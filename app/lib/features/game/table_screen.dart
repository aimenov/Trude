import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/sfx_service.dart';
import '../../core/haptics/haptics_service.dart';
import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';
import 'anim/motion_spec.dart';
import 'anim/rendered_state.dart';
import 'anim/table_anchors.dart';
import 'anim/table_fx_layer.dart';
import 'logic/rules_view.dart' as rules;
import 'widgets/card_widgets.dart';
import 'widgets/countdown_ring.dart';
import 'widgets/my_hand.dart';
import 'widgets/pile_stack.dart';
import 'widgets/seat_avatar.dart';

class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  final _subs = <StreamSubscription<dynamic>>[];
  final _anchors = TableAnchors();

  /// Local action-bar mode for my respond turn.
  bool _checking = false;
  bool _trusting = false;
  final Set<String> _selectedCardIds = {};
  String? _chosenRank;
  bool _urgentSignaled = false;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
        const Duration(milliseconds: 250), (_) => setState(() {}));
    final room = ref.read(currentRoomProvider);
    if (room == null) return;
    _subs.add(room.onError.listen((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.serverError(e.code, e.message))));
    }));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _anchors.dispose();
    super.dispose();
  }

  void _resetTurnUi() {
    _checking = false;
    _trusting = false;
    _selectedCardIds.clear();
    _chosenRank = null;
    _urgentSignaled = false;
  }

  void _throw(ClientGameState state, {required bool leading}) {
    final room = ref.read(currentRoomProvider);
    if (room == null || _selectedCardIds.isEmpty) return;
    room.throwCards(_selectedCardIds.toList(),
        rank: leading ? _chosenRank : null);
    ref.read(hapticsProvider).medium();
    setState(_resetTurnUi);
  }

  void _flip(int index) {
    ref.read(currentRoomProvider)?.check(index);
    ref.read(hapticsProvider).medium();
    setState(_resetTurnUi);
  }

  void _onTapAnywhere() {
    // Tap anywhere while a batch is animating -> skip to the end.
    if (ref.read(animationBusyProvider)) {
      ref.read(renderedGameStateProvider.notifier).skipAnimations();
    }
  }

  Duration _remaining(TurnView? turn) {
    if (turn == null) return Duration.zero;
    final left = turn.deadlineTs - DateTime.now().millisecondsSinceEpoch;
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  @override
  Widget build(BuildContext context) {
    // Navigation waits for the game-over set piece: the RENDERED phase flips
    // to 'finished' only when that queue step completes (or is tapped through).
    ref.listen(renderedGameStateProvider.select((s) => s.roomPhase),
        (prev, next) {
      if (next == 'finished') context.go('/results');
    });
    ref.listen(currentRoomProvider, (prev, next) {
      if (next == null && mounted) context.go('/home');
    });
    // A new turn (TRUE state) invalidates any in-progress local action UI.
    ref.listen(gameStateProvider.select((s) => s.turn?.deadlineTs), (p, n) {
      if (p != n) setState(_resetTurnUi);
    });
    // My-turn chime plays off the TRUE state (instant feedback).
    ref.listen(gameStateProvider.select((s) => s.isMyTurn), (p, n) {
      if (n == true && p != true) {
        ref.read(sfxProvider).yourTurn();
        ref.read(hapticsProvider).light();
      }
    });

    final trueState = ref.watch(gameStateProvider);
    final rendered = ref.watch(renderedGameStateProvider);
    final busy = ref.watch(animationBusyProvider);
    final speed = ref.watch(animationSpeedProvider);
    final view = trueState.toRulesView();

    _signalUrgency(trueState);

    return Scaffold(
      appBar: AppBar(
        title: Text(rendered.pileRank != null
            ? Strings.playingRank(rendered.pileRank!)
            : Strings.freshPile),
        actions: [
          if (rendered.roomCode != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(rendered.roomCode!)),
            ),
        ],
      ),
      body: SafeArea(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onTapAnywhere(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  _opponentsRow(rendered, speed),
                  const Divider(height: 1),
                  Expanded(child: _centerArea(rendered, speed)),
                  _eventStrip(rendered),
                  const Divider(height: 1),
                  _handArea(trueState, rendered, speed, busy),
                  AbsorbPointer(
                    absorbing: busy, // short input lock during set pieces
                    child: _actionArea(trueState, view),
                  ),
                  _reactionBar(),
                ],
              ),
              Positioned.fill(child: TableFxLayer(anchors: _anchors)),
            ],
          ),
        ),
      ),
    );
  }

  /// One-shot urgency beat when MY countdown crosses the amber/red window.
  void _signalUrgency(ClientGameState trueState) {
    final urgent = trueState.isMyTurn &&
        _remaining(trueState.turn) > Duration.zero &&
        _remaining(trueState.turn) <= MotionSpec.urgentThreshold;
    if (urgent && !_urgentSignaled) {
      _urgentSignaled = true;
      ref.read(sfxProvider).timerUrgent();
      ref.read(hapticsProvider).warning();
    }
  }

  // -- Opponents ----------------------------------------------------------------

  Widget _opponentsRow(ClientGameState state, AnimationSpeed speed) {
    final n = state.players.length;
    final opponents = state.players
        .where((p) => p.seat != state.mySeat)
        .toList()
      ..sort((a, b) {
        int order(int seat) =>
            state.mySeat < 0 ? seat : (seat - state.mySeat + n) % n;
        return order(a.seat).compareTo(order(b.seat));
      });
    final turnTotal = Duration(seconds: state.turnTimerSec);
    return SizedBox(
      height: 130,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final p in opponents)
            KeyedSubtree(
              key: _anchors.seatKey(p.seat),
              child: SeatAvatar(
                player: p,
                isTurn: state.turn?.seat == p.seat,
                remaining: state.turn?.seat == p.seat
                    ? _remaining(state.turn)
                    : Duration.zero,
                turnTotal: turnTotal,
                speed: speed,
                anchors: _anchors,
              ),
            ),
        ],
      ),
    );
  }

  // -- Center ---------------------------------------------------------------

  Widget _centerArea(ClientGameState state, AnimationSpeed speed) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _retiredRail(state),
        ),
        Expanded(
          child: Center(
            // Scale the pile cluster down rather than overflow when the
            // vertical budget is tight (small phones / short windows).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PileStack(
                    key: _anchors.pileKey,
                    count: state.pileCount,
                    rank: state.pileRank,
                    speed: speed,
                  ),
                  const SizedBox(height: 4),
                  Text(Strings.pileCount(state.pileCount),
                      style: textTheme.titleMedium),
                  if (state.lastThrowCount > 0 && state.pileRank != null)
                    Text(
                      '${Strings.lastThrowLabel(state.lastThrowCount)} × '
                      '${Strings.rankWord(state.pileRank!)}',
                      style: textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _turnLine(state),
        ),
      ],
    );
  }

  Widget _retiredRail(ClientGameState state) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: _anchors.retiredKey,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(state.retiredRanks.isEmpty
            ? Strings.noRetiredRanks
            : Strings.retiredRanksLabel('')),
        for (final rank in state.retiredRanks)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE082), // retired = golden
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB300)),
            ),
            child: Text(
              rank,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: scheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }

  Widget _turnLine(ClientGameState state) {
    final turn = state.turn;
    if (turn == null) return const SizedBox.shrink();
    final remaining = _remaining(turn);
    final secondsLeft = (remaining.inMilliseconds / 1000).ceil().clamp(0, 999);
    final who = turn.seat == state.mySeat
        ? (turn.phase == 'lead'
            ? Strings.yourTurnLead
            : Strings.yourTurnRespond)
        : state.nicknameAtSeat(turn.seat);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CountdownRing(
          remaining: remaining,
          total: Duration(seconds: state.turnTimerSec),
        ),
        const SizedBox(width: 8),
        Text('$who · ${Strings.countdown(secondsLeft)}',
            style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  // -- Event strip -------------------------------------------------------------

  Widget _eventStrip(ClientGameState state) {
    final text = state.lastEventText;
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, textAlign: TextAlign.center),
    );
  }

  // -- My hand -----------------------------------------------------------------

  Widget _handArea(ClientGameState trueState, ClientGameState rendered,
      AnimationSpeed speed, bool busy) {
    if (rendered.myHand.isEmpty && trueState.myHand.isEmpty) {
      return SizedBox(key: _anchors.handKey, height: 8);
    }
    final turn = trueState.turn;
    final selecting = !busy &&
        trueState.isMyTurn &&
        turn != null &&
        (turn.phase == 'lead' || _trusting);
    final maxCount = rules.maxThrowCount(trueState.myHand.length);
    final urgent = trueState.isMyTurn &&
        _remaining(turn) > Duration.zero &&
        _remaining(turn) <= MotionSpec.urgentThreshold;

    return KeyedSubtree(
      key: _anchors.handKey,
      child: MyHandView(
        cards: rendered.myHand,
        selectedIds: _selectedCardIds,
        selectable: selecting,
        shiver: urgent,
        speed: speed,
        onToggle: (card, selected) {
          setState(() {
            if (selected) {
              if (_selectedCardIds.length < maxCount) {
                _selectedCardIds.add(card.id);
                ref.read(hapticsProvider).selection();
              }
            } else {
              _selectedCardIds.remove(card.id);
            }
          });
        },
      ),
    );
  }

  // -- Bottom action area --------------------------------------------------------

  Widget _actionArea(ClientGameState state, rules.GameViewLite view) {
    final turn = state.turn;
    final myTurn = state.isMyTurn && turn != null;

    Widget content;
    if (!myTurn) {
      content = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(Strings.waitingForOpponent, textAlign: TextAlign.center),
      );
    } else if (turn.phase == 'lead') {
      content = _throwUi(state, view, leading: true);
    } else if (_checking) {
      content = _checkUi(view);
    } else if (_trusting) {
      content = _throwUi(state, view, leading: false);
    } else {
      content = _respondButtons(view);
    }

    // The action bar springs up (slide + fade with overshoot) when it
    // becomes my turn; rebuilding the tween via the key restarts it.
    final speed = ref.watch(animationSpeedProvider);
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        key: ValueKey('action-bar-$myTurn'),
        tween: Tween(begin: myTurn ? 0.0 : 1.0, end: 1.0),
        duration: speed.scale(MotionSpec.actionBarSlideIn),
        curve: MotionSpec.actionBarCurve,
        builder: (context, t, child) => FractionalTranslation(
          translation: Offset(0, (1 - t) * 0.6),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }

  Widget _respondButtons(rules.GameViewLite view) {
    final trustAllowed = rules.canTrust(view);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: trustAllowed
                      ? () => setState(() => _trusting = true)
                      : null,
                  child: Text(Strings.trust),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() => _checking = true),
                  child: Text(Strings.check),
                ),
              ),
            ],
          ),
          if (rules.mustCheck(view))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  Text(Strings.mustCheckReason, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  Widget _checkUi(rules.GameViewLite view) {
    final count = rules.lastThrowCount(view);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Strings.tapCardToFlip),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InkWell(
                    onTap: () => _flip(i),
                    borderRadius: BorderRadius.circular(6),
                    child: const TrudeCardBack(width: 48),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _throwUi(ClientGameState state, rules.GameViewLite view,
      {required bool leading}) {
    final maxCount = rules.maxThrowCount(state.myHand.length);
    final nameable = rules.nameableRanks(state.deckSize, state.retiredRanks);
    final canThrow = _selectedCardIds.isNotEmpty &&
        _selectedCardIds.length <= maxCount &&
        (!leading || _chosenRank != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Strings.selectCardsHint,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(
            children: [
              if (leading) ...[
                Text(Strings.claimRankLabel),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _chosenRank,
                  hint: Text(Strings.claimRankLabel),
                  items: [
                    for (final rank in nameable)
                      DropdownMenuItem(
                          value: rank, child: Text(Strings.rankWord(rank))),
                  ],
                  onChanged: (rank) => setState(() => _chosenRank = rank),
                ),
                const Spacer(),
              ] else
                const Spacer(),
              FilledButton(
                onPressed:
                    canThrow ? () => _throw(state, leading: leading) : null,
                child: Text(
                    '${Strings.throwButton} (${_selectedCardIds.length})'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- Reaction bar -------------------------------------------------------------

  Widget _reactionBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final entry in Strings.reactionEmoji.entries)
            IconButton(
              onPressed: () =>
                  ref.read(currentRoomProvider)?.reaction(entry.key),
              icon: Text(entry.value, style: const TextStyle(fontSize: 20)),
            ),
        ],
      ),
    );
  }
}
