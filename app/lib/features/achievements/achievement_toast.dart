/// Parlor toasts: a top-center sliding brass plaque with a shine sweep,
/// shared by achievement unlocks and rating rank-ups.
///
/// [parlorToastProvider] owns the queue: achievement unlocks stream in from
/// the room's `achievementUnlocked` messages, rank-up toasts fire when a
/// rewards message crosses a rating-tier threshold, and anything else can
/// [ParlorToastController.show] one. Never interrupts a running set piece:
/// while the AnimationQueue is busy ([animationBusyProvider]) toasts queue up
/// and surface only once the queue drains. Unlocks are also accumulated per
/// game for the results screen ([unlockedThisGameProvider]).
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../economy/rewards_providers.dart';
import '../game/anim/rendered_state.dart';
import '../leaderboard/rating_tiers.dart';
import 'achievement_art.dart';

/// Unlocks received since the current game started; cleared on gameStarted.
final unlockedThisGameProvider =
    NotifierProvider<UnlockedThisGameController, List<AchievementUnlocked>>(
        UnlockedThisGameController.new);

class UnlockedThisGameController extends Notifier<List<AchievementUnlocked>> {
  @override
  List<AchievementUnlocked> build() {
    final room = ref.watch(currentRoomProvider);
    if (room != null) {
      final subs = [
        room.onAchievement.listen((a) => state = [...state, a]),
        room.onEvents.listen((batch) {
          if (batch.events.any((e) => e is GameStartedEvent)) state = const [];
        }),
      ];
      ref.onDispose(() {
        for (final s in subs) {
          s.cancel();
        }
      });
    }
    return const [];
  }
}

/// One toast's content: emoji medallion, small etched overline, serif title.
@immutable
class ParlorToast {
  const ParlorToast({
    required this.emoji,
    required this.overline,
    required this.title,
  });

  final String emoji;
  final String overline;
  final String title;
}

/// The toast currently on screen (null = hidden). New toasts queue behind
/// the animation queue and each other.
final parlorToastProvider =
    NotifierProvider<ParlorToastController, ParlorToast?>(
        ParlorToastController.new);

class ParlorToastController extends Notifier<ParlorToast?> {
  final Queue<ParlorToast> _pending = Queue();
  Timer? _holdTimer;

  /// Slide-in + shine + hold + slide-out budget for one toast.
  static const displayDuration = Duration(milliseconds: 3100);

  @override
  ParlorToast? build() {
    final room = ref.watch(currentRoomProvider);
    // When the set-piece queue drains, surface anything that was deferred.
    ref.listen(animationBusyProvider, (_, busy) {
      if (!busy) _pump();
    });
    if (room != null) {
      final sub = room.onAchievement.listen((a) {
        show(ParlorToast(
          emoji: achievementEmoji(a.key),
          overline: Strings.achievementUnlockedToast,
          title: Strings.achievementTitle(a.key, a.title),
        ));
      });
      ref.onDispose(sub.cancel);
    }
    // Rank-up: fires once when the game's rewards land with a rating that
    // crossed a tier threshold upward.
    ref.listen(rewardsThisGameProvider, (prev, next) {
      if (next == null || identical(prev, next)) return;
      // Loosely typed on purpose — only field names couple to the message
      // model, and null-safety holds whether the model uses int or int?.
      final dynamic msg = next;
      if (msg.rated != true) return;
      final int? newRating = msg.newRating as int?;
      final int delta = (msg.ratingDelta as int?) ?? 0;
      if (newRating == null || delta <= 0) return;
      if (tierIndexFor(newRating) <= tierIndexFor(newRating - delta)) return;
      show(ParlorToast(
        emoji: '\u{1F3A9}', // 🎩
        overline: Strings.rankUpToast,
        title: Strings.tierName(tierFor(newRating).key),
      ));
    });
    ref.onDispose(() {
      _holdTimer?.cancel();
      _holdTimer = null;
    });
    return null;
  }

  /// Queues [toast]; it surfaces as soon as no set piece is playing and no
  /// earlier toast is on screen.
  void show(ParlorToast toast) {
    _pending.add(toast);
    _pump();
  }

  void _pump() {
    if (state != null || _pending.isEmpty) return;
    // Defer while a set piece is playing; retried when busy flips false.
    if (ref.read(animationBusyProvider)) return;
    state = _pending.removeFirst();
    _holdTimer = Timer(displayDuration, () {
      state = null;
      _pump();
    });
  }
}

/// Mounted once in the MaterialApp builder (above the Navigator) so the
/// toast overlays any screen.
class AchievementToastHost extends ConsumerWidget {
  const AchievementToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(parlorToastProvider);
    return Stack(
      children: [
        child,
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1.4),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: toast == null
                  ? const SizedBox.shrink()
                  : BrassToastCard(key: ObjectKey(toast), toast: toast),
            ),
          ),
        ),
      ],
    );
  }
}

/// A sliding brass plaque: brushed gradient, ivory emoji medallion, engraved
/// serif title, one shine sweep after it lands.
class BrassToastCard extends StatefulWidget {
  const BrassToastCard({super.key, required this.toast});

  final ParlorToast toast;

  @override
  State<BrassToastCard> createState() => _BrassToastCardState();
}

class _BrassToastCardState extends State<BrassToastCard>
    with SingleTickerProviderStateMixin {
  // One shine sweep across the badge shortly after it lands.
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TrudeDims.chipRadius + 2),
          child: AnimatedBuilder(
            animation: _shine,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TrudeColors.ivory.withValues(alpha: 0),
                  TrudeColors.ivory.withValues(alpha: 0.4),
                  TrudeColors.ivory.withValues(alpha: 0),
                ],
                stops: const [0.35, 0.5, 0.65],
                transform:
                    _SlideGradientTransform(_shine.value * 3 - 1.5),
              ).createShader(bounds),
              child: child,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: TrudeGradients.brass,
                borderRadius:
                    BorderRadius.circular(TrudeDims.chipRadius + 2),
                border:
                    Border.all(color: TrudeColors.brassDark, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: TrudeColors.midnight.withValues(alpha: 0.55),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TrudeColors.ivory,
                      border: Border.all(color: TrudeColors.brassDark),
                    ),
                    child: Center(
                      child: Text(widget.toast.emoji,
                          style: const TextStyle(fontSize: 21)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.toast.overline.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TrudeType.etched.copyWith(
                            fontSize: 9,
                            letterSpacing: 2,
                            color: TrudeColors.textOnBrass
                                .withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.toast.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TrudeType.display.copyWith(
                            fontSize: 15,
                            letterSpacing: 0.4,
                            color: TrudeColors.textOnBrass,
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
      ),
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * dx, 0, 0);
}
