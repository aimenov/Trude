/// AdMob configuration: ad-unit / app ids and server token kinds.
///
/// ALL ids below are Google's public TEST ids — safe to load anywhere, never
/// generate revenue, never risk account flags during development.
///
/// TODO(release): replace every id in this file with real AdMob ids (and the
/// mirrored ids in android/app/src/main/AndroidManifest.xml +
/// ios/Runner/Info.plist) before any store build.
library;

abstract final class AdConfig {
  // -- App ids (must match the platform manifests) ---------------------------

  /// TODO(release): real Android AdMob app id.
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// TODO(release): real iOS AdMob app id.
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  // -- Rewarded (the only format v1 actually shows) --------------------------

  /// TODO(release): real Android rewarded ad-unit id.
  static const androidRewardedUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// TODO(release): real iOS rewarded ad-unit id.
  static const iosRewardedUnitId = 'ca-app-pub-3940256099942544/1712485313';

  // -- Interstitial (reserved slot; UNUSED in v1 — premium's "no future
  // interstitials" pitch depends on us never wiring these without checking
  // the premium flag) --------------------------------------------------------

  /// TODO(release): real Android interstitial ad-unit id (unused in v1).
  static const androidInterstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  /// TODO(release): real iOS interstitial ad-unit id (unused in v1).
  static const iosInterstitialUnitId =
      'ca-app-pub-3940256099942544/4411468910';

  // -- Server ad-token kinds (GET /ads/token?kind=...) -----------------------

  /// Shop "+25 coins" placement (server cap 5/day).
  static const kindShop = 'shop';

  /// Results "double your winnings" placement (server cap 10/day).
  static const kindDouble = 'double';
}
