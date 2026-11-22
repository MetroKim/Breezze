import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/database/breezze_database.dart';
import '../../../lib/core/database/playback_heartbeat_outbox_dao.dart';

void main() {
  late BreezzeDatabase database;
  late PlaybackHeartbeatOutboxDao dao;

  setUp(() {
    database = BreezzeDatabase(NativeDatabase.memory());
    dao = PlaybackHeartbeatOutboxDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('heartbeat retry is persisted and scoped to its account', () async {
    await dao.save(
      ownerId: 'user-a',
      sessionId: 'session-a',
      eventId: 'event-a',
      sequence: 4,
    );
    await dao.save(
      ownerId: 'user-b',
      sessionId: 'session-b',
      eventId: 'event-b',
      sequence: 2,
    );

    final userA = await dao.pending(ownerId: 'user-a');
    expect(userA, hasLength(1));
    expect(userA.single.sessionId, 'session-a');
    expect(userA.single.eventId, 'event-a');
    expect(userA.single.sequence, 4);
    expect(await dao.pending(ownerId: 'user-c'), isEmpty);
  });

  test('acknowledgement removes only the matching pending event', () async {
    await dao.save(
      ownerId: 'user-a',
      sessionId: 'session-a',
      eventId: 'event-one',
      sequence: 1,
    );
    await dao.save(
      ownerId: 'user-a',
      sessionId: 'session-a',
      eventId: 'event-two',
      sequence: 2,
    );

    await dao.remove(sessionId: 'session-a', eventId: 'event-one');

    final remaining = await dao.pending(ownerId: 'user-a');
    expect(remaining, hasLength(1));
    expect(remaining.single.eventId, 'event-two');
  });

  test('closing a session clears its retry records for one owner only', () async {
    await dao.save(
      ownerId: 'user-a',
      sessionId: 'session-a',
      eventId: 'event-a',
      sequence: 1,
    );
    await dao.save(
      ownerId: 'user-b',
      sessionId: 'session-a',
      eventId: 'event-b',
      sequence: 1,
    );

    await dao.removeSession(ownerId: 'user-a', sessionId: 'session-a');

    expect(await dao.pending(ownerId: 'user-a'), isEmpty);
    expect(await dao.pending(ownerId: 'user-b'), hasLength(1));
  });
}
