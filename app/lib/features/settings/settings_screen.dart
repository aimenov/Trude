import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/net/meta_providers.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/storage/settings_providers.dart';
import '../../core/strings.dart';
import '../../core/version.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _changeNickname(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = ref.read(identityProvider)?.nickname ?? '';
    final nickname = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initial: current),
    );
    if (nickname == null || nickname == current) return;
    try {
      // PATCH /me is the source of truth (server profanity check), then the
      // local identity + session token are refreshed to match.
      await ref.read(sessionProvider.notifier).ensure();
      final profile =
          await ref.read(trudeClientProvider).patchMe(nickname: nickname);
      await ref.read(sessionProvider.notifier).loginAs(profile.nickname);
      ref.invalidate(meProvider);
      messenger.showSnackBar(SnackBar(content: Text(Strings.nicknameSaved)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(Strings.saveFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final speed = ref.watch(animationSpeedChoiceProvider);
    final nickname = ref.watch(identityProvider)?.nickname ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(Strings.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text(Strings.animationSpeedLabel),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<AnimationSpeed>(
                segments: [
                  ButtonSegment(
                      value: AnimationSpeed.normal,
                      label: Text(Strings.speedNormal)),
                  ButtonSegment(
                      value: AnimationSpeed.fast,
                      label: Text(Strings.speedFast)),
                  ButtonSegment(
                      value: AnimationSpeed.off,
                      label: Text(Strings.speedOff)),
                ],
                selected: {speed},
                onSelectionChanged: (v) => ref
                    .read(animationSpeedChoiceProvider.notifier)
                    .set(v.single),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up),
            title: Text(Strings.soundLabel),
            value: settings.soundOn,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setSoundOn(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: Text(Strings.hapticsLabel),
            value: settings.hapticsOn,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setHapticsOn(v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(Strings.nicknameLabel),
            subtitle: Text(nickname),
            trailing: const Icon(Icons.edit),
            onTap: () => _changeNickname(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(Strings.languageLabel),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'system', label: Text(Strings.languageSystem)),
                  ButtonSegment(
                      value: 'en', label: Text(Strings.languageEnglish)),
                  ButtonSegment(
                      value: 'ru', label: Text(Strings.languageRussian)),
                ],
                selected: {settings.localeCode},
                onSelectionChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setLocaleCode(v.single),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(Strings.aboutLabel),
            subtitle: Text(Strings.versionLabel(kAppVersion)),
          ),
        ],
      ),
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  bool get _valid {
    final v = _controller.text.trim();
    return v.length >= 2 && v.length <= 16;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.changeNickname),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 16,
        decoration: InputDecoration(labelText: Strings.nicknameHint),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (_valid) Navigator.of(context).pop(v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(Strings.save),
        ),
      ],
    );
  }
}
