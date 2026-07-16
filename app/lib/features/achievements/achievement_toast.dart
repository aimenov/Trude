/// Achievement unlock toast: listens to the room's `achievementUnlocked`
/// messages and shows a top-center sliding badge with a shine sweep.
///
/// Never interrupts a running set piece: while the AnimationQueue is busy
/// ([animationBusyProvider]) unlocks queue up and surface only once the
/// queue drains. Unlocks are also accumulated per game for the results
/// screen ([unlockedThisGameProvider]).
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';
import '../game/anim/rendered_state.dart';
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

/// The toast currently on screen (null = hidden). New unlocks queue behind
/// the animation queue and each other.
final achievementToastProvider =
    NotifierProvider<AchievementToastController, AchievementUnlocked?>(
        AchievementToastController.new);

class AchievementToastController extends Notifier<AchievementUnlocked?> {
  final Queue<AchievementUnlocked> _pending = Queue();
  Timer? _holdTimer;

  /// Slide-in + shine + hold + slide-out budget for one toast.
  static const displayDuration = Duration(milliseconds: 3100);

  @override
  AchievementUnlocked? build() {
    final room = ref.watch(currentRoomProvider);
    // When the set-piece queue drains, surface anything that was deferred.
    ref.listen(animationBusyProvider, (_, busy) {
      if (!busy) _pump();
    });
    if (room != null) {
      final sub = room.onAchievement.listen((a) {
        _pending.add(a);
        _pump();
      });
      ref.onDispose(sub.cancel);
    }
    ref.onDispose(() {
      _holdTimer?.cancel();
      _holdTimer = null;
    });
    return null;
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
    final toast = ref.watch(achievementToastProvider);
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
                  : _ToastCard(key: ValueKey(toast.key), toast: toast),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.toast});

  final AchievementUnlocked toast;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AnimatedBuilder(
            animation: _shine,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.35),
                  Colors.transparent,
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
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(achievementEmoji(widget.toast.key),
                      style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Strings.achievementUnlockedToast,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: scheme.onPrimaryContainer
                                      .withValues(alpha: 0.7)),
                        ),
                        Text(
                          Strings.achievementTitle(
                              widget.toast.key, widget.toast.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onPrimaryContainer),
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
