// Live, minimally invasive production acceptance test.
// Uses disposable accounts and deletes them in finally. No user data touched.
// Avoid printing access tokens, passwords, email addresses, or request bodies.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';

const baseUrl = process.env.BREEZZE_SMOKE_URL ??
  'https://breezze-api-edge.ykw8vmq7ph.workers.dev';
const suffix = randomUUID();
const users = [];
const pendingProblems = [];
let executed = 0;

function report(label) {
  executed += 1;
  process.stdout.write('PASS ' + String(executed).padStart(2, '0') +
    ': ' + label + '\n');
}

async function request(method, path, token, body) {
  const response = await fetch(baseUrl + path, {
    method,
    headers: {
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      'Cache-Control': 'no-store',
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(20000),
  });
  const text = await response.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; }
  catch { json = { error: 'NON_JSON_RESPONSE' }; }
  return { status: response.status, data: json.data ?? json };
}
function status(actual, expected, step) {
  assert.equal(actual, expected, step + ' returned HTTP ' + actual +
    ' instead of ' + expected);
}
async function register(label) {
  const user = {
    email: 'breezze-smoke-' + suffix + '-' + label + '@example.com',
    password: 'Breezze-QA-' + randomBytes(27).toString('base64url') + '!Aa1',
    token: null,
  };
  // Journal intended account BEFORE sending the request: registration might
  // commit on the server and then time out before we see its response.
  users.push(user);
  const res = await request('POST', '/api/v1/auth/register', null, {
    email: user.email,
    password: user.password,
    displayName: 'Breezze disposable acceptance test',
  });
  status(res.status, 201, label + ' account registration');
  assert.equal(typeof res.data.accessToken, 'string');
  assert.equal(typeof res.data.user?.id, 'string');
  user.token = res.data.accessToken;
  report('Disposable ' + label + ' created; account ID withheld');
  return user;
}

