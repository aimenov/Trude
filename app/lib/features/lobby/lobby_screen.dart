import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart' hide Card;
import '../../core/strings.dart';

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

  Future<void> _tapPlayer(PlayerView player, ClientGameState state) async {
    if (player.userId == state.me?.userId) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(Strings.swapAsk(player.nickname)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(Strings.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(Strings.requestSwap)),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(currentRoomProvider)?.requestSeatSwap(player.userId);
    }
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
    final isAdmin = state.iAmAdmin;
    final swap = _incomingSwap;

    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.lobbyTitle),
        leading: BackButton(onPressed: _leave),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.roomCode != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  Strings.roomCodeLabel(state.roomCode!),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (swap != null)
            MaterialBanner(
              content: Text(Strings.swapIncoming(
                  state.playerAtSeat(swap.fromSeat)?.nickname ??
                      Strings.seatName(swap.fromSeat))),
              actions: [
                TextButton(
                    onPressed: () => _respondSwap(false),
                    child: Text(Strings.decline)),
                FilledButton(
                    onPressed: () => _respondSwap(true),
                    child: Text(Strings.accept)),
              ],
            ),
          const SizedBox(height: 8),
          for (final player in state.players)
            ListTile(
              leading: CircleAvatar(
                  child: Text(player.nickname.isEmpty
                      ? '?'
                      : player.nickname[0].toUpperCase())),
              title: Row(
                children: [
                  Flexible(child: Text(player.nickname)),
                  if (player.isAdmin)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.star, size: 18),
                    ),
                ],
              ),
              subtitle: player.userId == state.me?.userId
                  ? Text(Strings.youBadge)
                  : null,
              trailing: player.connected
                  ? null
                  : const Icon(Icons.power_off, size: 18),
              onTap: () => _tapPlayer(player, state),
            ),
          const Divider(),
          if (isAdmin) ...[
            _configRow(
              context,
              Strings.deckSizeLabel,
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 37, label: Text(Strings.deckOption(37))),
                  ButtonSegment(value: 53, label: Text(Strings.deckOption(53))),
                ],
                selected: {state.deckSize},
                onSelectionChanged: (v) => room?.configureRoom(
                    deckSize: v.single,
                    maxPlayers: state.maxPlayers
                        .clamp(2, _deckCap[v.single] ?? 6)),
              ),
            ),
            _configRow(
              context,
              Strings.turnTimerLabel,
              SegmentedButton<int>(
                segments: [
                  for (final s in const [15, 30, 60])
                    ButtonSegment(
                        value: s, label: Text(Strings.secondsOption(s))),
                ],
                selected: {state.turnTimerSec},
                onSelectionChanged: (v) =>
                    room?.configureRoom(turnTimerSec: v.single),
              ),
            ),
            _configRow(
              context,
              Strings.maxPlayersLabel,
              DropdownButton<int>(
                value: state.maxPlayers
                    .clamp(2, _deckCap[state.deckSize] ?? 6),
                items: [
                  for (var n = 2; n <= (_deckCap[state.deckSize] ?? 6); n++)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (n) =>
                    n == null ? null : room?.configureRoom(maxPlayers: n),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: state.players.length >= 2
                  ? () => room?.startGame()
                  : null,
              child: Text(Strings.start),
            ),
            if (state.players.length < 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(Strings.needTwoPlayers,
                    textAlign: TextAlign.center),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                Strings.configLine(
                    state.deckSize, state.turnTimerSec, state.maxPlayers),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _configRow(BuildContext context, String label, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.labelLarge)),
          control,
        ],
      ),
    );
  }
}
