import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/branches/branches_screen.dart';
import 'core/constants/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/forgot_password_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/bookings/booking_flow_screen.dart';
import 'firebase_options.dart';
import 'features/bookings/my_bookings_screen.dart';
import 'features/occupancy/walk_in_check_in_screen.dart';
import 'features/occupancy/walk_in_check_out_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const OccupierApp());
}

class OccupierApp extends StatefulWidget {
  const OccupierApp({super.key, this.authStateChanges, this.routeBuilders});

  final Stream<String?>? authStateChanges;
  final Map<String, WidgetBuilder>? routeBuilders;

  @override
  State<OccupierApp> createState() => _OccupierAppState();
}

class _OccupierAppState extends State<OccupierApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _AppNavigatorObserver _navigatorObserver = _AppNavigatorObserver(
    (name) => _currentRouteName = name,
  );
  StreamSubscription<String?>? _authSubscription;

  String? _authenticatedUid;
  String? _currentRouteName;
  Object? _authError;
  bool _authResolved = false;

  static const _publicRoutes = {
    AppRoutes.login,
    AppRoutes.register,
    AppRoutes.forgotPassword,
  };

  static const _protectedRoutes = {
    AppRoutes.dashboard,
    AppRoutes.branches,
    AppRoutes.desks,
    AppRoutes.meetingRooms,
    AppRoutes.bookings,
    AppRoutes.occupancy,
    AppRoutes.profile,
    AppRoutes.myBookings,
    AppRoutes.walkInCheckIn,
  };

  @override
  void initState() {
    super.initState();
    _listenForAuthChanges();
  }

  @override
  void didUpdateWidget(covariant OccupierApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authStateChanges != widget.authStateChanges) {
      _listenForAuthChanges();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _listenForAuthChanges() {
    _authSubscription?.cancel();
    _authSubscription =
        (widget.authStateChanges ?? AuthService().authUidChanges).listen(
          _handleAuthState,
          onError: _handleAuthError,
        );
  }

  void _handleAuthState(String? uid) {
    if (!mounted) return;

    final wasAuthenticated = _authenticatedUid != null;
    setState(() {
      _authenticatedUid = uid;
      _authError = null;
      _authResolved = true;
    });

    if (wasAuthenticated &&
        uid == null &&
        _currentRouteName != null &&
        _currentRouteName != AppRoutes.login) {
      _redirectToLogin();
    }
  }

  void _handleAuthError(Object error, StackTrace stackTrace) {
    if (!mounted) return;

    setState(() {
      _authenticatedUid = null;
      _authError = error;
      _authResolved = true;
    });

    if (_currentRouteName != null && _currentRouteName != AppRoutes.login) {
      _redirectToLogin();
    }
  }

  void _redirectToLogin() {
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  }

  void _retryAuthCheck() {
    setState(() {
      _authResolved = false;
      _authError = null;
    });
    _listenForAuthChanges();
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final requestedName = settings.name ?? AppRoutes.login;

    if (_protectedRoutes.contains(requestedName) && _authenticatedUid == null) {
      return _buildRedirectRoute(settings, AppRoutes.login);
    }
    if (_publicRoutes.contains(requestedName) && _authenticatedUid != null) {
      return _buildRedirectRoute(settings, AppRoutes.dashboard);
    }

    final builder = _routeBuilders[requestedName];
    if (builder == null) {
      return MaterialPageRoute<void>(
        settings: RouteSettings(name: requestedName),
        builder: (_) => const PlaceholderScreen(title: 'Page not found'),
      );
    }

    return MaterialPageRoute<void>(
      settings: RouteSettings(
        name: requestedName,
        arguments: settings.arguments,
      ),
      builder: builder,
    );
  }

  Route<dynamic> _buildRedirectRoute(
    RouteSettings settings,
    String destination,
  ) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => _RouteRedirect(
        onRedirect: () {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            destination,
            (route) => false,
          );
        },
      ),
    );
  }

  Map<String, WidgetBuilder> get _routeBuilders => {
    AppRoutes.login: (_) => const LoginScreen(),
    AppRoutes.register: (_) => const RegisterScreen(),
    AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
    AppRoutes.dashboard: (_) => const DashboardScreen(),
    AppRoutes.branches: (_) => BranchesScreen(),
    AppRoutes.desks: (_) => const PlaceholderScreen(title: 'Desks'),
    AppRoutes.meetingRooms: (_) =>
        const PlaceholderScreen(title: 'Meeting Rooms'),
    AppRoutes.bookings: (_) => BookingFlowScreen(),
    AppRoutes.occupancy: (_) => const WalkInCheckOutScreen(),
    AppRoutes.profile: (_) => const ProfileScreen(),
    ...?widget.routeBuilders,
    AppRoutes.myBookings: (_) => const MyBookingsScreen(),
    AppRoutes.walkInCheckIn: (_) => const WalkInCheckInScreen(),
  };

  @override
  Widget build(BuildContext context) {
    if (!_authResolved) {
      return MaterialApp(
        title: 'Occupier',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_authError != null) {
      return MaterialApp(
        title: 'Occupier',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to check your sign-in status.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _retryAuthCheck,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_navigatorObserver],
      title: 'Occupier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: _authenticatedUid == null
          ? AppRoutes.login
          : AppRoutes.dashboard,
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

class _AppNavigatorObserver extends NavigatorObserver {
  _AppNavigatorObserver(this.onRouteChanged);

  final ValueChanged<String?> onRouteChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onRouteChanged(newRoute?.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute?.settings.name);
  }
}

class _RouteRedirect extends StatefulWidget {
  const _RouteRedirect({required this.onRedirect});

  final VoidCallback onRedirect;

  @override
  State<_RouteRedirect> createState() => _RouteRedirectState();
}

class _RouteRedirectState extends State<_RouteRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onRedirect();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
