/// io branch of the [AdsBackend] factory (mobile, desktop, VM tests).
///
/// Runtime gate: google_mobile_ads only has android/ios implementations, so
/// every other platform gets the no-op backend. NOTE: VM widget tests report
/// `defaultTargetPlatform == android` and DO construct [GoogleAdsBackend];
/// its `init()` probe (catchable MissingPluginException → broken forever) is
/// what keeps tests safe — see `ads_backend_google.dart`.
library;

import 'package:flutter/foundation.dart';

import 'ads_backend.dart';
import 'ads_backend_google.dart';

AdsBackend createBackend() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return GoogleAdsBackend();
  }
  return const NoopAdsBackend();
}
