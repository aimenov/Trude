import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achievements/achievements_screen.dart';
import '../../features/game/table_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/lobby/lobby_screen.dart';
import '../../features/nickname/nickname_screen.dart';
import '../../features/results/results_screen.dart';
import '../../features/rooms/open_rooms_screen.dart';
import '../../features/shop/shop_screen.dart';
import '../net/connection_providers.dart';
import '../storage/identity_providers.dart';

const _roomRoutes = {'/lobby', '/table', '/results'};

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (ref.read(identityProvider) == null && location != '/nickname') {
        return '/nickname';
      }
      // Room screens make no sense without a joined room (e.g. hot restart).
      if (_roomRoutes.contains(location) &&
          ref.read(currentRoomProvider) == null) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/nickname', builder: (_, _) => const NicknameScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/achievements',
          builder: (_, _) => const AchievementsScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/leaderboard',
          builder: (_, _) => const LeaderboardScreen()),
      GoRoute(path: '/shop', builder: (_, _) => const ShopScreen()),
      GoRoute(path: '/rooms', builder: (_, _) => const OpenRoomsScreen()),
      GoRoute(path: '/lobby', builder: (_, _) => const LobbyScreen()),
      GoRoute(path: '/table', builder: (_, _) => const TableScreen()),
      GoRoute(path: '/results', builder: (_, _) => const ResultsScreen()),
    ],
  );
});
