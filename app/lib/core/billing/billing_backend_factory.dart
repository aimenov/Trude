/// Platform-safe [BillingBackend] factory.
///
/// Same conditional-import + runtime-gate + init-probe triple as
/// `ads_backend_factory.dart` (pattern origin: `settings_store.dart`).
/// `flutter build web` compiling is the proof the gating is right.
library;

import 'billing_backend.dart';
import 'billing_backend_factory_noop.dart'
    if (dart.library.io) 'billing_backend_factory_io.dart' as impl;

BillingBackend createBillingBackend() => impl.createBackend();
