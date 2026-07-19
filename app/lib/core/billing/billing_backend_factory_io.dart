/// io branch of the [BillingBackend] factory (mobile, desktop, VM tests).
///
/// Runtime gate: in_app_purchase only supports android/ios(/macos); other
/// platforms get the no-op backend. VM widget tests report android and DO
/// construct [IapBillingBackend]; its `init()` probe is the real safety —
/// see `billing_backend_iap.dart`.
library;

import 'package:flutter/foundation.dart';

import 'billing_backend.dart';
import 'billing_backend_iap.dart';

BillingBackend createBackend() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return IapBillingBackend();
  }
  return const NoopBillingBackend();
}
