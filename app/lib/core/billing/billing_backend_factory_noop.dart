/// Web (and any non-io) branch of the [BillingBackend] factory: no plugin
/// code is ever linked; the store shelves stay hidden.
library;

import 'billing_backend.dart';

BillingBackend createBackend() => const NoopBillingBackend();
