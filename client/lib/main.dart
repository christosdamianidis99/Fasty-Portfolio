import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account/account_resources.dart';
import 'app_shell.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_token_store.dart';
import 'auth/email_confirmation_link.dart';
import 'auth/password_reset_link.dart';
import 'auth/signed_out_entry.dart';
import 'config/api_endpoint.dart';
import 'notes/local_notes_repository.dart';
import 'notes/notes_api.dart';
import 'notes/notes_sync_service.dart';
import 'notes/workspace_state_store.dart';
import 'releases/release_announcement_api.dart';
import 'releases/release_announcement_controller.dart';
import 'releases/release_announcement_store.dart';
import 'settings/app_settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appLinks = AppLinks();
  final initialUri = await appLinks.getInitialLink() ?? Uri.base;
  final apiBaseUrl = resolveApiBaseUrl();
  final initialConfirmationLink = EmailConfirmationLink.tryParse(initialUri);
  final initialPasswordResetLink = PasswordResetLink.tryParse(initialUri);

  final authController = AuthController(
    api: AuthApi(baseUrl: apiBaseUrl),
    tokenStore: AuthTokenStore(),
  );

  await authController.initialize();

  final settings = await AppSettingsController.load();

  final releaseAnnouncementController = ReleaseAnnouncementController(
    api: ReleaseAnnouncementApi(baseUrl: apiBaseUrl),
    store: ReleaseAnnouncementStore(),
  );

  runApp(
    FastyLaunchGate(
      child: FastyApp.production(
        apiBaseUrl: apiBaseUrl,
        settings: settings,
        authController: authController,
        releaseAnnouncementController: releaseAnnouncementController,
        initialConfirmationLink: initialConfirmationLink,
        initialPasswordResetLink: initialPasswordResetLink,
        accountLinkStream: appLinks.uriLinkStream,
      ),
    ),
  );
}

class FastyLaunchGate extends StatefulWidget {
  const FastyLaunchGate({super.key, required this.child});

  final Widget child;

  @override
  State<FastyLaunchGate> createState() => _FastyLaunchGateState();
}

