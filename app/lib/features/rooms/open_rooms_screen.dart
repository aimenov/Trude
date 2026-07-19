import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/error_messages.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../game/widgets/card_widgets.dart';
import '../home/parlor_widgets.dart';

/// One entry of the Colyseus LobbyRoom listing.
class RoomListing {
  const RoomListing({
    required this.roomId,
    required this.name,
    required this.players,
    required this.maxPlayers,
    required this.deckSize,
  });

  factory RoomListing.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map
        ? (json['metadata'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return RoomListing(
      roomId: json['roomId'] as String,
      name: (metadata['name'] as String?) ?? (json['name'] as String? ?? ''),
      players: (json['clients'] as num?)?.toInt() ??
          (metadata['playerCount'] as num?)?.toInt() ??
          0,
      maxPlayers: (json['maxClients'] as num?)?.toInt() ??
          (metadata['maxPlayers'] as num?)?.toInt() ??
          0,
      deckSize: (metadata['deckSize'] as num?)?.toInt() ?? 37,
    );
  }

  final String roomId;
  final String name;
  final int players;
  final int maxPlayers;
  final int deckSize;
}

class OpenRoomsScreen extends ConsumerStatefulWidget {
  const OpenRoomsScreen({super.key});

  @override
  ConsumerState<OpenRoomsScreen> createState() => _OpenRoomsScreenState();
}

class _OpenRoomsScreenState extends ConsumerState<OpenRoomsScreen> {
  TrudeRoom? _lobby;
  StreamSubscription<RoomMessage>? _sub;
  final _rooms = <String, RoomListing>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      await ref.read(sessionProvider.notifier).ensure();
      final lobby = await ref.read(trudeClientProvider).joinLobby();
      _sub = lobby.messages.listen(_onLobbyMessage);
      if (!mounted) {
        _sub?.cancel();
        unawaited(lobby.leave());
        return;
      }
      setState(() => _lobby = lobby);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyRoomError(e, creating: false));
      }
    }
  }

  void _onLobbyMessage(RoomMessage m) {
    switch (m.type) {
      case 'rooms': // initial full listing
        final list = (m.data as List? ?? const [])
            .whereType<Map>()
            .map((e) => RoomListing.fromJson(e.cast<String, dynamic>()));
        setState(() {
          _rooms
            ..clear()
            ..addEntries(list.map((r) => MapEntry(r.roomId, r)));
        });
      case '+': // [roomId, data] upsert
        final data = m.data as List;
        final listing =
            RoomListing.fromJson((data[1] as Map).cast<String, dynamic>());
        setState(() => _rooms[data[0] as String] = listing);
      case '-': // roomId removal
        setState(() => _rooms.remove(m.data as String));
      default:
        break;
    }
  }

  Future<void> _join(RoomListing listing) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(currentRoomProvider.notifier).joinById(listing.roomId);
      if (mounted) context.go('/lobby');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyRoomError(e, creating: false))));
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    final lobby = _lobby;
    if (lobby != null) unawaited(lobby.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms.values.toList();
    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.openRoomsTitle),
          leading: BackButton(onPressed: () => context.go('/home')),
        ),
        body: switch ((_error, _lobby)) {
          (final String error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ParlorPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_outlined,
                          color: TrudeColors.textMuted, size: 30),
                      const SizedBox(height: 10),
                      Text(error,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: TrudeColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          (_, null) => const Center(child: CircularProgressIndicator()),
          _ when rooms.isEmpty => const _EmptyParlor(),
          _ => ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => RoomCard(
                room: rooms[i],
                onJoin: _busy ? null : () => _join(rooms[i]),
              ),
            ),
        },
      ),
    );
  }
}

/// Empty state: a lone joker propped against the wry serif line.
class _EmptyParlor extends StatelessWidget {
  const _EmptyParlor();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -0.09,
              child: const TrudeCardFace(rank: 'JOKER', width: 84),
            ),
            const SizedBox(height: 22),
            Text(
              Strings.noRoomsYet,
              textAlign: TextAlign.center,
              style: TrudeType.cardIndex.copyWith(
                fontStyle: FontStyle.italic,
                fontSize: 16,
                color: TrudeColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One room as a felt-swatch card: mini felt gradient, serif room name,
/// ivory seat chips, a tiny fanned deck icon, and a brass join button.
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.room, this.onJoin});

  final RoomListing room;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onJoin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          gradient: const RadialGradient(
            center: Alignment(-0.4, -0.6),
            radius: 1.6,
            colors: [
              TrudeColors.feltLit,
              TrudeColors.felt,
              TrudeColors.feltDeep,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
          border: Border.all(color: TrudeColors.hairline),
          boxShadow: [
            BoxShadow(
              color: TrudeColors.midnight.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _DeckFanIcon(deckSize: room.deckSize),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrudeType.display.copyWith(
                        fontSize: 17, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      // Up to 8 fixed-size chips can't shrink on their own:
                      // scale the row down instead of overflowing.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _SeatChips(
                              players: room.players,
                              maxPlayers: room.maxPlayers),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          Strings.playersOf(room.players, room.maxPlayers),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: TrudeColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              child: BrassButton(
                height: 40,
                onPressed: onJoin,
                child: Text(Strings.join,
                    style: const TextStyle(fontSize: 14, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Occupied seats as solid ivory chips, free seats as hollow rings.
class _SeatChips extends StatelessWidget {
  const _SeatChips({required this.players, required this.maxPlayers});

  final int players;
  final int maxPlayers;

  @override
  Widget build(BuildContext context) {
    final total = maxPlayers.clamp(players, 8);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < players ? TrudeColors.ivory : null,
                border: Border.all(
                  color: i < players
                      ? TrudeColors.ivoryShade
                      : TrudeColors.hairline,
                  width: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The deck-size marker: a tiny fanned stack of card backs with the size
/// etched beneath (37 fans three cards, 53 fans four).
class _DeckFanIcon extends StatelessWidget {
  const _DeckFanIcon({required this.deckSize});

  final int deckSize;

  @override
  Widget build(BuildContext context) {
    final cards = deckSize > 40 ? 4 : 3;
    return SizedBox(
      width: 46,
      height: 54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 46,
            height: 36,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < cards; i++)
                  _miniCard(cards == 1 ? 0.0 : i / (cards - 1) - 0.5),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            Strings.deckBadge(deckSize),
            // height 1.0: the serif's implicit line height (~16px at 11px)
            // busts the 54px budget by 1px otherwise.
            style: TrudeType.etched.copyWith(
                fontSize: 11, letterSpacing: 1.5, height: 1.0,
                color: TrudeColors.brassBright),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(double t) {
    return Positioned(
      bottom: 0,
      child: Transform.translate(
        offset: Offset(t * 16, t.abs() * 3),
        child: Transform.rotate(
          angle: t * 0.5,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 17,
            height: 17 * kCardAspect,
            decoration: BoxDecoration(
              color: TrudeColors.cardBackTeal,
              borderRadius: BorderRadius.circular(2.5),
              border: Border.all(color: TrudeColors.ivory, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}
