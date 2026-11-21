import { HttpException, ServiceUnavailableException } from '@nestjs/common';
import { CloudflareAwareThrottlerGuard } from './cloudflare-aware-throttler.guard';

describe('CloudflareAwareThrottlerGuard', () => {
  let guard: CloudflareAwareThrottlerGuard;
  let redis: {
    status: string;
    eval: jest.Mock;
    quit: jest.Mock;
    disconnect: jest.Mock;
  };
  let response: { setHeader: jest.Mock };

  const context = (ip = '127.0.0.1', body: Record<string, unknown> = {}, url = '/api/v1/catalog') => ({
    switchToHttp: () => ({
      getRequest: () => ({ ip, body, method: 'POST', originalUrl: url, headers: {}, socket: {} }),
      getResponse: () => response,
    }),
  }) as any;

  beforeEach(() => {
    process.env.NODE_ENV = 'test';
    process.env.API_RATE_LIMIT = '1';
    process.env.API_RATE_WINDOW_MS = '60000';
    process.env.LOGIN_ACCOUNT_RATE_LIMIT = '1';
    process.env.LOGIN_ACCOUNT_RATE_WINDOW_MS = '900000';
    guard = new CloudflareAwareThrottlerGuard();
    redis = {
      status: 'ready',
      eval: jest.fn(),
      quit: jest.fn().mockResolvedValue('OK'),
      disconnect: jest.fn(),
    };
    (guard as any).redis = redis;
    response = { setHeader: jest.fn() };
  });

  afterEach(async () => {
    await guard.onModuleDestroy();
    delete process.env.API_RATE_LIMIT;
    delete process.env.API_RATE_WINDOW_MS;
    delete process.env.LOGIN_ACCOUNT_RATE_LIMIT;
    delete process.env.LOGIN_ACCOUNT_RATE_WINDOW_MS;
    delete process.env.NODE_ENV;
  });

  it('allows a request while its shared Redis counter is within quota', async () => {
    redis.eval.mockResolvedValue([1, 60000]);

    await expect(guard.canActivate(context())).resolves.toBe(true);
    expect(redis.eval).toHaveBeenCalledTimes(1);
  });

  it('rejects requests above quota and returns Retry-After', async () => {
    redis.eval.mockResolvedValue([2, 59001]);

    await expect(guard.canActivate(context())).rejects.toBeInstanceOf(HttpException);
    expect(response.setHeader).toHaveBeenCalledWith('Retry-After', '60');
  });

  it('applies a separate hashed account quota to login attempts', async () => {\n    process.env.API_RATE_LIMIT = '100';\n    process.env.LOGIN_ACCOUNT_RATE_LIMIT = '1';\n    redis.eval.mockResolvedValueOnce([1, 60000]).mockResolvedValueOnce([2, 899000]);\n\n    await expect(guard.canActivate(context('127.0.0.1', { email: 'Person@Example.com' }, '/api/v1/auth/login')))\n      .rejects.toBeInstanceOf(HttpException);\n    const accountKey = redis.eval.mock.calls[1][2] as string;\n    expect(accountKey).toContain('login-account:');\n    expect(accountKey).not.toContain('Person@Example.com');\n    expect(response.setHeader).toHaveBeenCalledWith('Retry-After', '899');\n  });\n\n  it('fails closed in production when Redis is unavailable', async () => {
    process.env.NODE_ENV = 'production';
    redis.eval.mockRejectedValue(new Error('redis unavailable'));

    await expect(guard.canActivate(context())).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('fails open in local development when Redis is unavailable', async () => {
    redis.eval.mockRejectedValue(new Error('redis unavailable'));

    await expect(guard.canActivate(context())).resolves.toBe(true);
  });
});
