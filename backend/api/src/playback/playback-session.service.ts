import {
  ConflictException,
  GoneException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { PlaybackResolveService } from './playback-resolve.service';

const SESSION_TTL_MS = 2 * 60 * 60 * 1000;
const MAX_HEARTBEAT_CREDIT_MS = 30_000;

export interface StartPlaybackSessionInput {
  trackId?: string;
  providerId?: string;
  providerTrackId?: string;
  canonicalTrackId?: string;
}

@Injectable()
export class PlaybackSessionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly resolver: PlaybackResolveService,
  ) {}

  async start(userId: string, territory: string | undefined, input: StartPlaybackSessionInput) {
    if (!territory || !/^[A-Za-z]{2}$/.test(territory.trim())) {
      throw new ConflictException('PLAYBACK_TERRITORY_UNAVAILABLE');
    }
    const country = territory.trim().toUpperCase();
    let trackId: string;
    let providerId: string | null = null;
    let playback: Record<string, unknown>;

    if (input.providerId || input.providerTrackId || input.canonicalTrackId) {
      if (!input.providerId || !input.providerTrackId || !input.canonicalTrackId || input.trackId) {
        throw new ConflictException('INVALID_PROVIDER_SESSION_REQUEST');
      }
      trackId = input.canonicalTrackId;
      providerId = input.providerId;
      playback = await this.resolver.resolveProvider(userId, {
        providerId: input.providerId,
        providerTrackId: input.providerTrackId,
        canonicalTrackId: input.canonicalTrackId,
      }, country);
    } else {
      if (!input.trackId) throw new ConflictException('TRACK_ID_REQUIRED');
      trackId = input.trackId;
      playback = await this.resolver.resolve(userId, { trackId }, country);
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + SESSION_TTL_MS);
    const session = await this.prisma.playbackSession.create({
      data: {
        userId,
        trackId,
        providerId,
        territory: country,
        startedAt: now,
        lastHeartbeatAt: now,
        expiresAt,
      },
      select: { id: true, startedAt: true, expiresAt: true, territory: true },
    });
    return { ...session, playback };
  }

  async heartbeat(userId: string, sessionId: string, eventId: string, sequence: number) {
    const priorEvent = await this.prisma.playbackHeartbeat.findUnique({
      where: { id: eventId },
      select: { sessionId: true, sequence: true, elapsedMs: true },
    });
    if (priorEvent) {
      if (priorEvent.sessionId !== sessionId || priorEvent.sequence !== sequence) {
        throw new ConflictException('PLAYBACK_HEARTBEAT_ID_CONFLICT');
      }
      return { accepted: true, duplicate: true, creditedMs: priorEvent.elapsedMs };
    }

    const now = new Date();
    try {
      return await this.prisma.$transaction(async (tx) => {
        const session = await tx.playbackSession.findUnique({
          where: { id: sessionId },
        });
        if (!session || session.userId !== userId) {
          throw new NotFoundException('PLAYBACK_SESSION_NOT_FOUND');
        }
        if (session.status !== 'active' || session.expiresAt <= now) {
          throw new GoneException('PLAYBACK_SESSION_EXPIRED');
        }
        if (!Number.isInteger(sequence) || sequence !== session.lastSequence + 1) {
          throw new ConflictException('PLAYBACK_HEARTBEAT_SEQUENCE_INVALID');
        }

        // Credit only server-observed wall time, capped per heartbeat. A client
        // cannot claim an arbitrary duration by sending a large playedMs value.
        const elapsedMs = Math.max(0, Math.min(
          MAX_HEARTBEAT_CREDIT_MS,
          now.getTime() - session.lastHeartbeatAt.getTime(),
        ));
        const updated = await tx.playbackSession.updateMany({
          where: {
            id: sessionId,
            userId,
            status: 'active',
            lastSequence: session.lastSequence,
            expiresAt: { gt: now },
          },
          data: {
            lastSequence: sequence,
            lastHeartbeatAt: now,
            accumulatedMs: { increment: elapsedMs },
          },
        });
        if (updated.count !== 1) {
          throw new ConflictException('PLAYBACK_HEARTBEAT_RACE');
        }
        await tx.playbackHeartbeat.create({
          data: { id: eventId, sessionId, sequence, elapsedMs },
        });
        const total = await tx.playbackSession.findUnique({
          where: { id: sessionId },
          select: { accumulatedMs: true },
        });
        return {
          accepted: true,
          duplicate: false,
          creditedMs: elapsedMs,
          accumulatedMs: total?.accumulatedMs ?? elapsedMs,
        };
      });
    } catch (error) {
      if (error && typeof error === 'object' && 'code' in error && error.code === 'P2002') {
        const raced = await this.prisma.playbackHeartbeat.findUnique({
          where: { id: eventId },
          select: { sessionId: true, sequence: true, elapsedMs: true },
        });
        if (raced?.sessionId === sessionId && raced.sequence === sequence) {
          return { accepted: true, duplicate: true, creditedMs: raced.elapsedMs };
        }
        throw new ConflictException('PLAYBACK_HEARTBEAT_ID_CONFLICT');
      }
      throw error;
    }
  }

  async stop(userId: string, sessionId: string) {
    return this.prisma.$transaction(async (tx) => {
      const session = await tx.playbackSession.findUnique({ where: { id: sessionId } });
      if (!session || session.userId !== userId) {
        throw new NotFoundException('PLAYBACK_SESSION_NOT_FOUND');
      }
      if (session.status === 'stopped') {
        const event = await tx.listeningEvent.findUnique({
          where: { id: sessionId },
          select: { id: true },
        });
        return { stopped: true, duplicate: true, qualifiedPlayRecorded: Boolean(event) };
      }
      const stopped = await tx.playbackSession.updateMany({
        where: { id: sessionId, userId, status: 'active' },
        data: { status: 'stopped', stoppedAt: new Date() },
      });
      if (stopped.count !== 1) {
        const latest = await tx.playbackSession.findUnique({ where: { id: sessionId } });
        const event = await tx.listeningEvent.findUnique({
          where: { id: sessionId },
          select: { id: true },
        });
        if (latest?.status === 'stopped') {
          return { stopped: true, duplicate: true, qualifiedPlayRecorded: Boolean(event) };
        }
        throw new ConflictException('PLAYBACK_SESSION_STOP_RACE');
      }
      const qualified = session.accumulatedMs >= 30_000;
      if (qualified) {
        await tx.listeningEvent.create({
          data: {
            id: session.id,
            userId,
            trackId: session.trackId,
            playedMs: session.accumulatedMs,
          },
        });
        await tx.recentlyPlayed.upsert({
          where: { userId_trackId: { userId, trackId: session.trackId } },
          create: { userId, trackId: session.trackId },
          update: { playedAt: new Date() },
        });
      }
      return {
        stopped: true,
        duplicate: false,
        qualifiedPlayRecorded: qualified,
        accumulatedMs: session.accumulatedMs,
      };
    });
  }
}
