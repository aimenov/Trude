import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'colyseus_lite/matchmake.dart';
import 'colyseus_lite/room_connection.dart';
import 'meta_models.dart';
import 'protocol_models.dart';

export 'colyseus_lite/matchmake.dart' show MatchmakeException;
export 'colyseus_lite/room_connection.dart' show RoomMessage, RoomProtocolError;
export 'meta_models.dart';
export 'protocol_models.dart';

/// Non-2xx response from the game's own HTTP API (/auth, /rooms, ...).
class TrudeApiException implements Exception {
  TrudeApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'TrudeApiException($statusCode): $body';
}

/// Thin facade over the Trude server: auth + room matchmaking.
class TrudeClient {
  TrudeClient(String baseUrl, {http.Client? httpClient})
      : baseUri = Uri.parse(baseUrl),
        _http = httpClient ?? http.Client() {
    _matchmake = MatchmakeClient(baseUri, httpClient: _http);
  }

  /// HTTP origin, e.g. `http://127.0.0.1:2567`.
  final Uri baseUri;
  final http.Client _http;
  late final MatchmakeClient _matchmake;

  /// JWT from [guestLogin]; sent as `options.token` on every room join.
  String? token;
  GuestSession? session;

  static const _jsonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  /// `GET /health` — true when the server answers `{ ok: true }`.
  Future<bool> healthCheck({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final res = await _http.get(baseUri.resolve('/health')).timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// `POST /auth/guest` — stores the token for subsequent room joins.
  Future<GuestSession> guestLogin({
    required String deviceId,
    required String nickname,
    String? avatar,
  }) async {
    final json = await _post('/auth/guest', {
      'deviceId': deviceId,
      'nickname': nickname,
      'avatar': ?avatar,
    });
    final s = GuestSession.fromJson(json);
    token = s.token;
    session = s;
    return s;
  }

  /// `GET /me` — profile + lifetime stats (Bearer).
  Future<MeProfile> getMe() async => MeProfile.fromJson(await _get('/me'));

  /// `GET /me/achievements` — unlocked keys + full catalog (Bearer).
  Future<MeAchievements> getAchievements() async =>
      MeAchievements.fromJson(await _get('/me/achievements'));

  /// `PATCH /me` — rename / re-avatar (profanity-checked server-side).
  Future<MeProfile> patchMe({String? nickname, String? avatar}) async {
    final res = await _http.patch(
      baseUri.resolve('/me'),
      headers: _authHeaders,
      body: jsonEncode({'nickname': ?nickname, 'avatar': ?avatar}),
    );
    return MeProfile.fromJson(_decode(res));
  }

  /// Creates a `trude` room and joins it (the creator becomes admin).
  Future<TrudeRoom> createRoom({
    String? name,
    bool private = false,
    int? deckSize,
    int? turnTimerSec,
    int? maxPlayers,
  }) async {
    final reservation = await _matchmake.create('trude', _roomOptions({
      'name': ?name,
      if (private) 'private': true,
      'deckSize': ?deckSize,
      'turnTimerSec': ?turnTimerSec,
      'maxPlayers': ?maxPlayers,
    }));
    return _consume(reservation);
  }

  Future<TrudeRoom> joinRoomById(String roomId) async =>
      _consume(await _matchmake.joinById(roomId, _roomOptions()));

  /// Joins the Colyseus built-in LobbyRoom (room name "lobby") for realtime
  /// room listings ('rooms' / '+' / '-' messages on [TrudeRoom.messages]).
  Future<TrudeRoom> joinLobby() async =>
      _consume(await _matchmake.joinOrCreate('lobby', _roomOptions()));

  /// `GET /rooms/by-code/:code` then joinById.
  Future<TrudeRoom> joinByCode(String code) async {
    final res =
        await _http.get(baseUri.resolve('/rooms/by-code/${code.toUpperCase()}'));
    if (res.statusCode != 200) {
      throw TrudeApiException(res.statusCode, res.body);
    }
    final roomId =
        (jsonDecode(res.body) as Map).cast<String, dynamic>()['roomId'] as String;
    return joinRoomById(roomId);
  }

  /// Reconnects using a [TrudeRoom.reconnectionToken] (`"roomId:token"`).
  Future<TrudeRoom> reconnect(String reconnectionToken) async =>
      _consume(await _matchmake.reconnect(reconnectionToken));

  Map<String, dynamic> _roomOptions([Map<String, dynamic> extra = const {}]) {
    final t = token;
    if (t == null) {
      throw StateError('Call guestLogin() before joining rooms');
    }
    return {'token': t, ...extra};
  }

  Future<TrudeRoom> _consume(SeatReservation reservation) async {
    final conn = await RoomConnection.connect(baseUri, reservation);
    return TrudeRoom._(conn);
  }

  Map<String, String> get _authHeaders {
    final t = token;
    if (t == null) {
      throw StateError('Call guestLogin() before authorized requests');
    }
    return {..._jsonHeaders, 'Authorization': 'Bearer $t'};
  }

  Future<Map<String, dynamic>> _get(String path) async =>
      _decode(await _http.get(baseUri.resolve(path), headers: _authHeaders));

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _http.post(baseUri.resolve(path),
        headers: _jsonHeaders, body: jsonEncode(body));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TrudeApiException(res.statusCode, res.body);
    }
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  void close() => _http.close();
}

/// A joined Trude room: typed message streams + action send helpers.
///
/// Tracks `actionCount` from incoming `events`/`stateFull` messages and
/// auto-increments `clientSeq`, so callers normally omit both.
class TrudeRoom {
  TrudeRoom._(this._conn) {
    _sub = _conn.messages.listen(_onMessage);
  }

