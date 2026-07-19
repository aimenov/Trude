/// «Табель почёта» — weekly / all-time leaderboards. Weekly points are the
/// net rating change this ISO week; all-time is the persistent rating. The
/// viewer's row is highlighted in place, or pinned as a footer when their
/// rank does not appear on the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/economy_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../home/parlor_widgets.dart';
import 'rating_tiers.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderboardScope _scope = LeaderboardScope.weekly;

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(leaderboardProvider(_scope));
    final myUserId = ref.watch(sessionProvider)?.userId;

    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.leaderboardTitle),
          leading: BackButton(onPressed: () => context.go('/home')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SegmentedButton<LeaderboardScope>(
                    segments: [
                      ButtonSegment(
                          value: LeaderboardScope.weekly,
                          label: Text(Strings.leaderboardWeekly)),
                      ButtonSegment(
                          value: LeaderboardScope.alltime,
                          label: Text(Strings.leaderboardAlltime)),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (v) =>
                        setState(() => _scope = v.single),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: TrudeColors.brass,
                    backgroundColor: TrudeColors.surfaceRaised,
                    onRefresh: () =>
                        ref.refresh(leaderboardProvider(_scope).future),
                    child: switch (page) {
                      AsyncData(:final value) =>
                        _list(context, value, myUserId),
                      AsyncError() => _scrollableMessage(
                          context, Strings.leaderboardLoadFailed),
                      _ =>
                        const Center(child: CircularProgressIndicator()),
                    },
                  ),
                ),
                _MyRankFooter(scope: _scope, myUserId: myUserId),
              ],
            ),
          ),
        ),
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
                child: Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TrudeColors.textMuted)),
              ),
            ),
          ],
        ),
      );

  Widget _list(BuildContext context, dynamic page, String? myUserId) {
    final List<dynamic> entries = page.entries as List<dynamic>;
    if (entries.isEmpty) {
      return _scrollableMessage(context, Strings.leaderboardEmpty);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return _LeaderRow(
          rank: e.rank as int,
          nickname: e.nickname as String,
          value: e.value as int,
          gamesRated: e.gamesRated as int,
          isMe: myUserId != null && e.userId == myUserId,
          showTier: _scope == LeaderboardScope.alltime,
        );
      },
    );
  }
}

/// One roll-of-honor row: rank medallion (brass intensity for the top 3),
/// serif name, etched games count, and the score on the right.
class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.rank,
    required this.nickname,
    required this.value,
    required this.gamesRated,
    required this.isMe,
    required this.showTier,
  });

  final int rank;
  final String nickname;
  final int value;
  final int gamesRated;
  final bool isMe;
  final bool showTier;

  @override
  Widget build(BuildContext context) {
    final top3 = rank <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: TrudeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(
          color: isMe
              ? TrudeColors.brass
              : (top3
                  ? TrudeColors.brass.withValues(alpha: 0.55)
                  : TrudeColors.hairline),
          width: isMe ? 1.5 : 1,
        ),
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
          _RankMedallion(rank: rank),
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
                    fontSize: 15,
                    letterSpacing: 0.4,
                    color: isMe
                        ? TrudeColors.brassBright
                        : TrudeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Strings.gamesRatedLabel(gamesRated),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: TrudeColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$value',
                style: TrudeType.display.copyWith(
                  fontSize: 18,
                  color: top3
                      ? TrudeColors.brassBright
                      : TrudeColors.textPrimary,
                ),
              ),
              if (showTier)
                Text(
                  Strings.tierName(tierFor(value).key),
                  style: TrudeType.etched.copyWith(
                      fontSize: 8.5, letterSpacing: 1.2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rank number in an engraved ring; the top three get progressively brighter
/// brass and a heavier ring.
class _RankMedallion extends StatelessWidget {
  const _RankMedallion({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final (ring, ringWidth, fill) = switch (rank) {
      1 => (TrudeColors.brassBright, 2.4, TrudeColors.brassBright),
      2 => (TrudeColors.brass, 2.0, TrudeColors.brass),
      3 => (TrudeColors.brassDark, 1.7, TrudeColors.brass),
      _ => (TrudeColors.hairline, 1.2, TrudeColors.textMuted),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TrudeColors.surfaceSunken,
        border: Border.all(color: ring, width: ringWidth),
      ),
      child: Center(
        child: Text(
          '$rank',
          style: TrudeType.display.copyWith(fontSize: 14, color: fill),
        ),
      ),
    );
  }
}

/// Pinned footer with the viewer's own rank when their row is not on the
/// page (or they are unranked in this scope — then nothing is pinned).
class _MyRankFooter extends ConsumerWidget {
  const _MyRankFooter({required this.scope, required this.myUserId});

  final LeaderboardScope scope;
  final String? myUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loosely typed on purpose — only rank/value/entries are touched, so the
    // footer does not compile-couple to the page model class.
    final dynamic page = ref.watch(leaderboardProvider(scope)).valueOrNull;
    final dynamic me = page?.me;
    if (page == null || me == null) return const SizedBox.shrink();
    final List<dynamic> entries = page.entries as List<dynamic>;
    final onPage =
        myUserId != null && entries.any((e) => e.userId == myUserId);
    if (onPage) return const SizedBox.shrink();
    final int value = me.value as int;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: EtchedPlaque(
        child: Row(
          children: [
            Expanded(
              child: Text(
                Strings.leaderboardMyRank(me.rank as int),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrudeType.cardIndex.copyWith(
                    fontSize: 13, color: TrudeColors.textPrimary),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$value',
                  style: TrudeType.display.copyWith(
                      fontSize: 17, color: TrudeColors.brassBright),
                ),
                if (scope == LeaderboardScope.alltime)
                  Text(
                    Strings.tierName(tierFor(value).key),
                    style: TrudeType.etched.copyWith(
                        fontSize: 8.5, letterSpacing: 1.2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
