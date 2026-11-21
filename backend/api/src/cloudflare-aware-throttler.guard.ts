import {
  CanActivate,
  ExecutionContext,
  HttpException,
  Injectable,
  OnModuleDestroy,
  ServiceUnavailableException,
} from '@nestjs/common';
import Redis from 'ioredis';
import { createHash, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';

/**
 * Shared, atomic fixed-window limiter. Every API replica uses the same Redis
 * counter, so horizontal scaling does not multiply the effective IP quota.
 *
 * Production deliberately fails closed when Redis is unavailable: silently
 * switching to per-process limits would make abuse limits unpredictable.
 */
@Injectable()
export class CloudflareAwareThrottlerGuard
  implements CanActivate, OnModuleDestroy
{
  private readonly redis: Redis;
  private readonly limit = Number(process.env.API_RATE_LIMIT ?? 100);
  private readonly windowMs = Number(process.env.API_RATE_WINDOW_MS ?? 60_000);

  private static readonly incrementScript = `
    local count = redis.call('INCR', KEYS[1])
    if count == 1 then
      redis.call('PEXPIRE', KEYS[1], ARGV[1])
    end
    local ttl = redis.call('PTTL', KEYS[1])
    return { count, ttl }
  `;

  constructor() {
    this.redis = new Redis(process.env.REDIS_URL ?? 'redis://127.0.0.1:6379', {
      lazyConnect: true,
      connectTimeout: 1000,
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
      retryStrategy: (attempt) => Math.min(attempt * 250, 2000),
    });
    this.redis.on('error', () => undefined);
  }

  private getClientIp(req: Record<string, any>): string {
    const configuredSecret = process.env.EDGE_SHARED_SECRET;
    const suppliedSecret = req.headers?.['x-breezze-edge-secret'];
    const clientIp = req.headers?.['cf-connecting-ip'];

    const expected = Buffer.from(configuredSecret ?? '');
    const supplied = Buffer.from(
      typeof suppliedSecret === 'string' ? suppliedSecret : '',
    );
    const authenticatedEdge =
      expected.length >= 32 &&
      supplied.length === expected.length &&
      timingSafeEqual(supplied, expected);

    if (
      authenticatedEdge &&
      typeof clientIp === 'string' &&
      isIP(clientIp) !== 0
    ) {
      return clientIp;
    }

    const directIp = req.ip ?? req.socket?.remoteAddress;
    return typeof directIp === 'string' && isIP(directIp) !== 0
      ? directIp
      : 'unknown';
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<Record<string, any>>();
    const ipDigest = createHash('sha256')
      .update(this.getClientIp(req))
      .digest('hex');
    const minuteBucket = Math.floor(Date.now() / this.windowMs);
    const key = `breezze:ratelimit:v1:${ipDigest}:${minuteBucket}`;

    try {
      if (this.redis.status === 'wait') await this.redis.connect();
      const result = (await this.redis.eval(
        CloudflareAwareThrottlerGuard.incrementScript,
        1,
        key,
        String(this.windowMs * 2),
      )) as [number | string, number | string];

      const count = Number(result[0]);
      const ttlMs = Math.max(1, Number(result[1]));
      if (count > this.limit) {
        throw new HttpException(
          {
            statusCode: 429,
            error: 'RATE_LIMIT_EXCEEDED',
            message: 'Too many requests. Please retry after the window resets.',
          },
          429,
          { cause: undefined },
        );
      }
      return true;
    } catch (error) {
      if (error instanceof HttpException) throw error;
      if (process.env.NODE_ENV !== 'production') return true;
      throw new ServiceUnavailableException(
        'Request protection is temporarily unavailable',
      );
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.redis.status === 'ready') await this.redis.quit();
    else this.redis.disconnect();
  }
}