  final RoomConnection _conn;
  late final StreamSubscription<RoomMessage> _sub;

  final _events = StreamController<EventBatch>.broadcast();
  final _hand = StreamController<HandSnapshot>.broadcast();
  final _state = StreamController<StateFull>.broadcast();
  final _errors = StreamController<GameError>.broadcast();
  final _pongs = StreamController<PongMessage>.broadcast();
  final _reactions = StreamController<ReactionMessage>.broadcast();
  final _swapRequests = StreamController<SeatSwapRequest>.broadcast();
  final _achievements = StreamController<AchievementUnlocked>.broadcast();
  final _firstState = Completer<StateFull>();

  /// Last event-batch/state actionCount seen; stamped onto outgoing actions.
  /// -1 while no game is running (lobby).
  int actionCount = -1;
  int _clientSeq = 0;

  StateFull? lastState;

  String get roomId => _conn.roomId;
  String get sessionId => _conn.sessionId;

  /// `"roomId:token"` — feed to [TrudeClient.reconnect] after a disconnect.
  String? get reconnectionToken => _conn.reconnectionToken;

  Stream<EventBatch> get onEvents => _events.stream;
  Stream<HandSnapshot> get onHand => _hand.stream;
  Stream<StateFull> get onStateFull => _state.stream;
  Stream<GameError> get onError => _errors.stream;
  Stream<PongMessage> get onPong => _pongs.stream;
  Stream<ReactionMessage> get onReaction => _reactions.stream;
  Stream<SeatSwapRequest> get onSeatSwapRequested => _swapRequests.stream;
  Stream<AchievementUnlocked> get onAchievement => _achievements.stream;

  /// Raw decoded messages (all types), for anything not covered above.
  Stream<RoomMessage> get messages => _conn.messages;

  /// Transport-level ERROR frames (rare; join/seat problems).
  Stream<RoomProtocolError> get onProtocolError => _conn.protocolErrors;

  /// The `stateFull` snapshot the server sends right after joining.
  Future<StateFull> get firstState => _firstState.future;

  Future<void> get onClose => _conn.onClose;

