import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart' hide Card;
import '../../core/net/moderation_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../game/widgets/card_widgets.dart';
import '../home/parlor_widgets.dart';
import '../moderation/player_actions_sheet.dart';

const _deckCap = {37: 6, 53: 8};

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _subs = <StreamSubscription<dynamic>>[];
  SeatSwapRequest? _incomingSwap;

  @override
  void initState() {
    super.initState();
    final room = ref.read(currentRoomProvider);
    if (room == null) return;
    _subs.add(room.onError.listen((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.serverError(e.code, e.message))));
    }));
    _subs.add(room.onSeatSwapRequested.listen((req) {
      if (mounted) setState(() => _incomingSwap = req);
    }));
    _subs.add(room.onEvents.listen((batch) {
      for (final e in batch.events) {
        if (e is GenericEvent && e.type == 'seatSwapResolved') {
          if (!mounted) return;
          setState(() => _incomingSwap = null);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.raw['accepted'] == true
                  ? Strings.swapAccepted
                  : Strings.swapDeclined)));
        }
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    await ref.read(currentRoomProvider.notifier).leaveRoom();
    if (mounted) context.go('/home');
  }

  /// Tap on a lobby seat → the player actions sheet, with the seat-swap flow
  /// moved into it and an admin-only kick row (the server enforces both
  /// lobby-only and admin-only on kickPlayer).
  Future<void> _tapPlayer(PlayerView player, ClientGameState state) async {
    if (player.userId == state.me?.userId) return;
    await showPlayerActionsSheet(
      context,
      ref,
      userId: player.userId,
      nickname: player.nickname,
      extras: PlayerActionsExtras(
        onRequestSwap: () =>
            ref.read(currentRoomProvider)?.requestSeatSwap(player.userId),
        onKick: state.iAmAdmin
            ? () => ref.read(currentRoomProvider)?.kickPlayer(player.userId)
            : null,
      ),
    );
  }

  void _respondSwap(bool accept) {
    ref.read(currentRoomProvider)?.respondSeatSwap(accept: accept);
    setState(() => _incomingSwap = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameStateProvider.select((s) => s.roomPhase), (prev, next) {
      if (next == 'playing') context.go('/table');
    });
    ref.listen(currentRoomProvider, (prev, next) {
      if (next == null && mounted) context.go('/home');
    });

    final state = ref.watch(gameStateProvider);
    final room = ref.watch(currentRoomProvider);
    final blocked = ref.watch(blockedIdsProvider);
    final isAdmin = state.iAmAdmin;
    final swap = _incomingSwap;
    final swapFrom =
        swap == null ? null : state.playerAtSeat(swap.fromSeat);

    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.lobbyTitle),
          leading: BackButton(onPressed: _leave),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (state.roomCode != null) ...[
                  Center(child: _RoomCodePlate(code: state.roomCode!)),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      Strings.shareCodeHint,
                      textAlign: TextAlign.center,
                      style: TrudeType.cardIndex.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        fontSize: 12.5,
                        color: TrudeColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                if (swap != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ParlorPanel(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Strings.swapIncoming(swapFrom == null
                                ? Strings.seatName(swap.fromSeat)
                                : maskedNickname(blocked, swapFrom.userId,
                                    swapFrom.nickname)),
                            style: const TextStyle(
                                color: TrudeColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                  onPressed: () => _respondSwap(false),
                                  child: Text(Strings.decline)),
                              const SizedBox(width: 4),
                              FilledButton(
                                  onPressed: () => _respondSwap(true),
                                  child: Text(Strings.accept)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                _TablePreview(
                  state: state,
                  blocked: blocked,
                  onTapPlayer: (p) => _tapPlayer(p, state),
                ),
                const SizedBox(height: 10),
                if (isAdmin) ...[
                  ParlorPanel(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _configRow(
                          context,
                          Strings.deckSizeLabel,
                          SegmentedButton<int>(
                            segments: [
                              ButtonSegment(
                                  value: 37,
                                  label: Text(Strings.deckOption(37))),
                              ButtonSegment(
                                  value: 53,
                                  label: Text(Strings.deckOption(53))),
                            ],
                            selected: {state.deckSize},
                            onSelectionChanged: (v) => room?.configureRoom(
                                deckSize: v.single,
                                maxPlayers: state.maxPlayers
                                    .clamp(2, _deckCap[v.single] ?? 6)),
                          ),
                        ),
                        const EtchedDivider(
                            padding: EdgeInsets.symmetric(vertical: 4)),
                        _configRow(
                          context,
                          Strings.turnTimerLabel,
                          SegmentedButton<int>(
                            segments: [
                              for (final s in const [15, 30, 60])
                                ButtonSegment(
                                    value: s,
                                    label: Text(Strings.secondsOption(s))),
                            ],
                            selected: {state.turnTimerSec},
                            onSelectionChanged: (v) =>
                                room?.configureRoom(turnTimerSec: v.single),
                          ),
                        ),
                        const EtchedDivider(
                            padding: EdgeInsets.symmetric(vertical: 4)),
                        _configRow(
                          context,
                          Strings.maxPlayersLabel,
                          DropdownButton<int>(
                            value: state.maxPlayers
                                .clamp(2, _deckCap[state.deckSize] ?? 6),
                            dropdownColor: TrudeColors.surfaceRaised,
                            items: [
                              for (var n = 2;
                                  n <= (_deckCap[state.deckSize] ?? 6);
                                  n++)
                                DropdownMenuItem(
                                    value: n, child: Text('$n')),
                            ],
                            onChanged: (n) => n == null
                                ? null
                                : room?.configureRoom(maxPlayers: n),
                          ),
                        ),
                        const SizedBox(height: 14),
                        BrassButton(
                          onPressed: state.players.length >= 2
                              ? () => room?.startGame()
                              : null,
                          child: Text(Strings.start),
                        ),
                        if (state.players.length < 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              Strings.needTwoPlayers,
                              textAlign: TextAlign.center,
                              style: TrudeType.cardIndex.copyWith(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w400,
                                fontSize: 13.5,
                                color: TrudeColors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else
                  ParlorPanel(
                    child: Text(
                      Strings.configLine(state.deckSize, state.turnTimerSec,
                          state.maxPlayers),
                      textAlign: TextAlign.center,
                      style: TrudeType.cardIndex.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        color: TrudeColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _configRow(BuildContext context, String label, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TrudeType.etched.copyWith(
                  fontSize: 10.5, letterSpacing: 2),
            ),
          ),
          control,
        ],
      ),
    );
  }
}

/// The engraved brass room-code plate; tapping copies the code (the copy
/// glyph flips to a check for a moment — no extra strings needed).
class _RoomCodePlate extends StatefulWidget {
  const _RoomCodePlate({required this.code});

  final String code;

  @override
  State<_RoomCodePlate> createState() => _RoomCodePlateState();
}

class _RoomCodePlateState extends State<_RoomCodePlate> {
  bool _copied = false;
  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    _revert?.cancel();
    _revert = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: TrudeGradients.brass,
          borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
          border: Border.all(color: TrudeColors.brassDark, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: TrudeColors.midnight.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                Strings.roomCodeLabel(widget.code),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrudeType.cardIndex.copyWith(
                  fontSize: 16.5,
                  letterSpacing: 1.6,
                  color: TrudeColors.textOnBrass,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 17,
              color: TrudeColors.textOnBrass,
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the real game table: an oval of lit felt on a mahogany
/// rail, with the seats arranged around it (mine at the bottom). Empty seats
/// render as hollow placeholders up to the room's max.
class _TablePreview extends StatelessWidget {
  const _TablePreview({
    required this.state,
    required this.blocked,
    required this.onTapPlayer,
  });

  final ClientGameState state;
  final Set<String> blocked;
  final void Function(PlayerView) onTapPlayer;

  static const _nodeW = 74.0;
  static const _nodeH = 88.0;
  static const _height = 300.0;

  @override
  Widget build(BuildContext context) {
    final seatCount =
        max(state.maxPlayers, state.players.length).clamp(2, 8);
    final mySeat = state.me?.seat ?? 0;
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final rx = (w - _nodeW) / 2 - 2;
          final ry = (_height - _nodeH) / 2 - 2;
          final ovalW = w - _nodeW - 30;
          final ovalH = _height - _nodeH - 30;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The felt oval with its wooden rail and brass trim.
              Center(
                child: Container(
                  width: ovalW,
                  height: ovalH,
                  decoration: BoxDecoration(
                    color: TrudeColors.railWood,
                    borderRadius: BorderRadius.all(
                        Radius.elliptical(ovalW / 2, ovalH / 2)),
                    border: Border.all(
                        color: TrudeColors.railWoodLit, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: TrudeColors.midnight.withValues(alpha: 0.6),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(7),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: TrudeGradients.feltLight,
                      borderRadius: BorderRadius.all(Radius.elliptical(
                          (ovalW - 14) / 2, (ovalH - 14) / 2)),
                      border: Border.all(color: TrudeColors.hairline),
                    ),
                    child: const Center(
                      child: TrudeCardBack(width: 26),
                    ),
                  ),
                ),
              ),
              for (var seat = 0; seat < seatCount; seat++)
                _positionSeat(w, rx, ry, seat, seatCount, mySeat),
            ],
          );
        },
      ),
    );
  }

  Widget _positionSeat(
      double w, double rx, double ry, int seat, int seatCount, int mySeat) {
    // Rotate so my seat sits at the bottom of the oval.
    final rel = (seat - mySeat) % seatCount;
    final angle = pi / 2 + 2 * pi * rel / seatCount;
    final cx = w / 2 + rx * cos(angle);
    final cy = _height / 2 + ry * sin(angle);
    final player = state.playerAtSeat(seat);
    return Positioned(
      left: cx - _nodeW / 2,
      top: cy - _nodeH / 2,
      width: _nodeW,
      height: _nodeH,
      child: player == null
          ? const _EmptySeat()
          : _SeatNode(
              player: player,
              blocked: blocked,
              isMe: player.userId == state.me?.userId,
              onTap: () => onTapPlayer(player),
            ),
    );
  }
}

class _SeatNode extends StatelessWidget {
  const _SeatNode({
    required this.player,
    required this.blocked,
    required this.isMe,
    this.onTap,
  });

  final PlayerView player;
  final Set<String> blocked;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = maskedInitial(blocked, player.userId, player.nickname);
    return PressableScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TrudeColors.surfaceSunken,
                  border: Border.all(
                    color: isMe
                        ? TrudeColors.brassBright
                        : (player.connected
                            ? TrudeColors.brassDark
                            : TrudeColors.hairline),
                    width: isMe ? 2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: TrudeColors.midnight.withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TrudeType.cardIndex.copyWith(
                      fontSize: 19,
                      color: player.connected
                          ? TrudeColors.brassBright
                          : TrudeColors.textMuted,
                    ),
                  ),
                ),
              ),
              if (player.isAdmin)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: TrudeColors.surfacePanel,
                    ),
                    child: const Icon(Icons.star,
                        size: 12, color: TrudeColors.brass),
                  ),
                ),
              if (!player.connected)
                Positioned(
                  bottom: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: TrudeColors.surfacePanel,
                    ),
                    child: const Icon(Icons.power_off,
                        size: 11, color: TrudeColors.lie),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            maskedNickname(blocked, player.userId, player.nickname),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: TrudeColors.textPrimary),
          ),
          if (isMe)
            Text(
              Strings.youBadge.toUpperCase(),
              maxLines: 1,
              style: TrudeType.etched.copyWith(
                  fontSize: 8, letterSpacing: 1.5),
            ),
        ],
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TrudeColors.surfaceSunken.withValues(alpha: 0.55),
            border: Border.all(color: TrudeColors.hairline),
          ),
          child: Icon(
            Icons.event_seat_outlined,
            size: 18,
            color: TrudeColors.textMuted.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
