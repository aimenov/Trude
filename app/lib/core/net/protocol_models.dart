/// Plain Dart models for the wire payloads in docs/protocol.md.
/// All fromJson factories take deep-converted `Map<String, dynamic>` maps as
/// produced by RoomConnection.
library;

int _int(dynamic v) => (v as num).toInt();
int? _intOrNull(dynamic v) => v == null ? null : (v as num).toInt();

Map<String, dynamic> _map(dynamic v) => (v as Map).cast<String, dynamic>();

List<Map<String, dynamic>> _mapList(dynamic v) =>
    (v as List? ?? const []).map(_map).toList();

/// `{ id, rank, suit? }` — rank is `"2".."10" | "J" | "Q" | "K" | "A" | "JOKER"`.
class Card {
  Card({required this.id, required this.rank, this.suit});

  factory Card.fromJson(Map<String, dynamic> json) => Card(
        id: json['id'] as String,
        rank: json['rank'] as String,
        suit: json['suit'] as String?,
      );

  final String id;
  final String rank;
  final String? suit;

  bool get isJoker => rank == 'JOKER';

  @override
  String toString() => 'Card($id $rank${suit ?? ''})';
}

/// `POST /auth/guest` response.
class GuestSession {
  GuestSession({
    required this.token,
    required this.userId,
    required this.nickname,
    required this.avatar,
  });

  factory GuestSession.fromJson(Map<String, dynamic> json) => GuestSession(
        token: json['token'] as String,
        userId: json['userId'] as String,
        nickname: json['nickname'] as String,
        avatar: json['avatar'] as String,
      );

  final String token;
  final String userId;
  final String nickname;
  final String avatar;
}

class RoomConfig {
  RoomConfig({
    required this.deckSize,
    required this.turnTimerSec,
    required this.maxPlayers,
  });

  factory RoomConfig.fromJson(Map<String, dynamic> json) => RoomConfig(
        deckSize: _int(json['deckSize']),
        turnTimerSec: _int(json['turnTimerSec']),
        maxPlayers: _int(json['maxPlayers']),
      );

  final int deckSize;
  final int turnTimerSec;
  final int maxPlayers;
}

class WirePlayer {
  WirePlayer({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.seat,
    required this.cardCount,
    required this.connected,
    required this.autoPilot,
    required this.isOut,
    required this.isAdmin,
  });

  factory WirePlayer.fromJson(Map<String, dynamic> json) => WirePlayer(
        userId: json['userId'] as String,
        nickname: json['nickname'] as String,
        avatar: json['avatar'] as String,
        seat: _int(json['seat']),
        cardCount: _int(json['cardCount']),
        connected: json['connected'] as bool,
        autoPilot: json['autoPilot'] as bool,
        isOut: json['isOut'] as bool,
        isAdmin: json['isAdmin'] as bool,
      );

  final String userId;
  final String nickname;
  final String avatar;
  final int seat;
  final int cardCount;
  final bool connected;
  final bool autoPilot;
  final bool isOut;
  final bool isAdmin;
}

class PileGroup {
  PileGroup({required this.seat, required this.count});

  factory PileGroup.fromJson(Map<String, dynamic> json) =>
      PileGroup(seat: _int(json['seat']), count: _int(json['count']));

  final int seat;
  final int count;
}

class PileState {
  PileState({required this.rank, required this.totalCount, required this.groups});

  factory PileState.fromJson(Map<String, dynamic> json) => PileState(
        rank: json['rank'] as String?,
        totalCount: _int(json['totalCount']),
        groups: _mapList(json['groups']).map(PileGroup.fromJson).toList(),
      );

  final String? rank;
  final int totalCount;
  final List<PileGroup> groups;
}

class TurnInfo {
  TurnInfo({required this.seat, required this.phase, required this.deadlineTs});

  factory TurnInfo.fromJson(Map<String, dynamic> json) => TurnInfo(
        seat: _int(json['seat']),
        phase: json['phase'] as String,
        deadlineTs: _int(json['deadlineTs']),
      );

  final int seat;

  /// `"lead"` or `"respond"`.
  final String phase;

  /// Epoch ms, server clock.
  final int deadlineTs;
}

/// `stateFull` — full resync snapshot, sent on join/reconnect.
class StateFull {
  StateFull({
    required this.actionCount,
    required this.phase,
    required this.config,
    required this.roomCode,
    required this.players,
    required this.pile,
    required this.lastThrowSeat,
    required this.mustCheck,
    required this.retiredRanks,
    required this.discarded,
    required this.turn,
    required this.hand,
    required this.lastResolution,
    required this.loserSeat,
  });

