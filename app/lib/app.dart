import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/motion/animation_speed.dart';
import 'core/router/app_router.dart';
import 'core/theme/trude_theme.dart';
import 'core/storage/settings_providers.dart';
import 'core/strings.dart';
import 'features/achievements/achievement_toast.dart';
import 'features/game/anim/rendered_state.dart';
import 'l10n/app_localizations.dart';

class TrudeApp extends ConsumerWidget {
  const TrudeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly instantiate the rendered-state notifier. The room's broadcast
    // streams do NOT replay, and the lobby navigates to the table on the TRUE
    // state's phase flip — so the game-start hand snapshot + deal batch are
    // emitted while the lobby is still mounted. Subscribing here (app root)
    // guarantees the animation queue is listening before that navigation, so
    // nothing is lost and the deal still animates on the table.
    ref.listen(renderedGameStateProvider, (previous, next) {});
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildTrudeTheme(),
      routerConfig: ref.watch(appRouterProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Settings override; null follows the system locale.
      locale: ref.watch(localeOverrideProvider),
      // Mirrors platform reduce-motion into the AnimationSpeed provider so
      // every animated duration in the app collapses to zero when asked.
      // StringsSync rebinds the Strings facade to the ambient locale before
      // any screen builds; AchievementToastHost overlays unlock toasts on
      // every screen.
      builder: (context, child) => ReduceMotionSync(
        child: StringsSync(
          child: AchievementToastHost(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
