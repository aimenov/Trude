import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/sfx_service.dart';
import '../../core/haptics/haptics_service.dart';
import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import 'anim/motion_spec.dart';
import 'anim/rendered_state.dart';
import 'anim/table_anchors.dart';
import 'anim/table_fx_layer.dart';
import 'logic/rules_view.dart' as rules;
import 'widgets/card_widgets.dart';
import 'widgets/countdown_ring.dart';
import 'widgets/my_hand.dart';
import 'widgets/pile_stack.dart';
import 'widgets/rank_strip.dart';
import 'widgets/seat_avatar.dart';

class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  /// Server error codes that mean "your throw was rejected" — the optimistic
  /// hold is rolled back and the selection kept for retry. Anything else
  /// (e.g. RATE_LIMITED on a reaction) must not touch a pending throw.
  static const _throwRejectionCodes = {
    'NOT_YOUR_TURN',
    'BAD_CARDS',
    'RANK_REQUIRED',
    'RANK_MISMATCH',
    'RANK_DEAD',
    'RANK_JOKER',
    'MUST_CHECK',
    'BAD_PHASE',
    'STALE_ACTION',
  };

  /// How close to the deadline the staged selection is auto-submitted.
  static const _autoSubmitWindow = Duration(milliseconds: 400);

  final _subs = <StreamSubscription<dynamic>>[];
  final _anchors = TableAnchors();

  /// Local action-bar mode for my respond turn.
  bool _checking = false;
  bool _trusting = false;
  final Set<String> _selectedCardIds = {};
  String? _chosenRank;

  /// The player tapped a rank chip this turn — smart defaults back off.
  bool _rankChosenManually = false;
  bool _urgentSignaled = false;

  /// The optimistic throw in flight: sent to the server, cards held out of
  /// the rendered hand, awaiting confirmation (turn change) or rejection.
  ({int clientSeq, List<String> cardIds, String? rank})? _pendingThrow;

  /// The deadline the ticker already auto-submitted for (at most once each).
  int? _autoSubmittedDeadline;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _maybeAutoSubmit();
      setState(() {});
    });
    final room = ref.read(currentRoomProvider);
    if (room == null) return;
    _subs.add(room.onError.listen((e) {
      if (!mounted) return;
      final pending = _pendingThrow;
      if (pending != null && _throwRejectionCodes.contains(e.code)) {
        // Rollback: the held cards spring back into the rendered hand, but
        // the selection/rank/TRUST mode stay so the player can just retry.
        ref
            .read(renderedGameStateProvider.notifier)
            .releaseHold(pending.clientSeq);
        setState(() => _pendingThrow = null);
      }
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
    _rankChosenManually = false;
    _urgentSignaled = false;
    _pendingThrow = null;
  }

  /// Optimistic throw: send, hold the cards out of the rendered hand, and
  /// remember the pending action. NO local reset here — a confirmed throw is
  /// followed by a turn change (the deadlineTs listener does the full reset),
  /// a rejected one rolls back in the onError listener keeping the selection.
  void _throw(ClientGameState state, {required bool leading}) {
    final room = ref.read(currentRoomProvider);
    if (room == null || _selectedCardIds.isEmpty || _pendingThrow != null) {
      return;
    }
    final cardIds = _selectedCardIds.toList();
    final rank = leading ? _chosenRank : null;
    final clientSeq = room.throwCards(cardIds, rank: rank);
    ref.read(renderedGameStateProvider.notifier).holdCards(clientSeq, cardIds);
    ref.read(hapticsProvider).medium();
    setState(() {
      _pendingThrow = (clientSeq: clientSeq, cardIds: cardIds, rank: rank);
    });
  }

  /// Timeout uses the player's picks: just before the deadline, a legal
  /// standing selection is submitted through the same optimistic [_throw]
  /// (at most once per deadline). If it races the server's timeout the stale
  /// action is rejected server-side before any side effects — harmless.
  void _maybeAutoSubmit() {
    final s = ref.read(gameStateProvider);
    final turn = s.turn;
    if (turn == null || !s.isMyTurn || s.mustCheck || _pendingThrow != null) {
      return;
    }
    if (_autoSubmittedDeadline == turn.deadlineTs) return;
    final remaining = _remaining(turn);
    if (remaining <= Duration.zero || remaining > _autoSubmitWindow) return;
    final leading = turn.phase == 'lead';
    if (!leading && !_trusting) return;
    final legal = _selectedCardIds.isNotEmpty &&
        _selectedCardIds.length <= rules.maxThrowCount(s.myHand.length) &&
        (!leading || _chosenRank != null);
    if (!legal) return;
    _autoSubmittedDeadline = turn.deadlineTs;
    _throw(s, leading: leading);
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

  // -- Shared parlor text styles -----------------------------------------------

  /// Small brass-etched section label.
  TextStyle get _etchedLabel => TrudeType.etched
      .copyWith(fontSize: 10.5, letterSpacing: 2.2, height: 1.2);

  /// Small italic serif — hints and disabled-reason lines. The bundled italic
  /// weight is 700, so hints stay on it.
  TextStyle get _hintSerif => TrudeType.cardIndex.copyWith(
        fontStyle: FontStyle.italic,
        fontSize: 12.5,
        height: 1.35,
        color: TrudeColors.textMuted,
      );

  /// Engraved lettering pressed into a brass plaque.
  TextStyle _engraved(double fontSize) => TrudeType.stamp.copyWith(
        color: TrudeColors.textOnBrass,
        fontSize: fontSize,
        letterSpacing: 1.6,
        shadows: [
          Shadow(
            color: TrudeColors.brassBright.withValues(alpha: 0.55),
            offset: const Offset(0, 0.8),
          ),
        ],
      );

  /// An engraved brass plaque surface.
  BoxDecoration _brassPlaque({double radius = TrudeDims.chipRadius}) =>
      BoxDecoration(
        gradient: TrudeGradients.brass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: TrudeColors.brassDark),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// A hairline that fades out toward both ends — reads as a felt seam.
  Widget _hairlineSeam() => Container(
        height: TrudeDims.hairlineWidth,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, TrudeColors.hairline, Colors.transparent],
          ),
        ),
      );

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
              child: Center(
                child: Text(
                  rendered.roomCode!,
                  style: TrudeType.etched
                      .copyWith(fontSize: 12, letterSpacing: 2.4),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The parlor: candle-lit felt, rail, and monogram behind everything.
          Positioned.fill(child: TableFeltBackground(speed: speed)),
          SafeArea(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _onTapAnywhere(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      _opponentsRow(rendered, speed),
                      _hairlineSeam(),
                      Expanded(child: _centerArea(rendered, speed)),
                      _eventStrip(rendered),
                      _hairlineSeam(),
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
        ],
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
    // Ring total = the armed decision window (server-provided): the arc is
    // pinned full during animation grace and drains over the real window.
    final turnTotal = state.turn == null
        ? Duration(seconds: state.turnTimerSec)
        : Duration(milliseconds: state.turn!.durationMs);
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
                  const SizedBox(height: 6),
                  Text(Strings.pileCount(state.pileCount),
                      style: _etchedLabel),
                  if (state.lastThrowCount > 0 && state.pileRank != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _claimPlaque(state),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _turnLine(state, speed),
        ),
      ],
    );
  }

  /// The standing claim, engraved into a brass plaque under the pile.
  Widget _claimPlaque(ClientGameState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: _brassPlaque(),
      child: Text(
        '${Strings.lastThrowLabel(state.lastThrowCount)} × '
        '${Strings.rankWord(state.pileRank!)}',
        style: _engraved(12),
      ),
    );
  }

  Widget _retiredRail(ClientGameState state) {
    return Row(
      key: _anchors.retiredKey,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          state.retiredRanks.isEmpty
              ? Strings.noRetiredRanks
              : Strings.retiredRanksLabel(''),
          style: _etchedLabel,
        ),
        for (final rank in state.retiredRanks)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: _brassPlaque(radius: 7),
            child: Text(rank, style: _engraved(11)),
          ),
      ],
    );
  }

  Widget _turnLine(ClientGameState state, AnimationSpeed speed) {
    final turn = state.turn;
    if (turn == null) return const SizedBox.shrink();
    final remaining = _remaining(turn);
    final who = turn.seat == state.mySeat
        ? (turn.phase == 'lead'
            ? Strings.yourTurnLead
            : Strings.yourTurnRespond)
        : state.nicknameAtSeat(turn.seat);
    // Graphic-only countdown: the ring is the countdown (no numeric text).
    // Its total is the armed decision window, so it starts full and is
    // pinned full through the animation grace.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CountdownRing(
          remaining: remaining,
          total: Duration(milliseconds: turn.durationMs),
          // Urgent-window pulse honors the in-app animation-speed setting.
          animate: !speed.isOff,
        ),
        const SizedBox(width: 8),
        Text(
          who,
          style: TrudeType.cardIndex.copyWith(
            fontSize: 15,
            height: 1.2,
            color: TrudeColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // -- Event strip -------------------------------------------------------------

  Widget _eventStrip(ClientGameState state) {
    final text = state.lastEventText;
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: TrudeColors.surfaceSunken.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, textAlign: TextAlign.center, style: _hintSerif),
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
        _pendingThrow == null &&
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
            _applySmartRankDefault(trueState);
          });
        },
        // Flick-to-throw: same action as the THROW button. Guards legality
        // itself against fresh state (selection count, chosen rank on lead).
        onFlickThrow: !selecting
            ? null
            : () {
                final s = ref.read(gameStateProvider);
                final t = s.turn;
                if (!s.isMyTurn || t == null || _pendingThrow != null) return;
                final leading = t.phase == 'lead';
                if (!leading && !_trusting) return;
                final canThrow = _selectedCardIds.isNotEmpty &&
                    _selectedCardIds.length <=
                        rules.maxThrowCount(s.myHand.length) &&
                    (!leading || _chosenRank != null);
                if (canThrow) _throw(s, leading: leading);
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
        child: Text(
          Strings.waitingForOpponent,
          textAlign: TextAlign.center,
          style: _hintSerif,
        ),
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
                child: _ParlorButton(
                  label: Strings.trust,
                  onPressed: trustAllowed
                      ? () => setState(() => _trusting = true)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ParlorButton(
                  label: Strings.check,
                  primary: true,
                  onPressed: () => setState(() => _checking = true),
                ),
              ),
            ],
          ),
          if (rules.mustCheck(view))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                Strings.mustCheckReason,
                textAlign: TextAlign.center,
                style: _hintSerif,
              ),
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
          Text(Strings.tapCardToFlip, style: _hintSerif),
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

  /// «ТРИ СЕМЁРКИ» / "THREE SEVENS" — the claim-callout string without the
  /// trailing stamp "!", for the THROW button label.
  String _claimLabel(int count, String rank) {
    final claim = Strings.claimCallout(count, rank);
    return claim.endsWith('!') ? claim.substring(0, claim.length - 1) : claim;
  }

  /// Smart claim default: while the player has not tapped a rank chip this
  /// turn, the chosen rank tracks the majority rank of the selected cards
  /// (truthful throws are select → THROW, zero extra taps). Jokers and
  /// retired ranks never become a default.
  void _applySmartRankDefault(ClientGameState trueState) {
    if (_rankChosenManually) return;
    final nameable =
        rules.nameableRanks(trueState.deckSize, trueState.retiredRanks);
    final counts = <String, int>{};
    for (final card in trueState.myHand) {
      if (_selectedCardIds.contains(card.id) && nameable.contains(card.rank)) {
        counts[card.rank] = (counts[card.rank] ?? 0) + 1;
      }
    }
    String? majority;
    var best = 0;
    for (final entry in counts.entries) {
      if (entry.value > best) {
        best = entry.value;
        majority = entry.key;
      }
    }
    _chosenRank = majority;
  }

  Widget _throwUi(ClientGameState state, rules.GameViewLite view,
      {required bool leading}) {
    final maxCount = rules.maxThrowCount(state.myHand.length);
    final nameable = rules.nameableRanks(state.deckSize, state.retiredRanks);
    final canThrow = _pendingThrow == null &&
        _selectedCardIds.isNotEmpty &&
        _selectedCardIds.length <= maxCount &&
        (!leading || _chosenRank != null);
    // The THROW button speaks the claim itself once rank+count are staged
    // (the callout string, sans its stamp "!").
    final label = leading && _chosenRank != null && _selectedCardIds.isNotEmpty
        ? _claimLabel(_selectedCardIds.length, _chosenRank!)
        : '${Strings.throwButton} (${_selectedCardIds.length})';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Strings.selectCardsHint,
              textAlign: TextAlign.center, style: _hintSerif),
          const SizedBox(height: 6),
          if (leading) ...[
            RankStrip(
              ranks: nameable,
              chosen: _chosenRank,
              onChosen: (rank) => setState(() {
                _chosenRank = rank;
                _rankChosenManually = true;
              }),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Spacer(),
              _ParlorButton(
                label: label,
                primary: true,
                onPressed:
                    canThrow ? () => _throw(state, leading: leading) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- Reaction bar -------------------------------------------------------------

  Widget _reactionBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: TrudeColors.surfaceSunken.withValues(alpha: 0.4),
        border: const Border(top: BorderSide(color: TrudeColors.hairline)),
      ),
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

/// A substantial parlor button: brass fill for the primary action, a brass
/// outline for the secondary, both with a pressed-in state (the button sinks
/// 1.5dp and its shadow tightens).
class _ParlorButton extends StatefulWidget {
  const _ParlorButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<_ParlorButton> createState() => _ParlorButtonState();
}

class _ParlorButtonState extends State<_ParlorButton> {
  bool _down = false;

  static const _pressedBrass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [TrudeColors.brass, TrudeColors.brassDark, TrudeColors.brass],
    stops: [0.0, 0.6, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = _down && enabled;

    final BoxDecoration decoration;
    final Color labelColor;
    if (!enabled) {
      decoration = BoxDecoration(
        color: TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(color: TrudeColors.hairline),
      );
      labelColor = TrudeColors.textMuted;
    } else if (widget.primary) {
      decoration = BoxDecoration(
        gradient: pressed ? _pressedBrass : TrudeGradients.brass,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(color: TrudeColors.brassDark),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.55),
            blurRadius: pressed ? 2 : 6,
            offset: Offset(0, pressed ? 1 : 3),
          ),
        ],
      );
      labelColor = TrudeColors.textOnBrass;
    } else {
      decoration = BoxDecoration(
        color: pressed
            ? TrudeColors.surfaceSunken
            : TrudeColors.surfacePanel.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(color: TrudeColors.brassDark, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.4),
            blurRadius: pressed ? 1 : 4,
            offset: Offset(0, pressed ? 0.5 : 2),
          ),
        ],
      );
      labelColor = TrudeColors.brassBright;
    }

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: Transform.translate(
        offset: Offset(0, pressed ? 1.5 : 0),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: decoration,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrudeType.etched.copyWith(
              fontSize: 15,
              letterSpacing: 2,
              height: 1.1,
              color: labelColor,
            ),
          ),
        ),
      ),
    );
  }
}
