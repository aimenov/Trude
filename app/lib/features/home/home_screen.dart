import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/net/economy_providers.dart';
import '../../core/net/error_messages.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../leaderboard/rating_tiers.dart';
import 'parlor_widgets.dart';

/// Daily-bonus curve by streak day 1..7+ (display only — the server is the
/// truth); day 7 is the cap.
const kDailyBonusByDay = [10, 15, 20, 30, 40, 50, 60];

/// Whether the daily-bonus sheet already auto-opened this app session.
final dailySheetShownProvider = StateProvider<bool>((_) => false);

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

  Future<void> _guarded(Future<void> Function() action,
      {required bool creating}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyRoomError(e, creating: creating))));
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
    await _guarded(creating: true, () async {
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
    await _guarded(creating: false, () async {
      await ref.read(currentRoomProvider.notifier).joinByCode(code);
      if (mounted) context.go('/lobby');
    });
  }

  /// Auto-opens the daily-bonus sheet: once per app session, only while the
  /// screen is idle (never over a create/join in flight).
  void _maybeShowDailySheet() {
    if (_busy || ref.read(dailySheetShownProvider)) return;
    if (!ref.read(dailyBonusProvider).claimable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy) return;
      // Home can rebuild while another route (lobby/table) is stacked on
      // top — the sheet would open OVER that route and swallow its taps.
      // Only auto-open while home itself is the current route.
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (ref.read(dailySheetShownProvider)) return;
      if (!ref.read(dailyBonusProvider).claimable) return;
      ref.read(dailySheetShownProvider.notifier).state = true;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const DailyBonusSheet(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final nickname = ref.watch(identityProvider)?.nickname ?? '';
    // Watched (not read) so a late claimable flip re-triggers the check.
    ref.watch(dailyBonusProvider);
    _maybeShowDailySheet();
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
                  const WalletRow(),
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
                  // The parlor doors: six plaque cards.
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
                        icon: Icons.storefront_outlined,
                        label: Strings.shopTitle,
                        onTap: () => context.go('/shop'),
                      ),
                      _DoorPlaque(
                        icon: Icons.leaderboard_outlined,
                        label: Strings.leaderboardTitle,
                        onTap: () => context.go('/leaderboard'),
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
                  const _QuestsPanel(),
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

/// Coin + rating chips under the identity line. Hidden until the profile
/// loads. The coin chip opens the shop, the rating chip (with its tier name)
/// opens the leaderboard; both numbers count up on change.
class WalletRow extends ConsumerWidget {
  const WalletRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(walletProvider);
    final rating = ref.watch(ratingProvider);
    if (coins == null && rating == null) return const SizedBox(height: 2);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (coins != null)
            _WalletChip(
              icon: Icons.paid_outlined,
              value: coins,
              onTap: () => context.go('/shop'),
            ),
          if (coins != null && rating != null) const SizedBox(width: 10),
          if (rating != null)
            _WalletChip(
              icon: Icons.military_tech_outlined,
              value: rating,
              caption: Strings.tierName(tierFor(rating).key),
              onTap: () => context.go('/leaderboard'),
            ),
        ],
      ),
    );
  }
}

class _WalletChip extends ConsumerWidget {
  const _WalletChip({
    required this.icon,
    required this.value,
    this.caption,
    this.onTap,
  });

  final IconData icon;
  final int value;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(animationSpeedProvider);
    return PressableScale(
      onTap: onTap,
      child: EtchedPlaque(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: TrudeColors.brassBright),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: speed.scale(const Duration(milliseconds: 700)),
                  builder: (context, v, _) => Text(
                    '${v.round()}',
                    style: TrudeType.display.copyWith(
                        fontSize: 16,
                        height: 1.1,
                        color: TrudeColors.brassBright),
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: TrudeType.etched.copyWith(
                        fontSize: 7.5, letterSpacing: 1.2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «Поручения на вечер» — the three daily quests as brass progress rows.
/// Collapses entirely while loading or on a provider error.
class _QuestsPanel extends ConsumerWidget {
  const _QuestsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(questsProvider);
    return switch (quests) {
      AsyncData(:final value) when value.quests.isNotEmpty => ParlorPanel(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Strings.questsTitle.toUpperCase(),
                textAlign: TextAlign.center,
                style: TrudeType.etched.copyWith(
                    fontSize: 10.5, letterSpacing: 2.4),
              ),
              const SizedBox(height: 10),
              for (final q in value.quests) _QuestRow(quest: q),
            ],
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.quest});

  final dynamic quest;

  @override
  Widget build(BuildContext context) {
    final int progress = quest.progress as int;
    final int target = quest.target as int;
    final bool completed = quest.completed as bool;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.questTitle(quest.key as String),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrudeType.cardIndex.copyWith(
                    fontSize: 13,
                    color: completed
                        ? TrudeColors.brassBright
                        : TrudeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Strings.questDescription(quest.key as String),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: TrudeColors.textMuted),
                ),
                const SizedBox(height: 4),
                BrassProgressBar(
                  progress: target == 0 ? 0 : progress / target,
                  label: '${min(progress, target)}/$target',
                  height: 11,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          completed
              ? const Icon(Icons.check_circle_outline,
                  size: 20, color: TrudeColors.brassBright)
              : Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: TrudeColors.surfaceSunken,
                    borderRadius:
                        BorderRadius.circular(TrudeDims.chipRadius),
                    border: Border.all(color: TrudeColors.brassDark),
                  ),
                  child: Text(
                    Strings.questRewardChip(quest.reward as int),
                    style: TrudeType.cardIndex.copyWith(
                        fontSize: 11.5, color: TrudeColors.brassBright),
                  ),
                ),
        ],
      ),
    );
  }
}

