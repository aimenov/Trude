import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/net/meta_providers.dart';
import '../../core/net/moderation_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../achievements/achievement_art.dart';
import '../achievements/achievement_toast.dart';
import '../economy/rewards_providers.dart';
import '../game/widgets/card_widgets.dart';
import '../home/parlor_widgets.dart';
import '../leaderboard/rating_tiers.dart';
import '../moderation/player_actions_sheet.dart';
import '../shop/shop_widgets.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(currentRoomProvider, (prev, next) {
      if (next == null) context.go('/home');
    });

    final state = ref.watch(gameStateProvider);
    final results = state.lastResults;
    final placements = [...?results?.placements]
      ..sort((a, b) => a.placement.compareTo(b.placement));
    final unlocked = ref.watch(unlockedThisGameProvider);
    final blocked = ref.watch(blockedIdsProvider);
    final myUserId = ref.watch(sessionProvider)?.userId ?? state.me?.userId;

    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.resultsTitle),
          leading: BackButton(onPressed: () => context.go('/home')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final entry in placements)
                        _PlacementPlaque(
                          state: state,
                          results: results!,
                          entry: entry,
                          blocked: blocked,
                          // Tap a row -> report/block sheet; never for self.
                          onTap: entry.userId == myUserId
                              ? null
                              : () => showPlayerActionsSheet(
                                    context,
                                    ref,
                                    userId: entry.userId,
                                    nickname: state
                                            .playerById(entry.userId)
                                            ?.nickname ??
                                        Strings.seatName(entry.seat),
                                  ),
                        ),
                      const RewardPanel(),
                      if (unlocked.isNotEmpty) ...[
                        const EtchedDivider(),
                        Text(
                          Strings.unlockedThisGame,
                          textAlign: TextAlign.center,
                          style: TrudeType.etched.copyWith(
                              fontSize: 11, letterSpacing: 2.4),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final a in unlocked)
                              _UnlockChip(
                                emoji: achievementEmoji(a.key),
                                title:
                                    Strings.achievementTitle(a.key, a.title),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: BrassButton(
                          onPressed: () => context.go('/lobby'),
                          child: Text(Strings.stayForRematch,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56)),
                          onPressed: () async {
                            await ref
                                .read(currentRoomProvider.notifier)
                                .leaveRoom();
                            if (context.mounted) context.go('/home');
                          },
                          child: Text(Strings.leave),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One podium row: an engraved plaque with a placement medallion, serif name,
/// and etched stat line. First place gets the brass treatment; the joker
/// loser gets a spotlight ring and the joker card itself.
class _PlacementPlaque extends StatelessWidget {
  const _PlacementPlaque({
    required this.state,
    required this.results,
    required this.entry,
    required this.blocked,
    this.onTap,
  });

  final ClientGameState state;
  final GameOverEvent results;
  final PlacementEntry entry;
  final Set<String> blocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final player = state.playerById(entry.userId);
    final nickname = maskedNickname(blocked, entry.userId,
        player?.nickname ?? Strings.seatName(entry.seat));
    final isLoser = entry.userId == results.loserUserId;
    final isWinner = entry.placement == 1;

    final stats = results.stats is Map ? results.stats as Map : const {};
    final playerStats =
        stats[entry.userId] is Map ? stats[entry.userId] as Map : const {};
    int stat(String key) => (playerStats[key] as num?)?.toInt() ?? 0;

    final plaque = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: isWinner ? TrudeGradients.brass : null,
        color: isWinner ? null : TrudeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(
          color: isWinner
              ? TrudeColors.brassDark
              : (isLoser ? TrudeColors.brass : TrudeColors.hairline),
          width: isLoser ? 1.4 : 1,
        ),
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
          _PlacementMedallion(entry: entry, isWinner: isWinner),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrudeType.display.copyWith(
                    fontSize: 17,
                    letterSpacing: 0.5,
                    color: isWinner
                        ? TrudeColors.textOnBrass
                        : TrudeColors.textPrimary,
                  ),
                ),
                if (entry.left)
                  // Mid-game leaver: etched «ПОКИНУЛ ИГРУ», the results-side
                  // sibling of the seat avatar's «ВЫШЕЛ».
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      Strings.leftGameBadge.toUpperCase(),
                      style: TrudeType.etched.copyWith(
                          fontSize: 9, letterSpacing: 1.2, height: 1.2),
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  Strings.statsLine(
                    stat('liesSurvived'),
                    stat('liesCaught'),
                    stat('checksWon'),
                  ),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: isWinner
                        ? TrudeColors.textOnBrass.withValues(alpha: 0.75)
                        : TrudeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isLoser) ...[
            const SizedBox(width: 10),
            const _JokerSpotlight(),
          ],
        ],
      ),
    );

    // Spotlight wash behind the loser's plaque.
    final body = !isLoser
        ? plaque
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.1,
                colors: [
                  TrudeColors.brassBright.withValues(alpha: 0.10),
                  TrudeColors.brassBright.withValues(alpha: 0),
                ],
              ),
            ),
            child: plaque,
          );
    if (onTap == null) return body;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: body);
  }
}

