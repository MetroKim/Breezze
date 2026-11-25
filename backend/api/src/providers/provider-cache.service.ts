import { Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

/**
 * Best-effort shared provider cache. Redis is an optimization, never the
 * source of truth: provider requests continue when Redis is unavailable.
 */
@Injectable()
export class ProviderCacheService implements OnModuleDestroy {
  private readonly redis: Redis;

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

  async get<T>(key: string): Promise<T | null> {
    try {
      if (this.redis.status === 'wait') await this.redis.connect();
      const value = await this.redis.get(key);
      return value ? JSON.parse(value) as T : null;
    } catch {
      return null;
    }
  }

  async set(key: string, value: unknown, ttlSeconds: number): Promise<void> {
    try {
      if (this.redis.status === 'wait') await this.redis.connect();
      await this.redis.set(key, JSON.stringify(value), 'EX', ttlSeconds);
    } catch {
      // Cache failure must never take down catalog discovery.
    }
  }

  /**
   * Reserve one official-provider search request across every API replica.
   * Google's 2026 search.list quota is a separate daily bucket. Fail closed
   * if Redis is down: a transient cache outage must not burn the user's key.
   */
  async reserveDailyProviderRequest(namespace: string, limit: number): Promise<boolean> {
    if (!/^[a-z0-9:_-]{2,80}$/.test(namespace) ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      return false;
    }
    const day = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Los_Angeles', year: 'numeric',
      month: '2-digit', day: '2-digit',
    }).format(new Date());
    const key = 'provider:quota:' + namespace + ':' + day;
    try {
      if (this.redis.status === 'wait') await this.redis.connect();
      const reserved = await this.redis.eval(
        "local c=redis.call('INCR',KEYS[1]); if c==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return c",
        1, key, 27 * 3600,
      ) as number;
      return Number.isInteger(reserved) && reserved <= limit;
    } catch {
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.redis.status === 'ready') await this.redis.quit();
    else this.redis.disconnect();
  }
}