async function run() {
  const health = await request('GET', '/health');
  status(health.status, 200, 'health');
  assert.equal(health.data.status, 'ok');
  report('Production edge health');

  const noToken = await request('GET', '/api/v1/playlists');
  status(noToken.status, 401, 'unsigned playlist access');
  report('Unauthenticated playlist access rejected');

  // The production Supabase bridge must be configured, reachable and
  // reject counterfeit identity tokens rather than issuing a Breezze JWT.
  const counterfeit = await request(
    'POST', '/api/v1/auth/supabase/exchange', null,
    { accessToken: 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJxYSJ9.invalidsignature' },
  );
  status(counterfeit.status, 401, 'counterfeit Supabase session rejection');
  assert.equal(counterfeit.data.message, 'SUPABASE_TOKEN_REJECTED');
  report('Production Supabase bridge rejects a forged access token');

  const owner = await register('owner');
  const stranger = await register('other');

  const second = await request('POST', '/api/v1/auth/login', null, {
    email: owner.email, password: owner.password,
  });
  status(second.status, 200, 'second device login');
  const secondToken = second.data.accessToken;
  assert.equal(typeof secondToken, 'string');
  assert.notEqual(secondToken, owner.token);
  report('Two independently issued sessions for the same account');

  const id = randomUUID();
  const createBody = { id, name: 'Breezze temporary offline playlist' };
  const firstCreate = await request('POST', '/api/v1/playlists',
    owner.token, createBody);
  status(firstCreate.status, 201, 'first playlist creation');
  assert.equal(firstCreate.data.id, id);

  const retried = await request('POST', '/api/v1/playlists',
    secondToken, createBody);
  status(retried.status, 201, 'idempotent client-UUID retry');
  assert.equal(retried.data.id, id);
  const list = await request('GET', '/api/v1/playlists', owner.token);
  status(list.status, 200, 'owner list');
  assert.equal(list.data.filter(item => item.id === id).length, 1);
  report('Offline playlist UUID retry creates no duplicates');

  const foreignList = await request('GET', '/api/v1/playlists', stranger.token);
  status(foreignList.status, 200, 'other account list');
  assert.equal(foreignList.data.some(item => item.id === id), false);
  status((await request('GET', '/api/v1/playlists/' + id, stranger.token))
    .status, 404, 'foreign playlist read');
  status((await request('PATCH', '/api/v1/playlists/' + id,
    stranger.token, { name: 'not mine' })).status, 404,
    'foreign playlist rename');
  status((await request('DELETE', '/api/v1/playlists/' + id,
    stranger.token)).status, 404, 'foreign playlist deletion');
  status((await request('POST', '/api/v1/playlists', stranger.token,
    createBody)).status, 409, 'foreign playlist UUID claim');
  report('Other-account list/read/update/delete/ID-claim denied');

  const renamed = await request('PATCH', '/api/v1/playlists/' + id,
    secondToken, { name: 'Breezze QA synced on second device' });
  status(renamed.status, 200, 'second device rename');
  const refreshed = await request('GET', '/api/v1/playlists/' + id, owner.token);
  status(refreshed.status, 200, 'first device refresh');
  assert.equal(refreshed.data.name, 'Breezze QA synced on second device');
  report('Playlist rename propagates between independent sessions');

  // Use catalog tracks returned by Breezze's live metadata provider,
  // not fake test tracks. Canonical resolver is idempotent and caches these
  // legitimate catalog songs for normal listeners, while all QA playlists
  // and accounts are removed in finally.
  const discovered = await request('GET', '/api/v1/search?q=love',
    owner.token);
  status(discovered.status, 200, 'production song metadata search');
  const hits = discovered.data.externalTracks ?? [];
  assert.equal(Array.isArray(hits), true);
  const firstTwo = [];
  const seen = new Set();
  for (const hit of hits) {
    if (typeof hit.providerTrackId !== 'string' ||
        typeof hit.providerId !== 'string' ||
        typeof hit.title !== 'string' ||
        typeof hit.artist !== 'string' ||
        !(hit.durationSec > 0)) continue;
    const externalId = 'bz:' + hit.providerId + ':' + hit.providerTrackId;
    if (seen.has(externalId)) continue;
    seen.add(externalId);
    firstTwo.push({ ...hit, externalId });
    if (firstTwo.length === 2) break;
  }
  assert.equal(firstTwo.length, 2,
    'Two real provider songs required for playlist acceptance');

  const canonicalIds = [];
  for (const track of firstTwo) {
    const canonical = await request('POST', '/api/v1/catalog/resolve',
      owner.token, {
        externalId: track.externalId,
        source: track.providerId,
        title: track.title,
        artistName: track.artist,
        durationSec: Math.round(track.durationSec),
      });
    status(canonical.status, 201, 'production canonical song resolve');
    assert.match(canonical.data.id,
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    canonicalIds.push(canonical.data.id);
  }
  assert.notEqual(canonicalIds[0], canonicalIds[1]);
  report('Two real songs resolved to distinct canonical track IDs');

  const tracksRoute = '/api/v1/playlists/' + id + '/tracks';
  for (const canonicalId of canonicalIds) {
    status((await request('POST', tracksRoute, secondToken,
      { trackId: canonicalId })).status, 201, 'second-device track add');
  }
  status((await request('POST', tracksRoute, owner.token,
    { trackId: canonicalIds[0] })).status, 201, 'idempotent track add');
  status((await request('POST', tracksRoute, stranger.token,
    { trackId: canonicalIds[0] })).status, 404,
    'other-account track insertion');
  const hydrated = await request('GET',
    '/api/v1/playlists/' + id, owner.token);
  status(hydrated.status, 200, 'cross-session catalog hydration');
  assert.deepEqual(hydrated.data.items.map(item => item.trackId), canonicalIds);
  assert.equal(hydrated.data.items[0].track.title, firstTwo[0].title);
  assert.equal(hydrated.data.items[0].track.artist.name, firstTwo[0].artist);
  report('Two-song addition, idempotency, metadata hydration and isolation');

  const reverse = [...canonicalIds].reverse();
  const reorder = await request('PATCH',
    '/api/v1/playlists/' + id + '/tracks/order',
    owner.token, { trackIds: reverse });
  status(reorder.status, 200, 'reorder two real songs');
  assert.equal(reorder.data.reordered, true);
  const reorderedView = await request('GET',
    '/api/v1/playlists/' + id, secondToken);
  assert.deepEqual(reorderedView.data.items.map(item => item.trackId), reverse);
  status((await request('PATCH',
    '/api/v1/playlists/' + id + '/tracks/order',
    secondToken, { trackIds: [canonicalIds[0]] })).status, 400,
    'stale reorder membership should not override other device');
  report('Reordering propagates and stale membership is rejected');

  status((await request('DELETE', tracksRoute + '/' + canonicalIds[0],
    secondToken)).status, 200, 'remove real song');
  const removedView = await request('GET',
    '/api/v1/playlists/' + id, owner.token);
  assert.deepEqual(removedView.data.items.map(item => item.trackId),
    [canonicalIds[1]]);
  report('Removing a song propagates to the other session');

  const deleted = await request('DELETE', '/api/v1/playlists/' + id,
    owner.token);
  status(deleted.status, 200, 'owner playlist deletion');
  status((await request('GET', '/api/v1/playlists/' + id, secondToken))
    .status, 404, 'deleted playlist on second device');
  report('Playlist deletion propagates to second session');
}

try {
  await run();
} catch (error) {
  pendingProblems.push(error instanceof Error ? error.message : String(error));
  console.error('FAIL production playlist scenario; attempting cleanup');
} finally {
  for (const user of users.reverse()) {
    try {
      if (!user.token) {
        // Reconnect to clean an account that was created remotely but whose
        // registration response was lost. If login fails with bad
        // credentials, registration never completed and nothing was left.
        const recovered = await request('POST', '/api/v1/auth/login', null, {
          email: user.email, password: user.password,
        });
        if (recovered.status === 401) {
          report('No abandoned account after interrupted registration');
          continue;
        }
        status(recovered.status, 200, 'test-account cleanup recovery');
        user.token = recovered.data.accessToken;
      }
      const deleted = await request('DELETE', '/api/v1/users/me', user.token, {
        password: user.password,
      });
      status(deleted.status, 200, 'disposable user cleanup');
      assert.equal(deleted.data.deleted, true);
      const invalidated = await request('GET', '/api/v1/auth/me', user.token);
      status(invalidated.status, 401, 'deleted session invalidation');
      report('Disposable account removed and session invalidated');
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      pendingProblems.push('CLEANUP FAILURE: ' + reason);
      console.error('CLEANUP FAILURE: ' + reason);
    }
  }
}
if (pendingProblems.length) {
  for (const reason of pendingProblems) console.error('FAIL: ' + reason);
  process.exitCode = 1;
} else {
  console.info('PASS: production playlist cross-session smoke; synthetic users cleaned');
}