/// The daily-bonus bottom sheet: streak ribbon of the seven bonus slots and
/// a brass claim button. Claiming is server-authoritative; the wallet bumps
/// through [dailyBonusProvider].
class DailyBonusSheet extends ConsumerStatefulWidget {
  const DailyBonusSheet({super.key});

  @override
  ConsumerState<DailyBonusSheet> createState() => _DailyBonusSheetState();
}

class _DailyBonusSheetState extends ConsumerState<DailyBonusSheet> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      await ref.read(dailyBonusProvider.notifier).claim();
    } catch (_) {
      // Claim is idempotent server-side; a network hiccup just re-offers
      // the sheet next session.
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final streak =
        ref.watch(meProvider).valueOrNull?.dailyStreak ?? 0;
    // The day being claimed now (1-based); bonuses cap at day 7.
    final claimDay = streak + 1;
    final bonus = kDailyBonusByDay[min(claimDay, 7) - 1];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ParlorPanel(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Strings.dailyBonusTitle,
                textAlign: TextAlign.center,
                style: TrudeType.display.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 4),
              Text(
                Strings.dailyBonusSubtitle,
                textAlign: TextAlign.center,
                style: TrudeType.cardIndex.copyWith(
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  fontSize: 12.5,
                  color: TrudeColors.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var day = 1; day <= 7; day++) ...[
                    if (day > 1) const SizedBox(width: 5),
                    Expanded(
                      child: _StreakSlot(
                        day: day,
                        coins: kDailyBonusByDay[day - 1],
                        state: day < min(claimDay, 7)
                            ? _SlotState.past
                            : (day == min(claimDay, 7)
                                ? _SlotState.today
                                : _SlotState.future),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              BrassButton(
                height: 50,
                onPressed: _claiming ? null : _claim,
                child: Text(Strings.dailyBonusClaim(bonus)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SlotState { past, today, future }

class _StreakSlot extends StatelessWidget {
  const _StreakSlot({
    required this.day,
    required this.coins,
    required this.state,
  });

  final int day;
  final int coins;
  final _SlotState state;

  @override
  Widget build(BuildContext context) {
    final today = state == _SlotState.today;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: today ? TrudeGradients.brass : null,
        color: today ? null : TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(
          color: today
              ? TrudeColors.brassDark
              : (state == _SlotState.past
                  ? TrudeColors.brass.withValues(alpha: 0.55)
                  : TrudeColors.hairline),
        ),
      ),
      child: Column(
        children: [
          state == _SlotState.past
              ? const Icon(Icons.check, size: 13, color: TrudeColors.brass)
              : Text(
                  '$coins',
                  style: TrudeType.display.copyWith(
                    fontSize: 13,
                    height: 1.0,
                    color: today
                        ? TrudeColors.textOnBrass
                        : TrudeColors.brassBright,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            '$day',
            style: TrudeType.etched.copyWith(
              fontSize: 7.5,
              letterSpacing: 0.5,
              color: today
                  ? TrudeColors.textOnBrass.withValues(alpha: 0.8)
                  : TrudeColors.textMuted,
            ),
          ),
        ],
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            style: TrudeType.cardIndex.copyWith(
                fontSize: 20, letterSpacing: 4, color: TrudeColors.textPrimary),
            textAlign: TextAlign.center,
            decoration: InputDecoration(labelText: Strings.roomCodeHint),
            onSubmitted: (v) =>
                Navigator.of(context).pop(v.trim().toUpperCase()),
          ),
          const SizedBox(height: 6),
          Text(
            Strings.joinCodeDialogHint,
            textAlign: TextAlign.center,
            style: TrudeType.cardIndex.copyWith(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              fontSize: 12.5,
              color: TrudeColors.textMuted,
              height: 1.35,
            ),
          ),
        ],
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