class _FastyLaunchGateState extends State<FastyLaunchGate> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) {
      return widget.child;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0877F9),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 320, maxHeight: 320),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(72),
              child: Image(
                image: AssetImage('assets/branding/fasty_logo.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef AccountResourcesFactory =
    AccountResources Function({
      required String email,
      required String apiBaseUrl,
      required AccessTokenProvider accessTokenProvider,
    });

class FastyApp extends StatefulWidget {
  factory FastyApp({
    Key? key,
    required LocalNotesRepository repository,
    required NotesSyncService syncService,
    required WorkspaceStateStore workspaceStore,
    AuthController? authController,
    EmailConfirmationLink? initialConfirmationLink,
    PasswordResetLink? initialPasswordResetLink,
    Stream<Uri>? accountLinkStream,
    AppSettingsController? settings,
  }) {
    return FastyApp._(
      key: key,
      repository: repository,
      syncService: syncService,
      workspaceStore: workspaceStore,
      apiBaseUrl: null,
      managesAccountResources: false,
      accountResourcesFactory: AccountResources.create,
      settings: settings ?? AppSettingsController.ephemeral(),
      authController: authController,
      releaseAnnouncementController: null,
      initialConfirmationLink: initialConfirmationLink,
      initialPasswordResetLink: initialPasswordResetLink,
      accountLinkStream: accountLinkStream,
    );
  }

  factory FastyApp.production({
    Key? key,
    required String apiBaseUrl,
    required AuthController authController,
    EmailConfirmationLink? initialConfirmationLink,
    PasswordResetLink? initialPasswordResetLink,
    Stream<Uri>? accountLinkStream,
    AppSettingsController? settings,
    ReleaseAnnouncementController? releaseAnnouncementController,
    AccountResourcesFactory accountResourcesFactory = AccountResources.create,
  }) {
    return FastyApp._(
      key: key,
      repository: null,
      syncService: null,
      workspaceStore: null,
      apiBaseUrl: apiBaseUrl,
      managesAccountResources: true,
      accountResourcesFactory: accountResourcesFactory,
      settings: settings ?? AppSettingsController.ephemeral(),
      authController: authController,
      releaseAnnouncementController: releaseAnnouncementController,
      initialConfirmationLink: initialConfirmationLink,
      initialPasswordResetLink: initialPasswordResetLink,
      accountLinkStream: accountLinkStream,
    );
  }

  const FastyApp._({
    super.key,
    required this.repository,
    required this.syncService,
    required this.workspaceStore,
    required this.apiBaseUrl,
    required this.managesAccountResources,
    required this.accountResourcesFactory,
    required this.settings,
    required this.authController,
    required this.releaseAnnouncementController,
    required this.initialConfirmationLink,
    required this.initialPasswordResetLink,
    required this.accountLinkStream,
  });

  final LocalNotesRepository? repository;
  final NotesSyncService? syncService;
  final WorkspaceStateStore? workspaceStore;
  final String? apiBaseUrl;
  final bool managesAccountResources;
  final AccountResourcesFactory accountResourcesFactory;
  final AppSettingsController settings;
  final AuthController? authController;
  final ReleaseAnnouncementController? releaseAnnouncementController;
  final EmailConfirmationLink? initialConfirmationLink;
  final PasswordResetLink? initialPasswordResetLink;
  final Stream<Uri>? accountLinkStream;

  @override
  State<FastyApp> createState() => _FastyAppState();
}

class _FastyAppState extends State<FastyApp> {
  late EmailConfirmationLink? _pendingConfirmationLink;
  late PasswordResetLink? _pendingPasswordResetLink;
  StreamSubscription<Uri>? _accountLinkSubscription;

  AccountResources? _accountResources;
  String? _accountResourceEmail;
  Future<void> _resourceTransition = Future<void>.value();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    _pendingConfirmationLink = widget.initialConfirmationLink;
    _pendingPasswordResetLink = widget.initialPasswordResetLink;

    _accountLinkSubscription = widget.accountLinkStream?.listen(
      _handleIncomingAccountLink,
    );

    widget.authController?.addListener(_handleAuthenticationChanged);
    if (widget.managesAccountResources) {
      _createInitialAccountResources();
    }
  }

  @override
  void dispose() {
    _disposed = true;

    widget.authController?.removeListener(_handleAuthenticationChanged);
    _accountLinkSubscription?.cancel();

    widget.releaseAnnouncementController?.close();

    final resources = _accountResources;
    _accountResources = null;
    _accountResourceEmail = null;

    if (resources != null) {
      unawaited(resources.dispose());
    }

    super.dispose();
  }

  String? _desiredAccountEmail() {
    final authController = widget.authController;

    if (authController == null || authController.state != AuthState.signedIn) {
      return null;
    }

    final email = authController.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      return null;
    }

    return email;
  }

  void _createInitialAccountResources() {
    final email = _desiredAccountEmail();

    if (email == null) {
      return;
    }

    _accountResources = widget.accountResourcesFactory(
      email: email,
      apiBaseUrl: widget.apiBaseUrl!,
      accessTokenProvider: ({bool forceRefresh = false}) async {
        if (_desiredAccountEmail() != email) {
          return null;
        }

        return widget.authController!.getValidAccessToken(
          forceRefresh: forceRefresh,
        );
      },
    );
    _accountResourceEmail = email;
  }

  void _handleAuthenticationChanged() {
    if (!widget.managesAccountResources || _disposed) {
      return;
    }

    _resourceTransition = _resourceTransition.then(
      (_) => _synchronizeAccountResources(),
    );
  }

  Future<void> _synchronizeAccountResources() async {
    if (_disposed) {
      return;
    }

    final desiredEmail = _desiredAccountEmail();

    if (desiredEmail != null &&
        desiredEmail == _accountResourceEmail &&
        _accountResources != null) {
      return;
    }

    final previousResources = _accountResources;

    if (previousResources != null || _accountResourceEmail != null) {
      if (mounted) {
        setState(() {
          _accountResources = null;
          _accountResourceEmail = null;
        });
      } else {
        _accountResources = null;
        _accountResourceEmail = null;
      }
    }

    if (previousResources != null) {
      await previousResources.dispose();
    }

    if (_disposed) {
      return;
    }

    final currentEmail = _desiredAccountEmail();

    if (currentEmail == null) {
      return;
    }

    final resources = widget.accountResourcesFactory(
      email: currentEmail,
      apiBaseUrl: widget.apiBaseUrl!,
      accessTokenProvider: ({bool forceRefresh = false}) async {
        if (_desiredAccountEmail() != currentEmail) {
          return null;
        }

        return widget.authController!.getValidAccessToken(
          forceRefresh: forceRefresh,
        );
      },
    );

    if (_disposed) {
      await resources.dispose();
      return;
    }

    if (mounted) {
      setState(() {
        _accountResources = resources;
        _accountResourceEmail = currentEmail;
      });
    } else {
      await resources.dispose();
    }
  }

  void _handleIncomingAccountLink(Uri uri) {
    final confirmationLink = EmailConfirmationLink.tryParse(uri);
    final passwordResetLink = PasswordResetLink.tryParse(uri);

    if (confirmationLink == null && passwordResetLink == null) {
      return;
    }

    setState(() {
      _pendingConfirmationLink = confirmationLink;
      _pendingPasswordResetLink = passwordResetLink;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authController = widget.authController;
    final settings = widget.settings;

    return AnimatedBuilder(
      animation: authController == null
          ? settings
          : Listenable.merge([settings, authController]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Fasty',
          debugShowCheckedModeBanner: false,
          locale: settings.locale,
          supportedLocales: const [Locale('en'), Locale('el')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: settings.themeMode,
          theme: _buildTheme(Brightness.light, settings.seedColor),
          darkTheme: _buildTheme(Brightness.dark, settings.seedColor),
          home: authController == null
              ? _buildInjectedAppShell(settings)
              : switch (authController.state) {
                  AuthState.initializing => const _AuthenticationLoadingPage(),
                  AuthState.signedOut => SignedOutEntry(
                    controller: authController,
                    initialConfirmationLink: _pendingConfirmationLink,
                    initialPasswordResetLink: _pendingPasswordResetLink,
                    onConfirmationLinkPresented: () {
                      _pendingConfirmationLink = null;
                    },
                    onPasswordResetLinkPresented: () {
                      _pendingPasswordResetLink = null;
                    },
                  ),
                  AuthState.signedIn => _buildSignedInContent(
                    settings,
                    authController,
                  ),
                },
        );
      },
    );
  }

  Widget _buildInjectedAppShell(AppSettingsController settings) {
    return FastyAppShell(
      repository: widget.repository!,
      syncService: widget.syncService!,
      workspaceStore: widget.workspaceStore!,
      settings: settings,
    );
  }

  Widget _buildSignedInContent(
    AppSettingsController settings,
    AuthController authController,
  ) {
    if (!widget.managesAccountResources) {
      return FastyAppShell(
        repository: widget.repository!,
        syncService: widget.syncService!,
        workspaceStore: widget.workspaceStore!,
        settings: settings,
        authController: authController,
      );
    }

    final resources = _accountResources;

    if (resources == null) {
      return const _AuthenticationLoadingPage();
    }

    return FastyAppShell(
      key: ValueKey('account-${_accountResourceEmail!}'),
      repository: resources.repository,
      syncService: resources.syncService,
      workspaceStore: resources.workspaceStore,
      settings: settings,
      authController: authController,
      releaseAnnouncementController: widget.releaseAnnouncementController,
    );
  }

  ThemeData _buildTheme(Brightness brightness, Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surfaceContainerLowest,
        foregroundColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }
}

class _AuthenticationLoadingPage extends StatelessWidget {
  const _AuthenticationLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