  factory StateFull.fromJson(Map<String, dynamic> json) => StateFull(
        actionCount: _int(json['actionCount']),
        phase: json['phase'] as String,
        config: RoomConfig.fromJson(_map(json['config'])),
        roomCode: json['roomCode'] as String?,
        players: _mapList(json['players']).map(WirePlayer.fromJson).toList(),
        pile: PileState.fromJson(_map(json['pile'])),
        lastThrowSeat: _intOrNull(json['lastThrowSeat']),
        mustCheck: json['mustCheck'] as bool,
        retiredRanks:
            (json['retiredRanks'] as List? ?? const []).cast<String>(),
        discarded: _mapList(json['discarded']).map(Card.fromJson).toList(),
        turn: json['turn'] == null ? null : TurnInfo.fromJson(_map(json['turn'])),
        hand: _mapList(json['hand']).map(Card.fromJson).toList(),
        lastResolution: json['lastResolution'] == null
            ? null
            : EventBatch.fromJson(_map(json['lastResolution'])),
        loserSeat: _intOrNull(json['loserSeat']),
      );

  final int actionCount;

  /// `"lobby" | "playing" | "finished"`.
  final String phase;
  final RoomConfig config;
  final String? roomCode;
  final List<WirePlayer> players;
  final PileState pile;
  final int? lastThrowSeat;
  final bool mustCheck;
  final List<String> retiredRanks;
  final List<Card> discarded;
  final TurnInfo? turn;
  final List<Card> hand;
  final EventBatch? lastResolution;
  final int? loserSeat;
}

/// `hand` — full private hand snapshot.
class HandSnapshot {
  HandSnapshot({required this.cards});

  factory HandSnapshot.fromJson(Map<String, dynamic> json) => HandSnapshot(
        cards: _mapList(json['cards']).map(Card.fromJson).toList(),
      );

  final List<Card> cards;
}

/// `events { actionCount, events: [...] }` — ordered event batch.
class EventBatch {
  EventBatch({required this.actionCount, required this.events});

  factory EventBatch.fromJson(Map<String, dynamic> json) => EventBatch(
        actionCount: _int(json['actionCount']),
        events: _mapList(json['events']).map(WireEvent.fromJson).toList(),
      );

  final int actionCount;
  final List<WireEvent> events;
}

/// Base class for the entries of an event batch. Known types decode to typed
/// subclasses; anything else falls back to [GenericEvent] with the raw map.
sealed class WireEvent {
  WireEvent(this.raw);

  factory WireEvent.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String?) {
      case 'gameStarted':
        return GameStartedEvent.fromJson(json);
      case 'turnStarted':
        return TurnStartedEvent.fromJson(json);
      case 'cardsThrown':
        return CardsThrownEvent.fromJson(json);
      case 'checkResult':
        return CheckResultEvent.fromJson(json);
      case 'fourDiscarded':
        return FourDiscardedEvent.fromJson(json);
      case 'playerOut':
        return PlayerOutEvent.fromJson(json);
      case 'gameOver':
        return GameOverEvent.fromJson(json);
      default:
        return GenericEvent(json);
    }
  }

  final Map<String, dynamic> raw;

  String get type => raw['type'] as String;
}

/// Any event this layer has no dedicated model for (playerJoined, autoPilot,
/// reaction, roomConfigured, ...) — fields available via [raw].
class GenericEvent extends WireEvent {
  GenericEvent(super.raw);
}

class GameStartedEvent extends WireEvent {
  GameStartedEvent.fromJson(super.json)
      : deckSize = _int(json['deckSize']),
        seatOrder = _mapList(json['seatOrder'])
            .map((e) => SeatOrderEntry.fromJson(e))
            .toList(),
        handCounts =
            (json['handCounts'] as List).map((e) => _int(e)).toList();

  final int deckSize;
  final List<SeatOrderEntry> seatOrder;
  final List<int> handCounts;
}

class SeatOrderEntry {
  SeatOrderEntry({required this.seat, required this.userId});

  factory SeatOrderEntry.fromJson(Map<String, dynamic> json) =>
      SeatOrderEntry(seat: _int(json['seat']), userId: json['userId'] as String);

  final int seat;
  final String userId;
}

class TurnStartedEvent extends WireEvent {
  TurnStartedEvent.fromJson(super.json)
      : seat = _int(json['seat']),
        phase = json['phase'] as String,
        mustCheck = json['mustCheck'] as bool,
        deadlineTs = _int(json['deadlineTs']);

  final int seat;

