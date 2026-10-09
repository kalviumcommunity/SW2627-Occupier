
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/constants/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const OccupierApp());
}

class OccupierApp extends StatelessWidget {
  const OccupierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Occupier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: AppRoutes.login,
      routes: {
        AppRoutes.login: (_) => const PlaceholderScreen(title: 'Login'),
        AppRoutes.register: (_) =>
            const PlaceholderScreen(title: 'Register'),
        AppRoutes.forgotPassword: (_) =>
            const PlaceholderScreen(title: 'Forgot Password'),
        AppRoutes.dashboard: (_) =>
            const PlaceholderScreen(title: 'Dashboard'),
        AppRoutes.branches: (_) =>
            const PlaceholderScreen(title: 'Branches'),
        AppRoutes.desks: (_) => const PlaceholderScreen(title: 'Desks'),
        AppRoutes.meetingRooms: (_) =>
            const PlaceholderScreen(title: 'Meeting Rooms'),
        AppRoutes.bookings: (_) =>
            const PlaceholderScreen(title: 'Bookings'),
        AppRoutes.occupancy: (_) =>
            const PlaceholderScreen(title: 'Occupancy'),
        AppRoutes.profile: (_) => const PlaceholderScreen(title: 'Profile'),
      },
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
