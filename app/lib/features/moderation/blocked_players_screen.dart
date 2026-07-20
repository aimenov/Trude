/// «Заблокированные игроки» — the block-management screen behind /blocked.
/// Lists everyone this user has blocked (from GET /me/blocks) with per-row
/// unblock buttons; unblocking hides the row immediately and refreshes the
/// list once the server confirms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/moderation_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../home/parlor_widgets.dart';

class BlockedPlayersScreen extends ConsumerStatefulWidget {
  const BlockedPlayersScreen({super.key});

  @override
  ConsumerState<BlockedPlayersScreen> createState() =>
      _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends ConsumerState<BlockedPlayersScreen> {
  /// Rows unblocked during this visit — hidden right away, so the list does
  /// not have to wait for the refetch.
  final _removed = <String>{};

  Future<void> _unblock(String userId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removed.add(userId));
    try {
      await ref.read(sessionProvider.notifier).ensure();
      // The optimistic set no-ops when the id never seeded (e.g. the seed
      // fetch failed) — fall back to the idempotent DELETE directly.
      if (ref.read(blockedIdsProvider).contains(userId)) {
        await ref.read(blockedIdsProvider.notifier).unblock(userId);
      } else {
        await ref.read(trudeClientProvider).unblockUser(userId);
      }
      ref.invalidate(blockedListProvider);
    } catch (e) {
      if (mounted) setState(() => _removed.remove(userId));
      messenger
          .showSnackBar(SnackBar(content: Text(Strings.saveFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(blockedListProvider);
    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.blockedPlayersTitle),
          leading: BackButton(onPressed: () => context.go('/settings')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: RefreshIndicator(
              color: TrudeColors.brass,
              backgroundColor: TrudeColors.surfaceRaised,
              onRefresh: () => ref.refresh(blockedListProvider.future),
              child: switch (page) {
                AsyncData(:final value) => _list(context, value),
                AsyncError() => _scrollableMessage(
                    context, Strings.leaderboardLoadFailed),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<BlockEntry> entries) {
    final visible =
        [for (final e in entries) if (!_removed.contains(e.userId)) e];
    if (visible.isEmpty) {
      return _scrollableMessage(context, Strings.blockedEmpty);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: visible.length,
      itemBuilder: (context, i) => _BlockedRow(
        entry: visible[i],
        onUnblock: () => _unblock(visible[i].userId),
      ),
    );
  }

  /// Pull-to-refresh needs a scrollable even for empty/error states.
  Widget _scrollableMessage(BuildContext context, String message) =>
      LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.8,
              child: Center(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TrudeType.cardIndex.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: TrudeColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.entry, required this.onUnblock});

  final BlockEntry entry;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: TrudeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(color: TrudeColors.hairline),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.block, size: 18, color: TrudeColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrudeType.display.copyWith(
                fontSize: 15,
                letterSpacing: 0.4,
                color: TrudeColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onUnblock,
            child: Text(Strings.unblockPlayer,
                style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
