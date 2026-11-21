import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

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

    if (
      configuredSecret
      && typeof suppliedSecret === 'string'
      && suppliedSecret === configuredSecret
      && typeof clientIp === 'string'
      && clientIp.length > 0
      && clientIp.length <= 64
    ) {
      return clientIp;
    }

    return req.ip ?? req.socket?.remoteAddress ?? 'unknown';
  }
}
