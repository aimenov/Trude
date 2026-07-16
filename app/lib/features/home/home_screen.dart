import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/meta_providers.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import 'parlor_widgets.dart';

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
    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.appTitle.toUpperCase()),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrassFlourish(width: 190)),
                  const SizedBox(height: 16),
                  // Identity line: italic serif, with a quiet edit affordance.
                  Text(
                    Strings.playingAs(nickname),
                    textAlign: TextAlign.center,
                    style: TrudeType.cardIndex.copyWith(
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                      color: TrudeColors.textPrimary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/nickname'),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(Strings.changeNickname),
                    style: TextButton.styleFrom(
                      foregroundColor: TrudeColors.textMuted,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const _StatsStrip(),
                  const SizedBox(height: 22),
                  // The primary CTA: a grand brass slab.
                  BrassButton(
                    height: 62,
                    onPressed: _busy ? null : _createRoom,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.style_outlined),
                        const SizedBox(width: 10),
                        Text(Strings.createRoom),
                      ],
                    ),
                  ),
                  const EtchedDivider(),
                  // The parlor doors: four plaque cards.
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      _DoorPlaque(
                        icon: Icons.meeting_room_outlined,
                        label: Strings.openRooms,
                        onTap: _busy ? null : () => context.go('/rooms'),
                      ),
                      _DoorPlaque(
                        icon: Icons.vpn_key_outlined,
                        label: Strings.joinByCode,
                        onTap: _busy ? null : _joinByCode,
                      ),
                      _DoorPlaque(
                        icon: Icons.emoji_events_outlined,
                        label: Strings.achievementsTitle,
                        onTap: () => context.go('/achievements'),
                      ),
                      _DoorPlaque(
                        icon: Icons.settings_outlined,
                        label: Strings.settingsTitle,
                        onTap: () => context.go('/settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A parlor door plaque: raised panel, brass-ringed icon, serif label.
class _DoorPlaque extends StatelessWidget {
  const _DoorPlaque({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: TrudeColors.surfaceRaised,
          borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
          border: Border.all(color: TrudeColors.hairline),
          boxShadow: [
            BoxShadow(
              color: TrudeColors.midnight.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TrudeColors.surfaceSunken,
                border: Border.all(color: TrudeColors.brassDark),
              ),
              child: Icon(icon, size: 19, color: TrudeColors.brassBright),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TrudeType.cardIndex.copyWith(
                fontSize: 13.5,
                letterSpacing: 0.4,
                color: TrudeColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lifetime stats under the nickname as three brass-etched plaques
/// (games · wins · best streak); hidden while loading or when the server is
/// unreachable. Splits the localized strip string on its "·" separators so no
/// new l10n keys are needed.
class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(meProvider).valueOrNull?.stats;
    if (stats == null) return const SizedBox(height: 4);
    final strip = Strings.statsStrip(
        stats.gamesPlayed, stats.gamesWon, stats.bestWinStreak);
    final parts = strip.split('·').map((s) => s.trim()).toList();
    if (parts.length != 3) {
      // Locale without the expected separators: one plaque with the line.
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: EtchedPlaque(
            child: Text(strip,
                style: TrudeType.etched.copyWith(
                    fontSize: 11, letterSpacing: 1.2)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _StatPlaque(text: parts[i])),
          ],
        ],
      ),
    );
  }
}

/// One plaque: trailing number rendered big in serif over the etched label.
class _StatPlaque extends StatelessWidget {
  const _StatPlaque({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^(.*?)\s*(\d+)$').firstMatch(text);
    final label = match?.group(1) ?? text;
    final value = match?.group(2);
    return EtchedPlaque(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value,
                style: TrudeType.display.copyWith(
                    fontSize: 20,
                    height: 1.1,
                    color: TrudeColors.brassBright)),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TrudeType.etched.copyWith(
                fontSize: 8.5, letterSpacing: 1.4),
          ),
        ],
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
              style: TrudeType.etched.copyWith(fontSize: 11)),
          const SizedBox(height: 6),
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
        style: TrudeType.cardIndex.copyWith(
            fontSize: 20, letterSpacing: 4, color: TrudeColors.textPrimary),
        textAlign: TextAlign.center,
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