/// Engraved circular medallion with the placement label ("1st", "2nd", …).
class _PlacementMedallion extends StatelessWidget {
  const _PlacementMedallion({required this.entry, required this.isWinner});

  final PlacementEntry entry;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isWinner ? TrudeColors.brassBright : TrudeColors.surfaceSunken,
        border: Border.all(
          color: isWinner ? TrudeColors.brassDark : TrudeColors.brassDark,
          width: isWinner ? 2 : 1.2,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isWinner
                ? TrudeColors.brassDark.withValues(alpha: 0.6)
                : TrudeColors.hairline,
          ),
        ),
        child: Center(
          child: Text(
            Strings.placementLabel(entry.placement),
            style: TrudeType.display.copyWith(
              fontSize: 13,
              letterSpacing: 0,
              color: isWinner
                  ? TrudeColors.textOnBrass
                  : TrudeColors.brassBright,
            ),
          ),
        ),
      ),
    );
  }
}

/// The joker card in a small spotlight ring — the loser's reveal.
class _JokerSpotlight extends StatelessWidget {
  const _JokerSpotlight();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            TrudeColors.jokerPurple.withValues(alpha: 0.35),
            TrudeColors.jokerPurple.withValues(alpha: 0),
          ],
        ),
        border: Border.all(
            color: TrudeColors.brass.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Transform.rotate(
        angle: 0.12,
        child: const TrudeCardFace(rank: 'JOKER', width: 26),
      ),
    );
  }
}

/// «Выручка вечера» — coins, rating delta, and quest ticks for the finished
/// game, fed by [rewardsThisGameProvider] (null → collapses). The coin
/// counter counts up 0→N, and the «Удвоить выигрыш» rewarded-ad button
/// doubles it once (server-authoritative), leaving an etched «Удвоено».
class RewardPanel extends ConsumerStatefulWidget {
  const RewardPanel({super.key});

  @override
  ConsumerState<RewardPanel> createState() => _RewardPanelState();
}

class _RewardPanelState extends ConsumerState<RewardPanel> {
  bool _doubled = false;
  bool _doubling = false;
  bool _prepared = false;

