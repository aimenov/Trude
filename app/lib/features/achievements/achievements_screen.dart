import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/meta_models.dart';
import '../../core/net/meta_providers.dart';
import '../../core/strings.dart';
import 'achievement_art.dart';

/// Badge grid from the server catalog: unlocked badges bright with their
/// unlock date, locked ones greyed silhouettes with the description as hint.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.achievementsTitle),
        bottom: achievements.valueOrNull == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    Strings.achievementsCount(
                      achievements.valueOrNull!.unlocked.length,
                      achievements.valueOrNull!.catalog.length,
                    ),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(achievementsProvider.future),
        child: switch (achievements) {
          AsyncData(:final value) => _grid(context, value),
          AsyncError() => _scrollableMessage(
              context, Strings.achievementsLoadFailed),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  /// Pull-to-refresh needs a scrollable even for the error state.
  Widget _scrollableMessage(BuildContext context, String message) =>
      LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.8,
              child: Center(child: Text(message)),
            ),
          ],
        ),
      );

  Widget _grid(BuildContext context, MeAchievements data) {
    final unlockedByKey = data.unlockedByKey;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: data.catalog.length,
      itemBuilder: (context, i) {
        final info = data.catalog[i];
        return _BadgeCard(info: info, unlock: unlockedByKey[info.key]);
      },
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.info, required this.unlock});

  final AchievementInfo info;
  final AchievementUnlock? unlock;

  bool get _unlocked => unlock != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Strings.achievementTitle(info.key, info.title);
    final description =
        Strings.achievementDescription(info.key, info.description);

    final emoji = Text(
      achievementEmoji(info.key),
      style: const TextStyle(fontSize: 42),
    );

    return Card(
      elevation: _unlocked ? 3 : 0,
      color: _unlocked ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _unlocked
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Locked badges render as grey silhouettes.
            _unlocked
                ? emoji
                : ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        Colors.grey, BlendMode.srcIn),
                    child: Opacity(opacity: 0.45, child: emoji),
                  ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _unlocked
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _unlocked
                  ? Strings.unlockedOn(unlock!.unlockedDate)
                  : description,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _unlocked
                        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                        : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
