import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:meta_seo/meta_seo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'config/theme.dart';
import 'providers/auth_providers.dart';
import 'providers/connectivity_provider.dart';
import 'providers/ml_analytics_provider.dart';
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'services/connectivity_service.dart';
import 'utils/env_helper.dart';
import 'utils/error_sanitizer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file if it exists (local development)
  // On deployed apps, env vars come from --dart-define-from-file at compile time
  try {
    await dotenv.load(fileName: ".env");
    EnvHelper.markDotenvInitialized();
  } catch (_) {
    // .env file doesn't exist in production, that's okay
    // Variables are provided via --dart-define at compile time
  }

  // Get Google client ID
  final googleClientId = EnvHelper.get('GOOGLE_WEB_CLIENT');
  if (googleClientId != null && googleClientId.isNotEmpty) {
    GoogleSignIn.instance.initialize(clientId: googleClientId);
  }

  _setupErrorHandling();

  if (kIsWeb) {
    MetaSEO().config();
  }

  await SupabaseConfig().initialize();

  await ConnectivityService().initialize();

  initRouter();

  runApp(const ProviderScope(child: MyApp()));
}

void _setupErrorHandling() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: ErrorSanitizer.getUserFriendlyMessage(details.exception),
        stack: details.stack,
        library: details.library,
        context: details.context,
        stackFilter: details.stackFilter,
        informationCollector: details.informationCollector,
        silent: details.silent,
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Error: ${ErrorSanitizer.getUserFriendlyMessage(error)}');
    return true;
  };
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _initialRouteHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAuthListener();
      // Pre-warm the ML backend (free tier may be sleeping)
      // This runs async in background, no blocking
      ref.read(mlWarmUpProvider);
    });
  }

  void _setupAuthListener() {
    // Listen to auth state changes (handles OAuth redirect callback)
    ref.listenManual(authStateProvider, (previous, next) {
      next.whenData((user) {
        if (!_initialRouteHandled) {
          _initialRouteHandled = true;
          _handleAuthStateChange(user);
        }
      });
    });

    // Also check immediately in case auth is already resolved
    final currentAuthState = ref.read(authStateProvider);
    currentAuthState.whenData((user) {
      if (!_initialRouteHandled) {
        _initialRouteHandled = true;
        _handleAuthStateChange(user);
      }
    });
  }

  Future<void> _handleAuthStateChange(User? user) async {
    if (user != null) {
      // User is authenticated - check if they have farms
      final authRepository = ref.read(authRepositoryProvider);
      final appUser = await authRepository.getAppUser(user.id);

      if (appUser != null && appUser.farms.isEmpty) {
        // New user without farms - need onboarding
        // Check for pending invites for their email
        final pendingInvites = await authRepository.getPendingInvitesForEmail(
          user.email ?? '',
        );

        if (pendingInvites.isNotEmpty) {
          // User has pending invites - go to register with invite flow
          coordinator.replace(RegisterRoute(hasInviteCode: true));
        } else {
          // No invites - go to dashboard with create farm dialog
          coordinator.replace(DashboardRoute(showCreateFarmDialog: true));
        }
      } else {
        // Existing user with farms - go to dashboard
        coordinator.replace(DashboardRoute());
      }
    } else {
      // Not authenticated
      if (kIsWeb) {
        coordinator.replace(LandingRoute());
      } else {
        coordinator.replace(LoginRoute());
      }
    }
  }

  Future<void> _retryConnection() async {
    final isConnected = await ConnectivityService().checkConnection();
    if (isConnected) {
      ref.invalidate(connectivityStreamProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final connectivityAsync = ref.watch(connectivityStreamProvider);

    return MaterialApp.router(
      title: 'Farm Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      restorationScopeId: 'manage',
      routerDelegate: coordinator.routerDelegate,
      routeInformationParser: coordinator.routeInformationParser,
      builder: (context, child) {
        return connectivityAsync.when(
          data: (isConnected) {
            if (!isConnected) {
              return _NoInternetView(onRetry: _retryConnection);
            }
            return child ?? const SizedBox.shrink();
          },
          loading: () => child ?? const SizedBox.shrink(),
          error: (_, _) => child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class _NoInternetView extends StatelessWidget {
  final VoidCallback? onRetry;

  const _NoInternetView({this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: 64,
                      color: colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'No Internet Connection',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Please check your internet connection and try again.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
