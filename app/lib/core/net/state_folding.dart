/// Pure fold functions turning wire messages into [ClientGameState].
///
/// Shared by the TRUE state ([GameStateNotifier] applies batches instantly,
/// for input gating) and the RENDERED state (the AnimationQueue applies the
/// same folds step by step as animations complete). Keeping one fold
/// guarantees both projections converge to identical states.
library;

import 'client_game_state.dart';
import 'protocol_models.dart';

/// Folds a full resync snapshot. [previous] supplies the fields that only
/// exist client-side (lastResults kept visible while 'finished').
ClientGameState foldStateFull(
  StateFull s, {
  required String? myUserId,
  ClientGameState previous = ClientGameState.empty,
}) {
  final players = s.players.map(PlayerView.fromWire).toList()
    ..sort((a, b) => a.seat.compareTo(b.seat));
  var mySeat = -1;
  for (final p in players) {
    if (p.userId == myUserId) mySeat = p.seat;
  }
  return ClientGameState(
    roomPhase: s.phase,
    roomCode: s.roomCode,
    deckSize: s.config.deckSize,
    turnTimerSec: s.config.turnTimerSec,
    maxPlayers: s.config.maxPlayers,
    players: players,
    pileRank: s.pile.rank,
    pileCount: s.pile.totalCount,
    lastThrowCount: s.pile.groups.isEmpty ? 0 : s.pile.groups.last.count,
    lastThrowSeat: s.lastThrowSeat,
    retiredRanks: s.retiredRanks,
    turn: s.turn == null
        ? null
        : TurnView(
            seat: s.turn!.seat,
            phase: s.turn!.phase,
            mustCheck: s.mustCheck,
            deadlineTs: s.turn!.deadlineTs,
            durationMs: s.turn!.durationMs ?? s.config.turnTimerSec * 1000,
          ),
    mustCheck: s.mustCheck,
    myHand: s.hand,
    mySeat: mySeat,
    // Keep the verdict visible while the room is still in 'finished'.
    lastResults: previous.lastResults,
  );
}

/// Applies one event of a batch. The single source of truth for how each
/// event type mutates client state.
ClientGameState applyEventTo(
  ClientGameState s,
  WireEvent event, {
  required String? myUserId,
}) {
  switch (event) {
    case GameStartedEvent():
      final bySeat = {for (final so in event.seatOrder) so.userId: so.seat};
      final players = s.players
          .map((p) => p.copyWith(
                seat: bySeat[p.userId] ?? p.seat,
                cardCount: 0,
                isOut: false,
              ))
          .toList()
        ..sort((a, b) => a.seat.compareTo(b.seat));
      final counted = players
          .map((p) => p.seat < event.handCounts.length
              ? p.copyWith(cardCount: event.handCounts[p.seat])
              : p)
          .toList();
      var mySeat = s.mySeat;
      if (myUserId != null && bySeat.containsKey(myUserId)) {
        mySeat = bySeat[myUserId]!;
      }
      return s.copyWith(
        roomPhase: 'playing',
        deckSize: event.deckSize,
        players: counted,
        mySeat: mySeat,
        pileRank: null,
        pileCount: 0,
        lastThrowCount: 0,
        lastThrowSeat: null,
        retiredRanks: const [],
        turn: null,
        mustCheck: false,
        lastResults: null,
      );

    case TurnStartedEvent():
      return s.copyWith(
        turn: TurnView(
          seat: event.seat,
          phase: event.phase,
          mustCheck: event.mustCheck,
          deadlineTs: event.deadlineTs,
          durationMs: event.durationMs ?? s.turnTimerSec * 1000,
        ),
        mustCheck: event.mustCheck,
      );

    case CardsThrownEvent():
      return s.copyWith(
        players: updateSeat(s.players, event.seat,
            (p) => p.copyWith(cardCount: p.cardCount - event.count)),
        pileRank: event.rank,
        pileCount: event.isLead ? event.count : s.pileCount + event.count,
        lastThrowCount: event.count,
        lastThrowSeat: event.seat,
      );

    case CheckResultEvent():
      return s.copyWith(
        players: updateSeat(s.players, event.pickerSeat,
            (p) => p.copyWith(cardCount: p.cardCount + event.pickedCount)),
        pileRank: null,
        pileCount: 0,
        lastThrowCount: 0,
        lastThrowSeat: null,
      );

    case FourDiscardedEvent():
      return s.copyWith(
        players: updateSeat(s.players, event.seat,
            (p) => p.copyWith(cardCount: p.cardCount - event.cards.length)),
        retiredRanks: [...s.retiredRanks, event.rank],
      );

    case PlayerOutEvent():
      return s.copyWith(
        players:
            updateSeat(s.players, event.seat, (p) => p.copyWith(isOut: true)),
      );

    case GameOverEvent():
      return s.copyWith(
        roomPhase: 'finished',
        turn: null,
        mustCheck: false,
        lastResults: event,
      );

    case GenericEvent():
      return _applyGenericEvent(s, event);
  }
}

