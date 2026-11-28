import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import {
  BadRequestException, Controller, Get, Head, Headers, NotFoundException,
  Param, Query, Req, Res, ServiceUnavailableException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { PrismaService } from '../prisma.service';
import { OpenSubsonicAdapter } from './opensubsonic.adapter';

/**
 * Public media delivery is authorized by a short-lived, account/recording/
 * territory-scoped HMAC grant issued AFTER the NestJS playback rights check.
 * Grant never contains an upstream key, password or origin.
 *
 * Request-range renewals recheck rights (including takedowns) immediately.
 * This route never allows arbitrary host, path, user ID or forwarded URL.
 */
@Controller('providers/opensubsonic/audio')
export class OpenSubsonicAudioController {
  constructor(
    private readonly adapter: OpenSubsonicAdapter,
    private readonly rights: RightsDecisionService,
    private readonly prisma: PrismaService,
  ) {}

  @Head(':id')
  async head(
    @Param('id') id: string,
    @Query('grant') token: string | undefined,
    @Headers('range') range: string | undefined,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    // Nest method decorators overwrite the route method metadata; use a
    // distinct handler so native audio HEAD probes cannot silently 404.
    await this.stream(id, token, range, req, res);
  }

  @Get(':id')
  async stream(
    @Param('id') id: string,
    @Query('grant') token: string | undefined,
    @Headers('range') range: string | undefined,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    const grant = this.adapter.verifyGrant(token ?? '', id);
    if (!grant) throw new NotFoundException('AUDIO_GRANT_INVALID');
    if (range != null && !/^bytes=\d+-\d*$/.test(range)) {
      throw new BadRequestException('AUDIO_RANGE_INVALID');
    }

    // A previously issued bearer grant is not proof that the canonical track
    // still maps to this upstream recording. A catalog correction or removal
    // must take effect immediately, including on existing seek/HEAD requests.
    const mapped = await this.prisma.track.findUnique({
      where: { id: grant.canonicalTrackId },
      select: { source: true, externalId: true },
    });
    if (mapped?.source !== 'opensubsonic' ||
        mapped.externalId !== 'bz:opensubsonic:' + id) {
      throw new NotFoundException('AUDIO_SOURCE_MAPPING_REVOKED');
    }

    const decision = await this.rights.decide({
      userId: grant.userId, trackId: grant.canonicalTrackId,
      territory: grant.territory, action: 'stream.full',
    });
    if (!decision.allowed || decision.previewOnly ||
        (decision.expiresAt && decision.expiresAt.getTime() <= Date.now())) {
      throw new NotFoundException('AUDIO_RIGHTS_UNAVAILABLE');
    }

    const upstream = await this.adapter.fetchAuthorizedBytes(id, range);
    if (!upstream || !OpenSubsonicAdapter.validMediaResponse(upstream, !!range)) {
      await upstream?.body?.cancel().catch(() => {});
      throw new ServiceUnavailableException('AUDIO_UPSTREAM_NOT_PLAYABLE');
    }

    if (range) {
      const matched = /^bytes (\d+)-(\d+)\/(\d+|\*)$/.exec(
        upstream.headers.get('content-range') ?? '');
      const requestedStart = Number(/^bytes=(\d+)-/.exec(range)![1]);
      const requestedEnd = /^bytes=\d+-(\d+)$/.exec(range);
      if (!matched || Number(matched[1]) !== requestedStart ||
          (requestedEnd && Number(matched[2]) > Number(requestedEnd[1]))) {
        await upstream.body?.cancel().catch(() => {});
        throw new ServiceUnavailableException('AUDIO_RANGE_MISMATCH');
      }
    }

    res.status(upstream.status);
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Type', upstream.headers.get('content-type')!);
    for (const header of ['content-range', 'content-length', 'accept-ranges', 'etag']) {
      const value = upstream.headers.get(header);
      if (value) res.setHeader(header, value);
    }
    if (req.method === 'HEAD') {
      await upstream.body?.cancel().catch(() => {});
      res.end();
      return;
    }
    // Streaming backpressure is managed by Node. No buffering the whole song.
    // Long-running bodies MUST NOT use the 15s connection/header deadline.
    res.setTimeout(45_000, () => res.destroy());
    try {
      await pipeline(Readable.fromWeb(upstream.body as never), res);
    } catch {
      if (!res.destroyed) res.destroy();
    }
  }
}
