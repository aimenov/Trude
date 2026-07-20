import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/sfx_service.dart';
import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/net/meta_providers.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/storage/settings_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../../core/version.dart';
import '../home/parlor_widgets.dart';
import '../shop/shop_widgets.dart';

/// Support contact shown (and copied) from the About panel — Apple 1.2 UGC
/// requires a reachable support address.
const _supportEmail = 'asatechnoltd@gmail.com';

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

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(billingRestoreProvider)();
      ref.invalidate(meProvider);
      messenger.showSnackBar(SnackBar(content: Text(Strings.restoreDone)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(Strings.saveFailed('$e'))));
    }
  }

  /// Double-confirmed account deletion: DELETE /me, then the local identity
  /// is wiped and the router lands on /nickname (store-policy requirement).
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    Future<bool> confirm(String title, String body) async =>
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(Strings.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: TrudeColors.lie,
                  foregroundColor: TrudeColors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(Strings.deleteAccountConfirm),
              ),
            ],
          ),
        ) ==
        true;

    if (!await confirm(
        Strings.deleteAccountTitle, Strings.deleteAccountBody)) {
      return;
    }
    if (!context.mounted) return;
    if (!await confirm(
        Strings.deleteAccountSecondTitle, Strings.deleteAccountSecondBody)) {
      return;
    }

    try {
      await ref.read(sessionProvider.notifier).ensure();
      await ref.read(trudeClientProvider).deleteMe();
      // Wipe the local identity + session so the router restarts the guest
      // flow from scratch.
      final client = ref.read(trudeClientProvider);
      client.token = null;
      client.session = null;
      ref.read(guestIdentityStoreProvider).clear();
      ref.invalidate(meProvider);
      ref.invalidate(sessionProvider);
      ref.invalidate(identityProvider);
      if (context.mounted) context.go('/nickname');
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(Strings.deleteAccountFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final speed = ref.watch(animationSpeedChoiceProvider);
    final nickname = ref.watch(identityProvider)?.nickname ?? '';

    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.settingsTitle),
          leading: BackButton(onPressed: () => context.go('/home')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Motion & feedback.
                ParlorPanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.speed,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.animationSpeedLabel,
                            style: _rowTitle),
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
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.soundLabel, style: _rowTitle),
                        value: settings.soundOn,
                        onChanged: (v) {
                          ref.read(settingsProvider.notifier).setSoundOn(v);
                          // Audible confirmation that sound is back on.
                          if (v) ref.read(sfxProvider).yourTurn();
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.vibration,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.hapticsLabel, style: _rowTitle),
                        value: settings.hapticsOn,
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setHapticsOn(v),
                      ),
                    ],
                  ),
                ),
                const EtchedDivider(),
                // Identity & language.
                ParlorPanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_outlined,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.nicknameLabel, style: _rowTitle),
                        subtitle: Text(
                          nickname,
                          style: TrudeType.cardIndex.copyWith(
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            color: TrudeColors.textMuted,
                          ),
                        ),
                        trailing: const Icon(Icons.edit,
                            size: 18, color: TrudeColors.brass),
                        onTap: () => _changeNickname(context, ref),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.language,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.languageLabel, style: _rowTitle),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SegmentedButton<String>(
                            segments: [
                              ButtonSegment(
                                  value: 'system',
                                  label: Text(Strings.languageSystem)),
                              ButtonSegment(
                                  value: 'en',
                                  label: Text(Strings.languageEnglish)),
                              ButtonSegment(
                                  value: 'ru',
                                  label: Text(Strings.languageRussian)),
                            ],
                            selected: {settings.localeCode},
                            onSelectionChanged: (v) => ref
                                .read(settingsProvider.notifier)
                                .setLocaleCode(v.single),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const EtchedDivider(),
                // Moderation: the block-management screen.
                ParlorPanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.block,
                        color: TrudeColors.brassBright),
                    title:
                        Text(Strings.blockedPlayersTitle, style: _rowTitle),
                    trailing: const Icon(Icons.chevron_right,
                        size: 20, color: TrudeColors.brass),
                    onTap: () => context.go('/blocked'),
                  ),
                ),
                const EtchedDivider(),
                // About & support.
                ParlorPanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.aboutLabel, style: _rowTitle),
                        subtitle: Text(
                          Strings.versionLabel(kAppVersion),
                          style: const TextStyle(
                              fontSize: 12.5, color: TrudeColors.textMuted),
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      // Tap-to-copy support address (no url_launcher dep).
                      ListTile(
                        leading: const Icon(Icons.mail_outline,
                            color: TrudeColors.brassBright),
                        title: Text(Strings.supportLabel, style: _rowTitle),
                        subtitle: const Text(
                          _supportEmail,
                          style: TextStyle(
                              fontSize: 12.5, color: TrudeColors.textMuted),
                        ),
                        trailing: const Icon(Icons.copy_outlined,
                            size: 18, color: TrudeColors.brass),
                        onTap: () {
                          Clipboard.setData(
                              const ClipboardData(text: _supportEmail));
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(Strings.emailCopied)));
                        },
                      ),
                    ],
                  ),
                ),
                if (ref.watch(billingSupportedProvider)) ...[
                  const EtchedDivider(),
                  // Store purchases.
                  ParlorPanel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.restore,
                          color: TrudeColors.brassBright),
                      title: Text(Strings.restorePurchases, style: _rowTitle),
                      onTap: () => _restorePurchases(context, ref),
                    ),
                  ),
                ],
                const EtchedDivider(),
                // The one destructive row: account deletion (double-confirm).
                ParlorPanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.delete_forever_outlined,
                        color: TrudeColors.lie),
                    title: Text(
                      Strings.deleteAccount,
                      style: _rowTitle.copyWith(color: TrudeColors.lie),
                    ),
                    onTap: () => _deleteAccount(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static final _rowTitle = TrudeType.cardIndex.copyWith(
    fontSize: 15,
    letterSpacing: 0.3,
    color: TrudeColors.textPrimary,
  );
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