ClientGameState _applyGenericEvent(ClientGameState s, GenericEvent event) {
  final raw = event.raw;
  switch (event.type) {
    case 'playerJoined':
      final userId = raw['userId'] as String;
      if (s.playerById(userId) != null) return s;
      final joined = PlayerView(
        userId: userId,
        nickname: (raw['nickname'] as String?) ?? '?',
        avatar: (raw['avatar'] as String?) ?? '',
        seat: (raw['seat'] as num?)?.toInt() ?? s.players.length,
        cardCount: 0,
        connected: true,
        autoPilot: false,
        isOut: false,
        isAdmin: false,
      );
      final players = [...s.players, joined]
        ..sort((a, b) => a.seat.compareTo(b.seat));
      return s.copyWith(players: players);

    case 'playerLeft':
      final userId = raw['userId'] as String;
      final gone = s.playerById(userId);
      if (gone == null) return s;
      return s.copyWith(
        players: s.players.where((p) => p.userId != userId).toList(),
      );

    case 'roomConfigured':
      return s.copyWith(
        deckSize: (raw['deckSize'] as num?)?.toInt() ?? s.deckSize,
        turnTimerSec: (raw['turnTimerSec'] as num?)?.toInt() ?? s.turnTimerSec,
        maxPlayers: (raw['maxPlayers'] as num?)?.toInt() ?? s.maxPlayers,
      );

    case 'seatSwapResolved':
      // The server follows up with a stateFull resync; only swap eagerly.
      if (raw['accepted'] != true) return s;
      final seatA = (raw['seatA'] as num).toInt();
      final seatB = (raw['seatB'] as num).toInt();
      final players = s.players.map((p) {
        if (p.seat == seatA) return p.copyWith(seat: seatB);
        if (p.seat == seatB) return p.copyWith(seat: seatA);
        return p;
      }).toList()
        ..sort((a, b) => a.seat.compareTo(b.seat));
      var mySeat = s.mySeat;
      if (mySeat == seatA) {
        mySeat = seatB;
      } else if (mySeat == seatB) {
        mySeat = seatA;
      }
      return s.copyWith(players: players, mySeat: mySeat);

    case 'autoPilot':
      final seat = (raw['seat'] as num).toInt();
      final on = raw['on'] == true;
      return s.copyWith(
          players: updateSeat(s.players, seat, (p) => p.copyWith(autoPilot: on)));

    case 'playerConnection':
      final seat = (raw['seat'] as num).toInt();
      final connected = raw['connected'] == true;
      return s.copyWith(
          players: updateSeat(
              s.players, seat, (p) => p.copyWith(connected: connected)));

    default:
      return s;
  }
}

List<PlayerView> updateSeat(
  List<PlayerView> players,
  int seat,
  PlayerView Function(PlayerView) update,
) =>
    [for (final p in players) p.seat == seat ? update(p) : p];
