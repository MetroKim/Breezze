import { randomBytes, randomUUID } from 'node:crypto';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { PrismaClient } from '@prisma/client';
import { PrismaModule } from '../prisma.module';
import { AuthModule } from '../auth/auth.module';
import { PlaylistsModule } from './playlists.module';
import { ResponseEnvelopeInterceptor } from '../response-envelope.interceptor';

// Two simulated devices use distinct JWTs and real HTTP through Nest Passport,
// DTO validation, controllers, Prisma and PostgreSQL. No production accounts
// or external OAuth credentials are created.
const dbUrl = process.env.INTEGRATION_DATABASE_URL;
const describePostgres = dbUrl ? describe : describe.skip;

describePostgres('Authenticated playlist cross-device HTTP integration', () => {
  const prisma = new PrismaClient(
    dbUrl ? { datasources: { db: { url: dbUrl } } } : undefined,
  );
  const userIds: string[] = [];
  const artistIds: string[] = [];
  const trackIds: string[] = [];
  let app: INestApplication;
  let rootUrl: string;

  type ApiResult<T = unknown> = {
    status: number;
    data: T;
    error: string | undefined;
  };

  async function api<T = unknown>(
    path: string,
    method = 'GET',
    jwt?: string,
    body?: unknown,
  ): Promise<ApiResult<T>> {
    const response = await fetch(rootUrl + '/api/v1' + path, {
      method,
      headers: {
        ...(jwt ? { Authorization: 'Bearer ' + jwt } : {}),
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const result = (await response.json()) as Record<string, unknown>;
    return {
      status: response.status,
      data: ((result.data ?? result) as T),
      error: typeof result.message === 'string' ? result.message : undefined,
    };
  }

  async function account() {
    const email = 'playlist-ci-' + randomUUID() + '@example.com';
    const password = 'Test!' + randomBytes(16).toString('hex');
    const res = await api<{
      user: { id: string };
      accessToken: string;
    }>('/auth/register', 'POST', undefined, { email, password });
    expect(res.status).toBe(201);
    expect(res.data.accessToken).toEqual(expect.any(String));
    userIds.push(res.data.user.id);
    return { email, password, token: res.data.accessToken };
  }

  beforeAll(async () => {
    await prisma.$connect();
    const module = await Test.createTestingModule({
      imports: [PrismaModule, AuthModule, PlaylistsModule],
    }).compile();
    app = module.createNestApplication();
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }));
    app.useGlobalInterceptors(new ResponseEnvelopeInterceptor());
    await app.listen(0, '127.0.0.1');
    rootUrl = await app.getUrl();
  });

  afterAll(async () => {
    try {
      if (userIds.length > 0) {
        await prisma.user.deleteMany({ where: { id: { in: userIds } } });
      }
      if (trackIds.length > 0) {
        await prisma.track.deleteMany({ where: { id: { in: trackIds } } });
      }
      if (artistIds.length > 0) {
        await prisma.artist.deleteMany({ where: { id: { in: artistIds } } });
      }
    } finally {
      if (app) await app.close();
      await prisma.$disconnect();
    }
  });

  it('replays owner edits from device A to device B while isolating another user', async () => {
    const owner = await account();
    const intruder = await account();
    const deviceBLogin = await api<{ accessToken: string }>(
      '/auth/login',
      'POST',
      undefined,
      { email: owner.email, password: owner.password },
    );
    expect(deviceBLogin.status).toBe(200);
    const tokenA = owner.token;
    const tokenB = deviceBLogin.data.accessToken;
    const tokenOther = intruder.token;
    expect(tokenB).not.toEqual(tokenA);

    const artist = await prisma.artist.create({
      data: { name: 'Playlist CI artist ' + randomUUID() },
    });
    artistIds.push(artist.id);
    const first = await prisma.track.create({
      data: { title: 'Offline first', duration: 181, artistId: artist.id },
    });
    const second = await prisma.track.create({
      data: { title: 'Offline second', duration: 192, artistId: artist.id },
    });
    trackIds.push(first.id, second.id);

    expect((await api('/playlists')).status).toBe(401);
    expect((await api('/playlists', 'POST', tokenA, {
      id: 'invalid-id', name: 'Invalid',
    })).status).toBe(400);

    const playlistId = randomUUID();
    const payload = { id: playlistId, name: 'Offline replay' };

    // A timeout after server commit must be safely retryable from another
    // device without creating a duplicate or reverting an existing name.
    const created = await api<{ id: string }>('/playlists', 'POST', tokenA, payload);
    expect(created.status).toBe(201);
    expect(created.data.id).toBe(playlistId);

    const replay = await api<{ id: string }>(
      '/playlists', 'POST', tokenB, payload,
    );
    expect(replay.status).toBe(201);
    expect(replay.data.id).toBe(playlistId);
    expect((await api<unknown[]>('/playlists', 'GET', tokenA)).data).toHaveLength(1);
    expect((await api<unknown[]>('/playlists', 'GET', tokenB)).data).toHaveLength(1);

    // A different account cannot even infer private playlist details via
    // normal GET/mutation routes; the creator UUID may not be claimed.
    expect((await api<unknown[]>('/playlists', 'GET', tokenOther)).data).toEqual([]);
    expect((await api('/playlists/' + playlistId, 'GET', tokenOther)).status).toBe(404);
    expect((await api('/playlists/' + playlistId, 'PATCH', tokenOther,
      { name: 'Hijacked' })).status).toBe(404);
    expect((await api('/playlists', 'POST', tokenOther, payload)).status).toBe(409);
    expect((await api('/playlists/' + playlistId, 'DELETE', tokenOther)).status).toBe(404);

    // Pin is an owner-scoped, idempotent operation visible on device B.
    expect((await api('/playlists/' + playlistId + '/pin',
      'PATCH', tokenOther, { pinned: true })).status).toBe(404);
    expect((await api('/playlists/' + playlistId + '/pin',
      'PATCH', tokenA, { pinned: 'yes' })).status).toBe(400);
    const pinned = await api<{ isPinned: boolean }>(
      '/playlists/' + playlistId + '/pin',
      'PATCH', tokenA, { pinned: true },
    );
    expect(pinned.status).toBe(200);
    expect(pinned.data.isPinned).toBe(true);
    const pinOnDeviceB = await api<Array<{ id: string; isPinned: boolean }>>(
      '/playlists', 'GET', tokenB,
    );
    expect(pinOnDeviceB.data.find(p => p.id === playlistId)?.isPinned).toBe(true);
    const unpinned = await api<{ isPinned: boolean }>(
      '/playlists/' + playlistId + '/pin',
      'PATCH', tokenB, { pinned: false },
    );
    expect(unpinned.status).toBe(200);
    expect(unpinned.data.isPinned).toBe(false);

    // Persist canonical track metadata and ordered playlist items.
    const addFirst = await api('/playlists/' + playlistId + '/tracks',
      'POST', tokenA, { trackId: first.id });
    expect(addFirst.status).toBe(201);
    expect((await api('/playlists/' + playlistId + '/tracks',
      'POST', tokenB, { trackId: first.id })).status).toBe(201);
    expect((await api('/playlists/' + playlistId + '/tracks',
      'POST', tokenA, { trackId: second.id })).status).toBe(201);
    expect((await api('/playlists/' + playlistId + '/tracks',
      'POST', tokenOther, { trackId: second.id })).status).toBe(404);

    const hydrated = await api<{
      name: string;
      items: Array<{ trackId: string; position: number; track: {
        id: string; title: string; duration: number;
        artist: { name: string };
      } }>;
    }>('/playlists/' + playlistId, 'GET', tokenB);
    expect(hydrated.status).toBe(200);
    expect(hydrated.data.name).toBe('Offline replay');
    expect(hydrated.data.items.map(item => item.trackId)).toEqual([
      first.id, second.id,
    ]);
    expect(hydrated.data.items.map(item => item.position)).toEqual([0, 1]);
    expect(hydrated.data.items[0].track).toMatchObject({
      id: first.id,
      title: 'Offline first',
      duration: 181,
      artist: { name: artist.name },
    });

    const reordered = await api('/playlists/' + playlistId + '/tracks/order',
      'PATCH', tokenB, { trackIds: [second.id, first.id] });
    expect(reordered.status).toBe(200);
    expect((await api('/playlists/' + playlistId + '/tracks/order',
      'PATCH', tokenA, { trackIds: [first.id] })).status).toBe(400);
    expect((await api('/playlists/' + playlistId + '/tracks/order',
      'PATCH', tokenOther,
      { trackIds: [first.id, second.id] })).status).toBe(404);

    const afterReorder = await api<Array<{ items: Array<{
      trackId: string;
    }> }>>('/playlists', 'GET', tokenA);
    expect(afterReorder.data[0].items.map(item => item.trackId)).toEqual([
      second.id, first.id,
    ]);

    expect((await api('/playlists/' + playlistId, 'PATCH', tokenA,
      { name: 'Synced edit' })).status).toBe(200);
    expect((await api<{ name: string }>('/playlists/' + playlistId,
      'GET', tokenB)).data.name).toBe('Synced edit');

    expect((await api('/playlists/' + playlistId + '/tracks/' + first.id,
      'DELETE', tokenB)).status).toBe(200);
    expect((await api<{ items: Array<{ trackId: string }> }>(
      '/playlists/' + playlistId, 'GET', tokenA,
    )).data.items.map(item => item.trackId)).toEqual([second.id]);

    expect((await api('/playlists/' + playlistId,
      'DELETE', tokenA)).status).toBe(200);
    expect((await api('/playlists/' + playlistId,
      'GET', tokenB)).status).toBe(404);
    expect((await api<unknown[]>('/playlists', 'GET', tokenOther)).data).toEqual([]);
  }, 30_000);
});