  /// `"lead"` or `"respond"`.
  final String phase;
  final bool mustCheck;
  final int deadlineTs;
}

class CardsThrownEvent extends WireEvent {
  CardsThrownEvent.fromJson(super.json)
      : seat = _int(json['seat']),
        count = _int(json['count']),
        rank = json['rank'] as String,
        isLead = json['isLead'] as bool;

  final int seat;
  final int count;
  final String rank;
  final bool isLead;
}

class CheckResultEvent extends WireEvent {
  CheckResultEvent.fromJson(super.json)
      : checkerSeat = _int(json['checkerSeat']),
        targetSeat = _int(json['targetSeat']),
        flipIndex = _int(json['flipIndex']),
        flipped = Card.fromJson(_map(json['flipped'])),
        matched = json['matched'] as bool,
        pickerSeat = _int(json['pickerSeat']),
        pickedCount = _int(json['pickedCount']),
        nextLeadSeat = _int(json['nextLeadSeat']);

  final int checkerSeat;
  final int targetSeat;
  final int flipIndex;
  final Card flipped;
  final bool matched;
  final int pickerSeat;
  final int pickedCount;
  final int nextLeadSeat;
}

class FourDiscardedEvent extends WireEvent {
  FourDiscardedEvent.fromJson(super.json)
      : seat = _int(json['seat']),
        rank = json['rank'] as String,
        cards = _mapList(json['cards']).map(Card.fromJson).toList();

  final int seat;
  final String rank;
  final List<Card> cards;
}

class PlayerOutEvent extends WireEvent {
  PlayerOutEvent.fromJson(super.json) : seat = _int(json['seat']);

  final int seat;
}

class GameOverEvent extends WireEvent {
  GameOverEvent.fromJson(super.json)
      : loserSeat = _int(json['loserSeat']),
        loserUserId = json['loserUserId'] as String,
        jokerCard = Card.fromJson(_map(json['jokerCard'])),
        placements =
            _mapList(json['placements']).map(PlacementEntry.fromJson).toList(),
        stats = json['stats'];

  final int loserSeat;
  final String loserUserId;
  final Card jokerCard;
  final List<PlacementEntry> placements;

  /// Per-player stats, kept raw. docs/protocol.md sketches a list of stat
  /// objects but the server currently sends the engine's map keyed by userId
  /// — so this stays untyped until the shape is pinned down.
  final dynamic stats;
}

class PlacementEntry {
  PlacementEntry({required this.userId, required this.seat, required this.placement});

  factory PlacementEntry.fromJson(Map<String, dynamic> json) => PlacementEntry(
        userId: json['userId'] as String,
        seat: _int(json['seat']),
        placement: _int(json['placement']),
      );

  final String userId;
  final int seat;
  final int placement;
}

/// Game-level `error` message (`{ code, message }`).
class GameError {
  GameError({required this.code, required this.message});

  factory GameError.fromJson(Map<String, dynamic> json) => GameError(
        code: json['code'] as String,
        message: (json['message'] as String?) ?? '',
      );

  final String code;
  final String message;

  @override
  String toString() => 'GameError($code): $message';
}

class PongMessage {
  PongMessage({required this.t, required this.serverT});

  factory PongMessage.fromJson(Map<String, dynamic> json) =>
      PongMessage(t: _int(json['t']), serverT: _int(json['serverT']));

  final int t;
  final int serverT;
}

/// Broadcast `reaction { seat, emoji }`.
class ReactionMessage {
  ReactionMessage({required this.seat, required this.emoji});

  factory ReactionMessage.fromJson(Map<String, dynamic> json) =>
      ReactionMessage(seat: _int(json['seat']), emoji: json['emoji'] as String);

  final int seat;
  final String emoji;
}

/// `seatSwapRequested { fromSeat, fromUserId }` (sent only to the target).
class SeatSwapRequest {
  SeatSwapRequest({required this.fromSeat, required this.fromUserId});

  factory SeatSwapRequest.fromJson(Map<String, dynamic> json) => SeatSwapRequest(
        fromSeat: _int(json['fromSeat']),
        fromUserId: json['fromUserId'] as String,
      );

  final int fromSeat;
  final String fromUserId;
}

/// `achievementUnlocked { key, title, description }`.
class AchievementUnlocked {
  AchievementUnlocked({
    required this.key,
    required this.title,
    required this.description,
  });

  factory AchievementUnlocked.fromJson(Map<String, dynamic> json) =>
      AchievementUnlocked(
        key: json['key'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
      );

  final String key;
  final String title;
  final String description;
}
