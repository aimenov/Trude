/// Client-side mirror of the engine's legality predicates
/// (packages/engine/src/legal.ts), kept honest by the golden fixtures in
/// packages/engine/fixtures/legality/fixtures.json.
///
/// Pure functions over a [GameViewLite] — the engine's GameView shape.
library;

const ranks37 = ['6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const ranks53 = [
  '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A',
];

/// Ranks present in a deck of [deckSize], ascending. The joker is never a
/// nameable rank and is not included.
List<String> ranksForDeck(int deckSize) => deckSize == 53 ? ranks53 : ranks37;

/// Ranks a leader may claim right now: deck ranks minus retired ones.
List<String> nameableRanks(int deckSize, List<String> retiredRanks) =>
    ranksForDeck(deckSize).where((r) => !retiredRanks.contains(r)).toList();

/// A throw is always 1..3 cards, capped by what's in hand.
int maxThrowCount(int handSize) => handSize < 3 ? handSize : 3;

/// Size of the most recent throw (the group a checker may flip from).
int lastThrowCount(GameViewLite view) =>
    view.pile.groups.isEmpty ? 0 : view.pile.groups.last.count;

/// The responder must check when the previous thrower emptied their hand.
bool mustCheck(GameViewLite view) => view.mustCheck;

/// Trusting (throwing onto the pile) is legal only on a respond turn when a
/// check is not forced.
bool canTrust(GameViewLite view) =>
    view.turn?.phase == 'respond' && !view.mustCheck;

/// Current turn phase: `"lead"`, `"respond"`, or null when no turn is running.
String? phaseOf(GameViewLite view) => view.turn?.phase;

// ---------------------------------------------------------------------------
// GameViewLite — the engine's GameView JSON shape, just enough for the mirror.
// ---------------------------------------------------------------------------

class GameViewLite {
  const GameViewLite({
    required this.deckSize,
    required this.players,
    required this.pile,
    required this.lastThrowSeat,
    required this.mustCheck,
    required this.retiredRanks,
    required this.turn,
    required this.hand,
  });

  factory GameViewLite.fromJson(Map<String, dynamic> json) => GameViewLite(
        deckSize: (json['deckSize'] as num).toInt(),
        players: (json['players'] as List? ?? const [])
            .map((p) => PlayerLite.fromJson((p as Map).cast<String, dynamic>()))
            .toList(),
        pile: PileLite.fromJson((json['pile'] as Map).cast<String, dynamic>()),
        lastThrowSeat: (json['lastThrowSeat'] as num?)?.toInt(),
        mustCheck: json['mustCheck'] as bool,
        retiredRanks: (json['retiredRanks'] as List? ?? const []).cast<String>(),
        turn: json['turn'] == null
            ? null
            : TurnLite.fromJson((json['turn'] as Map).cast<String, dynamic>()),
        hand: (json['hand'] as List? ?? const [])
            .map((c) => ((c as Map).cast<String, dynamic>())['rank'] as String)
            .toList(),
      );

  final int deckSize;
  final List<PlayerLite> players;
  final PileLite pile;
  final int? lastThrowSeat;
  final bool mustCheck;
  final List<String> retiredRanks;
  final TurnLite? turn;

  /// Ranks of my own cards (ids don't matter to the legality mirror).
  final List<String> hand;
}

class PlayerLite {
  const PlayerLite({
    required this.seat,
    required this.cardCount,
    required this.out,
  });

  factory PlayerLite.fromJson(Map<String, dynamic> json) => PlayerLite(
        seat: (json['seat'] as num).toInt(),
        cardCount: (json['cardCount'] as num).toInt(),
        out: json['out'] as bool,
      );

  final int seat;
  final int cardCount;
  final bool out;
}

class PileLite {
  const PileLite({required this.rank, required this.totalCount, required this.groups});

  factory PileLite.fromJson(Map<String, dynamic> json) => PileLite(
        rank: json['rank'] as String?,
        totalCount: (json['totalCount'] as num).toInt(),
        groups: (json['groups'] as List? ?? const [])
            .map((g) => PileGroupLite.fromJson((g as Map).cast<String, dynamic>()))
            .toList(),
      );

  final String? rank;
  final int totalCount;
  final List<PileGroupLite> groups;
}

class PileGroupLite {
  const PileGroupLite({required this.seat, required this.count});

  factory PileGroupLite.fromJson(Map<String, dynamic> json) => PileGroupLite(
        seat: (json['seat'] as num).toInt(),
        count: (json['count'] as num).toInt(),
      );

  final int seat;
  final int count;
}

class TurnLite {
  const TurnLite({required this.seat, required this.phase});

  factory TurnLite.fromJson(Map<String, dynamic> json) => TurnLite(
        seat: (json['seat'] as num).toInt(),
        phase: json['phase'] as String,
      );

  final int seat;
  final String phase;
}
