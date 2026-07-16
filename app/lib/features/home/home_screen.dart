import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/meta_providers.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/strings.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Home regains focus by being rebuilt on navigation (go_router swaps the
    // page), so a fresh state means fresh lifetime stats.
    Future.microtask(() {
      if (mounted) ref.invalidate(meProvider);
    });
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Strings.joinFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRoom() async {
    final config = await showDialog<_CreateRoomConfig>(
      context: context,
      builder: (_) => _CreateRoomDialog(
          defaultName: ref.read(identityProvider)?.nickname ?? ''),
    );
    if (config == null) return;
    await _guarded(() async {
      await ref.read(currentRoomProvider.notifier).createRoom(
            name: config.name,
            private: config.private,
            deckSize: config.deckSize,
          );
      if (mounted) context.go('/lobby');
    });
  }

  Future<void> _joinByCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinByCodeDialog(),
    );
    if (code == null || code.isEmpty) return;
    await _guarded(() async {
      await ref.read(currentRoomProvider.notifier).joinByCode(code);
      if (mounted) context.go('/lobby');
    });
  }

  @override
  Widget build(BuildContext context) {
    final nickname = ref.watch(identityProvider)?.nickname ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.appTitle),
        actions: [
          IconButton(
            tooltip: Strings.achievementsTitle,
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => context.go('/achievements'),
          ),
          IconButton(
            tooltip: Strings.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(Strings.playingAs(nickname),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center),
                const _StatsStrip(),
                TextButton(
                  onPressed: () => context.go('/nickname'),
                  child: Text(Strings.changeNickname),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _createRoom,
                  child: Text(Strings.createRoom),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => context.go('/rooms'),
                  child: Text(Strings.openRooms),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _joinByCode,
                  child: Text(Strings.joinByCode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lifetime stats under the nickname (games · wins · best streak); hidden
/// while loading or when the server is unreachable.
class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(meProvider).valueOrNull?.stats;
    if (stats == null) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        Strings.statsStrip(
            stats.gamesPlayed, stats.gamesWon, stats.bestWinStreak),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _CreateRoomConfig {
  const _CreateRoomConfig(this.name, this.private, this.deckSize);

  final String name;
  final bool private;
  final int deckSize;
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.defaultName});

  final String defaultName;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  late final TextEditingController _name;
  bool _private = false;
  int _deckSize = 37;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: widget.defaultName.isEmpty
            ? Strings.appTitle
            : widget.defaultName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.createRoomTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(labelText: Strings.roomNameHint),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(Strings.publicRoom)),
              ButtonSegment(value: true, label: Text(Strings.privateRoom)),
            ],
            selected: {_private},
            onSelectionChanged: (v) => setState(() => _private = v.single),
          ),
          const SizedBox(height: 16),
          Text(Strings.deckLabel,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 37, label: Text(Strings.deckOption(37))),
              ButtonSegment(value: 53, label: Text(Strings.deckOption(53))),
            ],
            selected: {_deckSize},
            onSelectionChanged: (v) => setState(() => _deckSize = v.single),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
              _CreateRoomConfig(_name.text.trim(), _private, _deckSize)),
          child: Text(Strings.create),
        ),
      ],
    );
  }
}

class _JoinByCodeDialog extends StatefulWidget {
  const _JoinByCodeDialog();

  @override
  State<_JoinByCodeDialog> createState() => _JoinByCodeDialogState();
}

class _JoinByCodeDialogState extends State<_JoinByCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.joinByCodeTitle),
      content: TextField(
        controller: _code,
        autofocus: true,
        maxLength: 6,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: Strings.roomCodeHint),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim().toUpperCase()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_code.text.trim().toUpperCase()),
          child: Text(Strings.join),
        ),
      ],
    );
  }
}
