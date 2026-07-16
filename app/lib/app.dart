import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/motion/animation_speed.dart';
import 'core/router/app_router.dart';
import 'core/storage/settings_providers.dart';
import 'core/strings.dart';
import 'features/achievements/achievement_toast.dart';
import 'l10n/app_localizations.dart';

class TrudeApp extends ConsumerWidget {
  const TrudeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
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
