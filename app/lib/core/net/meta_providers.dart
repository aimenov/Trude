/// Providers for the meta HTTP endpoints: profile + lifetime stats and the
/// achievements catalog. Both ensure the guest session (Bearer token) first.
///
/// Invalidate to refresh: `ref.invalidate(meProvider)` on focus,
/// `ref.refresh(achievementsProvider.future)` from pull-to-refresh.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_providers.dart';

final meProvider = FutureProvider<MeProfile>((ref) async {
  // ensure() may log in (writing session/identity providers); leave this
  // provider's synchronous build window first.
  await null;
  await ref.read(sessionProvider.notifier).ensure();
  return ref.read(trudeClientProvider).getMe();
});

final achievementsProvider = FutureProvider<MeAchievements>((ref) async {
  await null;
  await ref.read(sessionProvider.notifier).ensure();
  return ref.read(trudeClientProvider).getAchievements();
});
