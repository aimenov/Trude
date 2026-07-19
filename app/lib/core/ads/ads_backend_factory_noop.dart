/// Web (and any non-io) branch of the [AdsBackend] factory: no plugin code
/// is ever linked; ads simply don't exist.
library;

import 'ads_backend.dart';

AdsBackend createBackend() => const NoopAdsBackend();
