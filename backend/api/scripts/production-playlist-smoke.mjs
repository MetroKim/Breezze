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

  // M1 D1 public discovery: separate metadata results from playback grants.
  // These checks must run against the real deployed edge, not mocked sources.
  const shortSearch = await request('GET', '/api/v1/providers/search?q=a');
  status(shortSearch.status, 200, 'short catalog query');
  assert.equal(shortSearch.data.query, 'a');
  assert.deepEqual(shortSearch.data.providers, []);
  report('Federated search rejects one-character queries without upstream calls');

  const discovery = await request('GET', '/api/v1/providers/search?q=adele');
  status(discovery.status, 200, 'federated metadata discovery');
  assert.equal(discovery.data.query, 'adele');
  assert.ok(Array.isArray(discovery.data.providers),
    'federated discovery must return a provider-by-provider status list');
  const usableSources = discovery.data.providers.filter(row =>
    row && typeof row.providerId === 'string' &&
    row.result?.kind === 'ok' &&
    Array.isArray(row.result.value) &&
    row.result.value.some(track =>
      typeof track?.title === 'string' && track.title.trim() &&
      typeof track?.artist === 'string' && track.artist.trim()));
  assert.ok(usableSources.length > 0,
    'production discovery returned no real tracks from any music provider');
  report('Real federated discovery returns usable song metadata without assuming streaming rights');

  // D1 official video results must come from the deployed music-video
  // discovery service, with external-only playback explicitly declared.
  // Finding a YouTube ID is NOT permission to extract audio into Breezze.
  const videos = await request('GET',
    '/api/v1/discovery/videos?q=adele%20official%20music%20video');
  status(videos.status, 200, 'official music-video discovery');
  assert.ok(Array.isArray(videos.data.items), 'video search must return items');
  assert.ok(videos.data.items.length > 0,
    'deployed discovery returned no official music videos');
  for (const video of videos.data.items) {
    assert.match(video.id ?? '', /^[A-Za-z0-9_-]{11}$/,
      'each video must have a valid YouTube video ID');
    assert.equal(video.playback, 'external_youtube_only',
      'video metadata must not grant native music-stream rights');
  }
  report('Official music videos resolve with valid IDs and external-only playback rights');

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

  // Synthetic artist library acceptance: no artist media is retrieved,
  // and both test identities are automatically deleted during cleanup.
  const artistKey = 'apple:' +
    BigInt('0x' + randomBytes(6).toString('hex')).toString(10);
  const artistPath = '/api/v1/library/artists/' +
    encodeURIComponent(artistKey);
  const artistsPath = '/api/v1/library/artists';
  status((await request('GET', artistsPath)).status, 401,
    'artist list requires authentication');
  // The race caught by PostgreSQL CI must also pass against the deployed
  // API under simultaneous requests from two independently issued sessions.
  const concurrentFollows = await Promise.all([
    request('POST', artistPath, owner.token, {
      displayName: 'Breezze synthetic artist',
    }),
    request('POST', artistPath, secondToken, {
      displayName: 'Breezze synthetic artist',
    }),
    request('POST', artistPath, owner.token, {
      displayName: 'Breezze synthetic artist',
    }),
  ]);
  for (const response of concurrentFollows) {
    status(response.status, 201, 'concurrent artist follow');
  }
  report('Concurrent artist follows are idempotent under separate sessions');
  const artistList = await request('GET', artistsPath, secondToken);
  status(artistList.status, 200, 'second device followed artists');
  assert.equal(artistList.data.items.length, 1);
  assert.equal(artistList.data.items[0].artistKey, artistKey);
  assert.equal(artistList.data.items[0].isPinned, false);
  assert.equal((await request('GET', artistsPath, stranger.token))
    .data.items.length, 0);
  report('Artist follows are owner-isolated and cross-session');

  status((await request('PATCH', artistPath + '/pin', owner.token,
    { pinned: 'true' })).status, 400, 'invalid artist pin input');
  status((await request('PATCH', artistPath + '/pin', stranger.token,
    { pinned: true })).status, 404, 'foreign artist cannot be pinned');
  const pinnedArtist = await request('PATCH', artistPath + '/pin',
    owner.token, { pinned: true });
  status(pinnedArtist.status, 200, 'pin followed artist');
  assert.equal(pinnedArtist.data.isPinned, true);
  const artistOnSecond = await request('GET', artistsPath, secondToken);
  assert.equal(artistOnSecond.data.items[0].isPinned, true);
  status((await request('POST', artistPath, secondToken, {
    displayName: 'Breezze synthetic artist updated',
  })).status, 201, 'update metadata');
  assert.equal((await request('GET', artistPath, owner.token))
    .data.isPinned, true);
  status((await request('PATCH', artistPath + '/pin', secondToken,
    { pinned: false })).status, 200, 'unpin from second session');
  assert.equal((await request('GET', artistPath, owner.token))
    .data.isPinned, false);
  report('Artist pin/unpin reaches second device and survives metadata edits');

  status((await request('DELETE', artistPath, owner.token)).status, 200,
    'synthetic followed artist cleanup');
  assert.equal((await request('GET', artistsPath, secondToken))
    .data.items.length, 0);
  report('Synthetic artist removed with no listener data retained');

  // Owner-scoped B-Pin album acceptance uses only synthetic catalog bookmarks.
  // No playback grants or music downloads are requested.
  const pinAlbumId = BigInt('0x' + randomBytes(6).toString('hex')).toString(10);
  const otherAlbumId = BigInt('0x' + randomBytes(6).toString('hex')).toString(10);
  const albumsRoute = '/api/v1/library/albums';

  status((await request('GET', albumsRoute)).status, 401,
    'unsigned saved album access');
  const baseAlbum = {
    externalAlbumId: pinAlbumId, title: 'Disposable pinned album',
    artist: 'Breezze QA', genres: ['Synthetic'],
  };
  status((await request('POST', albumsRoute, owner.token, baseAlbum)).status,
    201, 'save synthetic album');
  status((await request('POST', albumsRoute, owner.token, {
    ...baseAlbum, externalAlbumId: otherAlbumId, title: 'Other synthetic album',
  })).status, 201, 'save second album');
  const unpinned = await request('GET', albumsRoute, secondToken);
  status(unpinned.status, 200, 'second session before pin');
  assert.deepEqual(unpinned.data.items.map(x => x.isPinned), [false, false]);
  assert.equal((await request('GET', albumsRoute, stranger.token))
    .data.items.length, 0);
  report('Saved album bookmarks are private and initially unpinned');

  const pin = await request('POST', albumsRoute, owner.token, {
    ...baseAlbum, isPinned: true,
  });
  status(pin.status, 201, 'pin saved album');
  assert.equal(pin.data.isPinned, true);
  const secondPinned = await request('GET', albumsRoute, secondToken);
  status(secondPinned.status, 200, 'pinned second session snapshot');
  assert.equal(secondPinned.data.items[0].externalAlbumId, pinAlbumId);
  assert.equal(secondPinned.data.items[0].isPinned, true);
  assert.equal(secondPinned.data.items[1].isPinned, false);
  report('Album pin moves to top and reaches a second authenticated session');

  const updateWithoutPin = await request('POST', albumsRoute,
    secondToken, { ...baseAlbum, title: 'Metadata-only updated title' });
  status(updateWithoutPin.status, 201, 'metadata-only album update');
  assert.equal(updateWithoutPin.data.isPinned, true);
  report('Metadata-only album update does not erase the remote pin');

  // Another user may bookmark the same public catalog ID but must never
  // inherit or modify this owner's private pin state.
  const strangerSave = await request('POST', albumsRoute,
    stranger.token, { ...baseAlbum, title: 'Independent catalog bookmark' });
  status(strangerSave.status, 201, 'other account private bookmark');
  const strangerView = await request('GET', albumsRoute, stranger.token);
  status(strangerView.status, 200, 'other account album listing');
  assert.equal(strangerView.data.items.length, 1);
  assert.equal(strangerView.data.items[0].isPinned, false);
  assert.equal(strangerView.data.items[0].title, 'Independent catalog bookmark');
  report('Same catalog ID has account-isolated metadata and pin settings');

  status((await request('POST', albumsRoute, owner.token, {
    ...baseAlbum, isPinned: 'yes',
  })).status, 400, 'invalid pinned type rejected');
  const unpin = await request('POST', albumsRoute, secondToken, {
    ...baseAlbum, isPinned: false,
  });
  status(unpin.status, 201, 'unpin saved album');
  assert.equal(unpin.data.isPinned, false);
  const finalPinned = await request('GET', albumsRoute, owner.token);
  status(finalPinned.status, 200, 'unpin reflected in owner session');
  assert.equal(finalPinned.data.items.every(item => !item.isPinned), true);
  assert.equal((await request('GET', albumsRoute, stranger.token))
    .data.items[0].isPinned, false);
  report('Unpin syncs between sessions and validates boolean input');

  for (const item of [pinAlbumId, otherAlbumId]) {
    status((await request('DELETE', albumsRoute + '/' + item,
      owner.token)).status, 200, 'owner pin smoke bookmark cleanup');
  }
  status((await request('DELETE', albumsRoute + '/' + pinAlbumId,
    stranger.token)).status, 200, 'other account pin smoke cleanup');
  assert.equal((await request('GET', albumsRoute, secondToken))
    .data.items.length, 0);
  report('Synthetic saved album bookmarks removed after acceptance');

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

  // Library/Favorites acceptance uses the SAME two disposable identities
  // and real catalog IDs. Never access or mutate real listeners' records.
  const favoritesRoute = '/api/v1/library/favorites';
  status((await request('GET', favoritesRoute)).status, 401,
    'unsigned cloud favorites');
  const favoriteId = canonicalIds[0];
  status((await request('POST', favoritesRoute, owner.token,
    { trackId: favoriteId })).status, 201, 'first-session favorite');
  status((await request('POST', favoritesRoute, secondToken,
    { trackId: favoriteId })).status, 201, 'idempotent second-session favorite');
  const onSecondDevice = await request('GET', favoritesRoute, secondToken);
  status(onSecondDevice.status, 200, 'second-session cloud favorites');
  assert.equal(onSecondDevice.data.filter(row => row.trackId === favoriteId).length, 1);
  assert.equal(onSecondDevice.data.find(row => row.trackId === favoriteId)
    ?.track?.title, firstTwo[0].title);
  report('Favorites add, idempotency and real track hydration across sessions');

  // M1 D3: two independently authenticated accounts must never share their
  // private Home rails. The same listener's second session must see both
  // their recent listening history and favorites.
  status((await request('GET', '/api/v1/home')).status, 401,
    'anonymous home feed');
  const recent = await request('POST', '/api/v1/home/recent',
    owner.token, { trackId: favoriteId });
  status(recent.status, 201, 'record owner-recent metadata');
  assert.equal(recent.data.recorded, true);
  const ownerFeed = await request('GET', '/api/v1/home', owner.token);
  const sameOwnerFeed = await request('GET', '/api/v1/home', secondToken);
  const strangerFeed = await request('GET', '/api/v1/home', stranger.token);
  for (const [label, feed] of [
    ['owner', ownerFeed], ['second session', sameOwnerFeed],
    ['unrelated account', strangerFeed],
  ]) {
    status(feed.status, 200, label + ' home feed');
    assert.ok(Array.isArray(feed.data), label + ' feed must be a list');
  }
  for (const feed of [ownerFeed, sameOwnerFeed]) {
    assert.ok(feed.data.some(section =>
      section.sectionType === 'favorites' &&
      section.trackIds.includes(favoriteId)));
    assert.ok(feed.data.some(section =>
      section.sectionType === 'recently_played' &&
      section.trackIds.includes(favoriteId)));
  }
  assert.equal(strangerFeed.data.some(section =>
    (section.sectionType === 'favorites' ||
      section.sectionType === 'recently_played') &&
    section.trackIds.includes(favoriteId)), false,
  'unrelated account must never see a listener\'s private Home music');
  report('Two-account production Home isolation and same-owner session sync');

  // M1 D5 negative real-production authorization: these tracks were
  // discovered in a metadata API and have no explicit full-stream right.
  // Never fabricate a grant just to turn this smoke green.
  const denied = await request('POST', '/api/v1/playback/sessions',
    owner.token, { trackId: favoriteId });
  status(denied.status, 406, 'unlicensed catalog full-stream rejection');
  assert.match(JSON.stringify(denied.data),
    /(NOT_AVAILABLE_IN_TERRITORY|NO_EXPLICIT_AUTHORIZATION|TAKEDOWN_ACTIVE|RIGHTS_EXPIRED)/,
    'unlicensed catalog track must fail at the canonical rights gate');
  assert.equal(denied.data.playback?.streamUrl, undefined);
  report('Catalog metadata cannot issue a signed or provider full-stream session');

  // M1 D5 positive production grant. The official Audius Open Music License
  // applies only to publicly API-streamable creator releases. This test
  // verifies fresh permission against the actual provider, our authenticated
  // session, transport delivery, ownership and session lifecycle. It does not
  // copy, download or rehost the recording.
  const publicAudio = await request('GET',
    '/api/v1/providers/audius/search?q=ambient');
  status(publicAudio.status, 200, 'Audius OML public discovery');
  assert.equal(publicAudio.data.kind, 'ok',
    'Audius is enabled and returns live artist-permitted music');
  const audiusTrack = publicAudio.data.value?.find(track =>
    typeof track?.providerTrackId === 'string' &&
    /^[A-Za-z0-9]{4,32}$/.test(track.providerTrackId) &&
    typeof track.title === 'string' && track.title.trim() &&
    typeof track.artist === 'string' && track.artist.trim() &&
    Number.isInteger(track.durationSec) && track.durationSec >= 1);
  assert.ok(audiusTrack, 'Audius must have a public OML recording for this test');

  const canonicalAudius = await request('POST', '/api/v1/catalog/resolve',
    owner.token, {
      externalId: 'bz:audius:' + audiusTrack.providerTrackId,
      source: 'audius',
      title: audiusTrack.title,
      artistName: audiusTrack.artist,
      durationSec: audiusTrack.durationSec,
    });
  status(canonicalAudius.status, 201, 'canonical Audius recording');
  let audiusSessionId = null;
  try {
    // One bounded retry is permitted only after a 503 from the read-only
    // upstream entitlement lookup. An HTTP 406 rights denial is final:
    // NEVER retry or bypass an artist's unavailable/gated recording.
    let grant;
    for (let attempt = 1; attempt <= 2; attempt++) {
      grant = await request('POST', '/api/v1/playback/sessions',
        owner.token, {
          providerId: 'audius',
          providerTrackId: audiusTrack.providerTrackId,
          canonicalTrackId: canonicalAudius.data.id,
        });
      if (grant.status !== 503 || attempt === 2) break;
      await new Promise(resolve => setTimeout(resolve, 750));
    }
    assert.equal(grant.status, 201,
      'authenticated Audius OML playback grant returned HTTP ' +
      grant.status + ' (' + String(grant.data?.message ?? grant.data?.code ?? 'unknown error').slice(0, 120) + ')');
    assert.equal(typeof grant.data.id, 'string');
    audiusSessionId = grant.data.id;
    assert.ok(grant.data.playback?.attribution?.startsWith('Audius OML:'),
      'licensed grant must preserve artist, source and OML attribution');
    const streamUrl = new URL(grant.data.playback.streamUrl);
    assert.equal(streamUrl.protocol, 'https:');
    assert.equal(streamUrl.hostname, 'api.audius.co');
    assert.equal(streamUrl.pathname,
      '/v1/tracks/' + audiusTrack.providerTrackId + '/stream');
    assert.ok(Date.parse(grant.data.playback.expiresAt) > Date.now(),
      'streaming grant must have a future expiry');

    const playable = await fetch(streamUrl, {
      headers: { Range: 'bytes=0-1023', Accept: 'audio/mpeg' },
      signal: AbortSignal.timeout(20_000),
    });
    assert.ok(playable.status === 200 || playable.status === 206,
      'Audius audio range request returned HTTP ' + playable.status);
    assert.match(playable.headers.get('content-type') ?? '',
      /audio\/(mpeg|mp3|mp4|aac|ogg)/i,
      'authorized stream must return actual playable audio');
    const reader = playable.body?.getReader();
    assert.ok(reader, 'authorized audio stream has a readable body');
    try {
      const firstBytes = await reader.read();
      assert.ok(firstBytes.value?.byteLength > 0,
        'the stream must deliver real audio bytes to a listener');
    } finally {
      await reader.cancel().catch(() => {});
    }
    report('Live Audius OML session grants a range-capable audio stream');

    const foreignPause = await request('POST',
      '/api/v1/playback/sessions/' + audiusSessionId + '/pause',
      stranger.token);
    status(foreignPause.status, 404, 'foreign playback-session pause');

    const beat = await request('POST',
      '/api/v1/playback/sessions/' + audiusSessionId + '/heartbeat',
      owner.token, { eventId: randomUUID(), sequence: 1 });
    status(beat.status, 200, 'licensed session heartbeat');
    assert.equal(beat.data.accepted, true);

    const paused = await request('POST',
      '/api/v1/playback/sessions/' + audiusSessionId + '/pause',
      owner.token);
    status(paused.status, 200, 'licensed playback pause');
    const resumed = await request('POST',
      '/api/v1/playback/sessions/' + audiusSessionId + '/resume',
      secondToken);
    status(resumed.status, 200, 'same-owner second-device playback resume');
    const stopped = await request('POST',
      '/api/v1/playback/sessions/' + audiusSessionId + '/stop',
      owner.token);
    status(stopped.status, 200, 'licensed playback stop');
    audiusSessionId = null;
    report('Live server-scoped playback heartbeat, ownership and stop');
  } finally {
    if (audiusSessionId) {
      await request('POST',
        '/api/v1/playback/sessions/' + audiusSessionId + '/stop',
        owner.token).catch(() => {});
    }
  }

  const otherBefore = await request('GET', favoritesRoute, stranger.token);
  status(otherBefore.status, 200, 'other-account cloud favorites');
  assert.equal(otherBefore.data.some(row => row.trackId === favoriteId), false);
  status((await request('DELETE', favoritesRoute + '/' + favoriteId,
    stranger.token)).status, 200, 'foreign favorite removal is owner-scoped');
  assert.equal((await request('GET', favoritesRoute, owner.token))
    .data.some(row => row.trackId === favoriteId), true);
  status((await request('POST', favoritesRoute, stranger.token,
    { trackId: favoriteId })).status, 201,
    'other user independently favorites same catalog track');
  status((await request('DELETE', favoritesRoute + '/' + favoriteId,
    owner.token)).status, 200, 'owner removes favorite');
  assert.equal((await request('GET', favoritesRoute, secondToken))
    .data.some(row => row.trackId === favoriteId), false);
  assert.equal((await request('GET', favoritesRoute, stranger.token))
    .data.some(row => row.trackId === favoriteId), true);
  status((await request('DELETE', favoritesRoute + '/' + favoriteId,
    stranger.token)).status, 200, 'other user clears own favorite');
  assert.equal((await request('GET', favoritesRoute, stranger.token))
    .data.some(row => row.trackId === favoriteId), false);
  report('Favorites cross-account isolation and removal propagated to second session');

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
