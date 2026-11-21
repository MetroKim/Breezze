import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import * as crypto from 'node:crypto';
import { isIP } from 'node:net';

/**
 * Cloudflare terminates public traffic before it reaches NestJS. Express'
 * req.ip can therefore identify the Cloudflare hop rather than the listener.
 * Trust CF-Connecting-IP only on requests authenticated by the API Worker.
 */
@Injectable()
export class CloudflareAwareThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    const configuredSecret = process.env.EDGE_SHARED_SECRET;
    const suppliedSecret = req.headers?.['x-breezze-edge-secret'];
    const clientIp = req.headers?.['cf-connecting-ip'];

    const expected = Buffer.from(configuredSecret ?? '');
    const supplied = Buffer.from(typeof suppliedSecret === 'string' ? suppliedSecret : '');
    const authenticatedEdge = expected.length >= 32
      && supplied.length === expected.length
      && crypto.timingSafeEqual(supplied, expected);

    if (authenticatedEdge && typeof clientIp === 'string' && isIP(clientIp) !== 0) {
      return clientIp;
    }

    return req.ip ?? req.socket?.remoteAddress ?? 'unknown';
  }
}
