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
import 'core/services/permission_service.dart';
import 'core/services/user_repository.dart';
import 'models/user.dart';
import 'features/occupancy/walk_in_check_in_screen.dart';
import 'features/occupancy/walk_in_check_out_screen.dart';
import 'features/admin/admin_user_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const OccupierApp());
}

class OccupierApp extends StatefulWidget {
  const OccupierApp({
    super.key,
    this.authStateChanges,
    this.profileChanges,
    this.routeBuilders,
  });

  final Stream<String?>? authStateChanges;
  final Stream<OccupierUser?> Function(String uid)? profileChanges;
  final Map<String, WidgetBuilder>? routeBuilders;

  @override
  State<OccupierApp> createState() => _OccupierAppState();
}

class _OccupierAppState extends State<OccupierApp> {
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static const PermissionService _permissions = PermissionService();
  late final _AppNavigatorObserver _navigatorObserver = _AppNavigatorObserver(
    (name) => _currentRouteName = name,
  );
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<OccupierUser?>? _profileSubscription;

  String? _authenticatedUid;
  UserRole? _role;
  String? _currentRouteName;
  Object? _authError;
  _ProfileStatus _profileStatus = _ProfileStatus.signedOut;
  int _profileGeneration = 0;
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
    AppRoutes.adminUserManagement,
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
    _profileSubscription?.cancel();
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

    if (_authResolved && uid == _authenticatedUid) return;

    final wasAuthenticated = _authenticatedUid != null;
    if (uid != _authenticatedUid) {
      _navigatorKey = GlobalKey<NavigatorState>();
      _currentRouteName = null;
    }
    _profileGeneration++;
    _profileSubscription?.cancel();
    _profileSubscription = null;
    setState(() {
      _authenticatedUid = uid;
      _role = null;
      _profileStatus = uid == null
          ? _ProfileStatus.signedOut
          : _ProfileStatus.loading;
      _authError = null;
      _authResolved = true;
    });

    if (uid != null) {
      _subscribeToProfile(uid, _profileGeneration);
    }

    if (wasAuthenticated && uid == null) {
      _redirectToLogin();
    }
  }

  void _handleAuthError(Object error, StackTrace stackTrace) {
    if (!mounted) return;

    _profileGeneration++;
    _profileSubscription?.cancel();
    _profileSubscription = null;
    setState(() {
      _authenticatedUid = null;
      _role = null;
      _profileStatus = _ProfileStatus.signedOut;
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

  void _subscribeToProfile(String uid, int generation) {
    try {
      final stream =
          widget.profileChanges?.call(uid) ?? UserRepository().watchUser(uid);
      _profileSubscription = stream.listen(
        (profile) => _handleProfile(uid, generation, profile),
        onError: (Object error, StackTrace stackTrace) {
          _handleProfileError(uid, generation, error);
        },
      );
    } catch (error) {
      _handleProfileError(uid, generation, error);
    }
  }

  void _handleProfile(String uid, int generation, OccupierUser? profile) {
    if (!mounted ||
        generation != _profileGeneration ||
        uid != _authenticatedUid) {
      return;
    }

    final previousStatus = _profileStatus;
    final previousRole = _role;
    final isValidProfile = profile != null && profile.uid == uid;
    setState(() {
      _role = isValidProfile ? profile.role : null;
      _profileStatus = profile == null
          ? _ProfileStatus.missing
          : isValidProfile
          ? _ProfileStatus.ready
          : _ProfileStatus.invalid;
    });

    if (previousStatus != _profileStatus || previousRole != _role) {
      _reevaluateCurrentRoute();
    }
  }

  void _handleProfileError(String uid, int generation, Object error) {
    if (!mounted ||
        generation != _profileGeneration ||
        uid != _authenticatedUid) {
      return;
    }

    setState(() {
      _role = null;
      _profileStatus = error is FormatException
          ? _ProfileStatus.invalid
          : _ProfileStatus.failed;
    });
    _reevaluateCurrentRoute();
  }

  void _retryProfileCheck() {
    final uid = _authenticatedUid;
    if (uid == null) return;

    _profileGeneration++;
    _profileSubscription?.cancel();
    setState(() {
      _role = null;
      _profileStatus = _ProfileStatus.loading;
    });
    _subscribeToProfile(uid, _profileGeneration);
  }

  void _reevaluateCurrentRoute() {
    final routeName = _currentRouteName;
    if (routeName == null || !_protectedRoutes.contains(routeName)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentRouteName != routeName) return;
      _navigatorKey.currentState?.pushReplacementNamed(routeName);
    });
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final requestedName = settings.name ?? AppRoutes.login;

    if (_protectedRoutes.contains(requestedName) && _authenticatedUid == null) {
      return _buildRedirectRoute(settings, AppRoutes.login);
    }

    if (_protectedRoutes.contains(requestedName)) {
      if (_profileStatus == _ProfileStatus.loading) {
        return _buildStatusRoute(settings, const _ProfileLoadingScreen());
      }
      if (_profileStatus == _ProfileStatus.failed) {
        return _buildStatusRoute(
          settings,
          _ProfileRetryScreen(onRetry: _retryProfileCheck),
        );
      }
      if (_profileStatus != _ProfileStatus.ready ||
          !_permissions.canAccessRoute(requestedName, _role)) {
        return _buildStatusRoute(settings, const _AccessDeniedScreen());
      }
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

  Route<dynamic> _buildStatusRoute(RouteSettings settings, Widget screen) {
    return MaterialPageRoute<void>(settings: settings, builder: (_) => screen);
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
    AppRoutes.myBookings: (_) => const MyBookingsScreen(),
    AppRoutes.walkInCheckIn: (_) => const WalkInCheckInScreen(),
    AppRoutes.adminUserManagement: (_) => const AdminUserManagementScreen(),
    ...?widget.routeBuilders,
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

    if (_authenticatedUid != null && _profileStatus != _ProfileStatus.ready) {
      final Widget screen = switch (_profileStatus) {
        _ProfileStatus.loading => const _ProfileLoadingScreen(),
        _ProfileStatus.failed => _ProfileRetryScreen(
          onRetry: _retryProfileCheck,
        ),
        _ProfileStatus.missing ||
        _ProfileStatus.invalid => const _AccessDeniedScreen(),
        _ProfileStatus.signedOut ||
        _ProfileStatus.ready => const _ProfileLoadingScreen(),
      };

      return MaterialApp(
        title: 'Occupier',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: screen,
      );
    }

    return MaterialApp(
      key: ValueKey<String?>(_authenticatedUid),
      navigatorKey: _navigatorKey,
      navigatorObservers: [_navigatorObserver],
      title: 'Occupier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final routeName = _currentRouteName;
        final routeIsDenied =
            _authenticatedUid != null &&
            _profileStatus == _ProfileStatus.ready &&
            routeName != null &&
            _protectedRoutes.contains(routeName) &&
            !_permissions.canAccessRoute(routeName, _role);

        if (!routeIsDenied) return child ?? const SizedBox.shrink();

        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: true, child: child),
            const _AccessDeniedScreen(),
          ],
        );
      },
      initialRoute: _authenticatedUid == null
          ? AppRoutes.login
          : AppRoutes.dashboard,
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

enum _ProfileStatus { signedOut, loading, ready, missing, invalid, failed }

class _ProfileLoadingScreen extends StatelessWidget {
  const _ProfileLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ProfileRetryScreen extends StatelessWidget {
  const _ProfileRetryScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unable to load your access profile.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access Denied')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your account profile is missing or does not allow access to this page.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
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
