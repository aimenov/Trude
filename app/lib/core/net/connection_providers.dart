/// Riverpod providers owning the network stack: the [TrudeClient], the guest
/// session, the currently joined [TrudeRoom], and the [GameStateNotifier]
/// that folds server messages into a [ClientGameState].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/identity_providers.dart';
import 'client_game_state.dart';
import 'state_folding.dart';
import 'trude_client.dart';

export 'client_game_state.dart';
export 'trude_client.dart';

/// Server origin; override with `--dart-define=TRUDE_SERVER=http://host:port`.
const kServerBaseUrl =
    String.fromEnvironment('TRUDE_SERVER', defaultValue: 'http://127.0.0.1:2567');

final trudeClientProvider = Provider<TrudeClient>((ref) {
  final client = TrudeClient(kServerBaseUrl);
  ref.onDispose(client.close);
  return client;
});

/// Guest session (token + userId); null until [SessionController.ensure] ran.
final sessionProvider =
    NotifierProvider<SessionController, GuestSession?>(SessionController.new);

class SessionController extends Notifier<GuestSession?> {
  @override
  GuestSession? build() => null;

  /// Logs in as the persisted identity if not logged in yet.
  Future<GuestSession> ensure() async {
    final existing = state;
    if (existing != null) return existing;
    final identity = ref.read(identityProvider);
    if (identity == null) throw StateError('No guest identity yet');
    return loginAs(identity.nickname);
  }

  /// Persists [nickname] as the identity and logs in with it.
  Future<GuestSession> loginAs(String nickname) async {
    final identity = ref.read(identityProvider.notifier).setNickname(nickname);
    final session = await ref.read(trudeClientProvider).guestLogin(
          deviceId: identity.deviceId,
          nickname: identity.nickname,
        );
    state = session;
    return session;
  }
}

/// The game room the user is currently in (never the listing lobby room).
final currentRoomProvider =
    NotifierProvider<CurrentRoomController, TrudeRoom?>(CurrentRoomController.new);

class CurrentRoomController extends Notifier<TrudeRoom?> {
  @override
  TrudeRoom? build() => null;

  Future<TrudeRoom> createRoom({
    required String name,
    required bool private,
    required int deckSize,
  }) async {
    await ref.read(sessionProvider.notifier).ensure();
    final room = await ref
        .read(trudeClientProvider)
        .createRoom(name: name, private: private, deckSize: deckSize);
    return _adopt(room);
  }

  Future<TrudeRoom> joinById(String roomId) async {
    await ref.read(sessionProvider.notifier).ensure();
    return _adopt(await ref.read(trudeClientProvider).joinRoomById(roomId));
  }

  Future<TrudeRoom> joinByCode(String code) async {
    await ref.read(sessionProvider.notifier).ensure();
    return _adopt(await ref.read(trudeClientProvider).joinByCode(code));
  }

  Future<void> leaveRoom() async {
    final room = state;
    state = null;
    if (room != null) {
      try {
        await room.leave();
      } catch (_) {
        // The socket may already be gone; leaving is best-effort.
      }
    }
  }

  Future<TrudeRoom> _adopt(TrudeRoom room) async {
    final previous = state;
    if (previous != null) {
      try {
        await previous.leave();
      } catch (_) {}
    }
    state = room;
    // Drop the room from state when the server closes the socket.
    unawaited(room.onClose.then((_) {
      if (state == room) state = null;
    }));
    return room;
  }
}

/// Folded view of the current room, rebuilt whenever the room changes.
final gameStateProvider =
    NotifierProvider<GameStateNotifier, ClientGameState>(GameStateNotifier.new);

class GameStateNotifier extends Notifier<ClientGameState> {
  @override
  ClientGameState build() {
    final room = ref.watch(currentRoomProvider);
    if (room == null) return ClientGameState.empty;

    final subs = <StreamSubscription<dynamic>>[
      room.onStateFull.listen(_onStateFull),
      room.onHand.listen(_onHand),
      room.onEvents.listen(_onEvents),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });

    final snapshot = room.lastState;
    return snapshot == null ? ClientGameState.empty : _fold(snapshot);
  }

  String? get _myUserId => ref.read(sessionProvider)?.userId;

  void _onStateFull(StateFull s) =>
      state = _fold(s);

  void _onHand(HandSnapshot h) => state = state.copyWith(myHand: h.cards);

  ClientGameState _fold(StateFull s) =>
      foldStateFull(s, myUserId: _myUserId, previous: state);

  void _onEvents(EventBatch batch) {
    var next = state;
    for (final event in batch.events) {
      next = applyEventTo(next, event, myUserId: _myUserId);
    }
    state = next;
  }
}
