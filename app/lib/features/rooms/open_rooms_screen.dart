import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';

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
      if (mounted) setState(() => _error = '$e');
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Strings.joinFailed('$e'))));
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
    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.openRoomsTitle),
        leading: BackButton(onPressed: () => context.go('/home')),
      ),
      body: switch ((_error, _lobby)) {
        (final String error, _) => Center(child: Text(error)),
        (_, null) => const Center(child: CircularProgressIndicator()),
        _ when rooms.isEmpty =>
          Center(child: Text(Strings.noRoomsYet)),
        _ => ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              return ListTile(
                title: Text(room.name),
                subtitle:
                    Text(Strings.playersOf(room.players, room.maxPlayers)),
                trailing: Chip(label: Text(Strings.deckBadge(room.deckSize))),
                onTap: _busy ? null : () => _join(room),
              );
            },
          ),
      },
    );
  }
}
