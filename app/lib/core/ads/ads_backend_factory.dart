/// Platform-safe [AdsBackend] factory.
///
/// Same conditional-import pattern as `settings_store.dart`: the default
/// branch (web/js) never even references the plugin-backed implementation,
/// so `flutter build web` compiling is the proof this gating is right. The
/// io branch adds a runtime platform gate, and the google backend itself
/// adds a MissingPluginException probe in `init()` (VM widget tests report
/// an android platform — the probe is the real safety).
library;

import 'ads_backend.dart';
import 'ads_backend_factory_noop.dart'
    if (dart.library.io) 'ads_backend_factory_io.dart' as impl;

AdsBackend createAdsBackend() => impl.createBackend();