  /// Preloads the rewarded ad + double token once the rewards (and their
  /// gameId) are known.
  void _maybePrepare(String? gameId) {
    if (_prepared) return;
    _prepared = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(adPrepareProvider)('double', gameId: gameId);
    });
  }

  Future<void> _double(String gameId) async {
    if (_doubling || _doubled) return;
    setState(() => _doubling = true);
    try {
      final got = await ref.read(adEarnProvider)('double', gameId: gameId);
      if (got != null && mounted) setState(() => _doubled = true);
    } catch (_) {
      // No reward, no error UI — the button just stays.
    } finally {
      if (mounted) setState(() => _doubling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rewards = ref.watch(rewardsThisGameProvider);
    if (rewards == null) return const SizedBox.shrink();
    final speed = ref.watch(animationSpeedProvider);
    final premium = ref.watch(meProvider).valueOrNull?.premium ?? false;
    // Loosely typed on purpose — only field names couple to the message
    // model, and null-safety holds whether the model uses int or int?.
    final dynamic msg = rewards;
    final int coins = (msg.coins as int?) ?? 0;
    final int coinTarget = _doubled ? coins * 2 : coins;
    final bool rated = msg.rated == true;
    final int ratingDelta = (msg.ratingDelta as int?) ?? 0;
    final int? newRating = msg.newRating as int?;
    final String? gameId = msg.gameId as String?;
    final List<dynamic> quests = (msg.quests as List?) ?? const [];
    _maybePrepare(gameId);

    return ParlorPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            Strings.rewardsPanelTitle.toUpperCase(),
            textAlign: TextAlign.center,
            style:
                TrudeType.etched.copyWith(fontSize: 10.5, letterSpacing: 2.4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.paid_outlined,
                  size: 22, color: TrudeColors.brassBright),
              const SizedBox(width: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: coinTarget.toDouble()),
                duration: speed.scale(const Duration(milliseconds: 900)),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '+${value.round()}',
                  style: TrudeType.display.copyWith(
                      fontSize: 28, color: TrudeColors.brassBright),
                ),
              ),
            ],
          ),
          if (rated && newRating != null) ...[
            const SizedBox(height: 8),
            Center(child: _RatingChip(delta: ratingDelta, rating: newRating)),
          ] else if (!rated) ...[
            const SizedBox(height: 6),
            Text(
              Strings.unratedGame,
              textAlign: TextAlign.center,
              style: TrudeType.cardIndex.copyWith(
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: TrudeColors.textMuted,
              ),
            ),
          ],
          if (quests.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final q in quests)
              _RewardQuestRow(quest: q, speed: speed),
          ],
          if (_doubled) ...[
            const SizedBox(height: 10),
            Text(
              Strings.doubledLabel.toUpperCase(),
              textAlign: TextAlign.center,
              style:
                  TrudeType.etched.copyWith(fontSize: 11, letterSpacing: 2.6),
            ),
          ] else if (!premium && coins > 0 && gameId != null)
            ValueListenableBuilder<bool>(
              valueListenable: ref.watch(rewardedAdReadyProvider),
              builder: (context, ready, _) => !ready
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: BrassButton(
                        height: 46,
                        onPressed: _doubling ? null : () => _double(gameId),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle_outline),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                Strings.doubleWinnings,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// «+12» in truth green (or «−8» in lie red) beside the new rating total and
/// its tier name.
class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.delta, required this.rating});

  final int delta;
  final int rating;

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final color = up ? TrudeColors.truth : TrudeColors.lie;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            up ? '+$delta' : '−${delta.abs()}',
            style: TrudeType.display.copyWith(fontSize: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            '$rating · ${Strings.tierName(tierFor(rating).key)}',
            style: TrudeType.cardIndex.copyWith(
                fontSize: 12.5, color: TrudeColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// One quest delta row on the reward panel: title, animated progress bar,
/// and the reward chip once crossed.
class _RewardQuestRow extends StatelessWidget {
  const _RewardQuestRow({required this.quest, required this.speed});

  final dynamic quest;
  final AnimationSpeed speed;

  @override
  Widget build(BuildContext context) {
    final int progress = quest.progress as int;
    final int target = quest.target as int;
    final bool completed = quest.completed as bool;
    final int questCoins = quest.coins as int;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                    fontSize: 12,
                    color: completed
                        ? TrudeColors.brassBright
                        : TrudeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                BrassProgressBar(
                  progress: target == 0 ? 0 : progress / target,
                  label: '${progress < target ? progress : target}/$target',
                  height: 10,
                  duration: speed.scale(const Duration(milliseconds: 600)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (completed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: TrudeColors.brassBright),
                const SizedBox(width: 4),
                Text(
                  Strings.questRewardChip(questCoins),
                  style: TrudeType.cardIndex.copyWith(
                      fontSize: 11.5, color: TrudeColors.brassBright),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A small parlor chip for an achievement unlocked this game.
class _UnlockChip extends StatelessWidget {
  const _UnlockChip({required this.emoji, required this.title});

  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius + 6),
        border: Border.all(color: TrudeColors.brassDark),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 7),
          Text(
            title,
            style: TrudeType.cardIndex.copyWith(
                fontSize: 12.5, color: TrudeColors.brassBright),
          ),
        ],
      ),
    );
  }
}