  void _onMessage(RoomMessage m) {
    final data = m.data is Map
        ? (m.data as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    switch (m.type) {
      case 'events':
        final batch = EventBatch.fromJson(data);
        // Lobby-phase batches carry actionCount -1 and must not regress a
        // running game's counter; a gameOver returns the room to the lobby.
        if (batch.actionCount >= 0) actionCount = batch.actionCount;
        if (batch.events.any((e) => e is GameOverEvent)) actionCount = -1;
        _events.add(batch);
      case 'hand':
        _hand.add(HandSnapshot.fromJson(data));
      case 'stateFull':
        final s = StateFull.fromJson(data);
        actionCount = s.actionCount;
        lastState = s;
        if (!_firstState.isCompleted) _firstState.complete(s);
        _state.add(s);
      case 'error':
        _errors.add(GameError.fromJson(data));
      case 'pong':
        _pongs.add(PongMessage.fromJson(data));
      case 'reaction':
        _reactions.add(ReactionMessage.fromJson(data));
      case 'seatSwapRequested':
        _swapRequests.add(SeatSwapRequest.fromJson(data));
      case 'achievementUnlocked':
        _achievements.add(AchievementUnlocked.fromJson(data));
      default:
        break; // unknown message types are still visible on [messages]
    }
  }

  // -- Send helpers ----------------------------------------------------------

  void _sendAction(String type, Map<String, dynamic> payload,
      {int? actionCountOverride, int? clientSeq}) {
    _conn.send(type, {
      'actionCount': actionCountOverride ?? actionCount,
      'clientSeq': clientSeq ?? _clientSeq++,
      ...payload,
    });
  }

  /// Returns the `clientSeq` stamped onto the action, so callers can key an
  /// optimistic hold on it (released on rejection / superseded by resync).
  int throwCards(List<String> cardIds,
      {String? rank, int? actionCount, int? clientSeq}) {
    final seq = clientSeq ?? _clientSeq++;
    _sendAction('throwCards', {
      'cardIds': cardIds,
      'rank': ?rank,
    }, actionCountOverride: actionCount, clientSeq: seq);
    return seq;
  }

  void check(int flipIndex, {int? actionCount, int? clientSeq}) {
    _sendAction('check', {'flipIndex': flipIndex},
        actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  void startGame({int? actionCount, int? clientSeq}) {
    _sendAction('startGame', const {},
        actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  void configureRoom(
      {int? deckSize,
      int? turnTimerSec,
      int? maxPlayers,
      int? actionCount,
      int? clientSeq}) {
    _sendAction('configureRoom', {
      'deckSize': ?deckSize,
      'turnTimerSec': ?turnTimerSec,
      'maxPlayers': ?maxPlayers,
    }, actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  void kickPlayer(String userId, {int? actionCount, int? clientSeq}) {
    _sendAction('kickPlayer', {'userId': userId},
        actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  void requestSeatSwap(String targetUserId, {int? actionCount, int? clientSeq}) {
    _sendAction('requestSeatSwap', {'targetUserId': targetUserId},
        actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  void respondSeatSwap({required bool accept, int? actionCount, int? clientSeq}) {
    _sendAction('respondSeatSwap', {'accept': accept},
        actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  void reaction(String emoji, {int? actionCount, int? clientSeq}) {
    _sendAction('reaction', {'emoji': emoji},
        actionCountOverride: actionCount, clientSeq: clientSeq);
  }

  // The timestamp is sent as a double: msgpack_dart encodes ints > 2^32 via
  // ByteData.setUint64, which throws UnsupportedError under dart2js (web).
  void ping() =>
      _conn.send('ping', {'t': DateTime.now().millisecondsSinceEpoch.toDouble()});

  /// Consented leave; the server frees the seat (or autopilots it mid-game).
  Future<void> leave() async {
    await _conn.leave();
    await _sub.cancel();
  }
}
