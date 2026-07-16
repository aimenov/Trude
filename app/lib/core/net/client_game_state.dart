/// Client-side projection of one room: stateFull snapshots + hand snapshots +
/// event batches folded into a single immutable view for the UI.
library;

import '../../features/game/logic/rules_view.dart';
import '../strings.dart';
import 'protocol_models.dart';

class PlayerView {
  const PlayerView({
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

  factory PlayerView.fromWire(WirePlayer p) => PlayerView(
        userId: p.userId,
        nickname: p.nickname,
        avatar: p.avatar,
        seat: p.seat,
        cardCount: p.cardCount,
        connected: p.connected,
        autoPilot: p.autoPilot,
        isOut: p.isOut,
        isAdmin: p.isAdmin,
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

  PlayerView copyWith({
    int? seat,
    int? cardCount,
    bool? connected,
    bool? autoPilot,
    bool? isOut,
    bool? isAdmin,
  }) =>
      PlayerView(
        userId: userId,
        nickname: nickname,
        avatar: avatar,
        seat: seat ?? this.seat,
        cardCount: cardCount ?? this.cardCount,
        connected: connected ?? this.connected,
        autoPilot: autoPilot ?? this.autoPilot,
        isOut: isOut ?? this.isOut,
        isAdmin: isAdmin ?? this.isAdmin,
      );
}

class TurnView {
  const TurnView({
    required this.seat,
    required this.phase,
    required this.mustCheck,
    required this.deadlineTs,
  });

  final int seat;

  /// `"lead"` or `"respond"`.
  final String phase;
  final bool mustCheck;

  /// Epoch ms, server clock.
  final int deadlineTs;
}

class ClientGameState {
  const ClientGameState({
    this.roomPhase = '',
    this.roomCode,
    this.deckSize = 37,
    this.turnTimerSec = 30,
    this.maxPlayers = 6,
    this.players = const [],
    this.pileRank,
    this.pileCount = 0,
    this.lastThrowCount = 0,
    this.lastThrowSeat,
    this.retiredRanks = const [],
    this.turn,
    this.mustCheck = false,
    this.myHand = const [],
    this.mySeat = -1,
    this.lastResults,
    this.lastEventText,
  });

  static const empty = ClientGameState();

  /// `''` (not in a room) | `'lobby'` | `'playing'` | `'finished'`.
  final String roomPhase;
  final String? roomCode;
  final int deckSize;
  final int turnTimerSec;
  final int maxPlayers;

  /// Seat-ordered.
  final List<PlayerView> players;
  final String? pileRank;
  final int pileCount;
  final int lastThrowCount;
  final int? lastThrowSeat;
  final List<String> retiredRanks;
  final TurnView? turn;
  final bool mustCheck;
  final List<Card> myHand;
  final int mySeat;
  final GameOverEvent? lastResults;
  final String? lastEventText;

  bool get isMyTurn => mySeat >= 0 && turn != null && turn!.seat == mySeat;

  PlayerView? playerAtSeat(int seat) {
    for (final p in players) {
      if (p.seat == seat) return p;
    }
    return null;
  }

  PlayerView? playerById(String userId) {
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  String nicknameAtSeat(int seat) =>
      playerAtSeat(seat)?.nickname ?? Strings.seatName(seat);

  PlayerView? get me => mySeat >= 0 ? playerAtSeat(mySeat) : null;
  bool get iAmAdmin => me?.isAdmin ?? false;

  /// The legality-mirror view of this state (features/game/logic/rules_view).
  GameViewLite toRulesView() => GameViewLite(
        deckSize: deckSize,
        players: [
          for (final p in players)
            PlayerLite(seat: p.seat, cardCount: p.cardCount, out: p.isOut),
        ],
        pile: PileLite(
          rank: pileRank,
          totalCount: pileCount,
          groups: [
            if (lastThrowSeat != null && lastThrowCount > 0)
              PileGroupLite(seat: lastThrowSeat!, count: lastThrowCount),
          ],
        ),
        lastThrowSeat: lastThrowSeat,
        mustCheck: mustCheck,
        retiredRanks: retiredRanks,
        turn: turn == null ? null : TurnLite(seat: turn!.seat, phase: turn!.phase),
        hand: [for (final c in myHand) c.rank],
      );

  ClientGameState copyWith({
    String? roomPhase,
    Object? roomCode = _sentinel,
    int? deckSize,
    int? turnTimerSec,
    int? maxPlayers,
    List<PlayerView>? players,
    Object? pileRank = _sentinel,
    int? pileCount,
    int? lastThrowCount,
    Object? lastThrowSeat = _sentinel,
    List<String>? retiredRanks,
    Object? turn = _sentinel,
    bool? mustCheck,
    List<Card>? myHand,
    int? mySeat,
    Object? lastResults = _sentinel,
    Object? lastEventText = _sentinel,
  }) =>
      ClientGameState(
        roomPhase: roomPhase ?? this.roomPhase,
        roomCode: roomCode == _sentinel ? this.roomCode : roomCode as String?,
        deckSize: deckSize ?? this.deckSize,
        turnTimerSec: turnTimerSec ?? this.turnTimerSec,
        maxPlayers: maxPlayers ?? this.maxPlayers,
        players: players ?? this.players,
        pileRank: pileRank == _sentinel ? this.pileRank : pileRank as String?,
        pileCount: pileCount ?? this.pileCount,
        lastThrowCount: lastThrowCount ?? this.lastThrowCount,
        lastThrowSeat:
            lastThrowSeat == _sentinel ? this.lastThrowSeat : lastThrowSeat as int?,
        retiredRanks: retiredRanks ?? this.retiredRanks,
        turn: turn == _sentinel ? this.turn : turn as TurnView?,
        mustCheck: mustCheck ?? this.mustCheck,
        myHand: myHand ?? this.myHand,
        mySeat: mySeat ?? this.mySeat,
        lastResults: lastResults == _sentinel
            ? this.lastResults
            : lastResults as GameOverEvent?,
        lastEventText: lastEventText == _sentinel
            ? this.lastEventText
            : lastEventText as String?,
      );

  static const _sentinel = Object();
}
