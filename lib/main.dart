import 'services/user_private_data.dart';
import 'dart:async';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'theme/colors.dart';
import 'screens/construction_page.dart';
import 'screens/landing/landing_page.dart';
import 'screens/home_page.dart';
import 'screens/login/desktop_login_page.dart';
import 'screens/login/mobile_login_page.dart';
import 'screens/login/mobile_welcome_page.dart';
import 'screens/login/forgot_password_page.dart';
import 'screens/login/auth_action_page.dart';
import 'screens/register/desktop_register_page.dart';
import 'screens/register/mobile_register_page.dart';
import 'screens/account/account_management_page.dart';
import 'screens/trips/trip_viewer_page.dart';
import 'screens/trips/trip_sample.dart';
import 'screens/error_404_page.dart';
import 'screens/lab/lab_landing_page.dart' deferred as lab_landing;
import 'labs/labs_app_page.dart' deferred as labs_app;
import 'labs/lab_experiments.dart';
import 'labs/lab_eval_page.dart' deferred as lab_eval;
import 'labs/labs_results_page.dart' deferred as labs_results;
import 'labs/lab_access.dart';
import 'config/admin.dart' show isSuperUser;
import 'screens/api/api_landing_page.dart' deferred as api_landing;
import 'widgets/deferred_view.dart';
import 'screens/legal/legal_center_page.dart';
import 'screens/legal/legal_content.dart';
import 'screens/onboarding/onboarding_wizard_page.dart';
import 'screens/places/places_page.dart';
import 'widgets/user_profile_helper.dart';
import 'services/ohtli_sso.dart';
import 'services/app_route.dart';
import 'services/app_url.dart';
import 'services/saved_accounts.dart';
import 'screens/login/sso_bridge_page.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // SSO entre subdominios: toma el código #ohtli_sso=… antes de que el enrutador lea la URL.
  OhtliSso.captureFromUrl();
  // URLs sin "#" (ohtli.quest/lugares). La URL de arranque se guarda antes de que el
  // enrutador reescriba el historial (los enlaces antiguos traen la ruta en el fragmento).
  AppUrl.launchUri = Uri.base;
  usePathUrlStrategy();
  // Sigue en vivo el modo claro/oscuro del sistema cuando el tema está en "Sistema"
  OhtliSettings.instance.attachToSystem();

  const configApiKey = String.fromEnvironment('apiKey');
  const configAuthDomain = String.fromEnvironment('authDomain');
  const configProjectId = String.fromEnvironment('projectId');
  const configStorageBucket = String.fromEnvironment('storageBucket');
  const configMessagingSenderId = String.fromEnvironment('messagingSenderId');
  const configAppId = String.fromEnvironment('appId');
  const configMeasurementId = String.fromEnvironment('measurementId');

  FirebaseOptions options;
  if (configApiKey.isNotEmpty) {
    options = FirebaseOptions(
      apiKey: configApiKey,
      authDomain: configAuthDomain,
      projectId: configProjectId,
      storageBucket: configStorageBucket,
      messagingSenderId: configMessagingSenderId,
      appId: configAppId,
      measurementId: configMeasurementId,
    );
  } else {
    options = DefaultFirebaseOptions.currentPlatform;
  }

  try {
    await Firebase.initializeApp(options: options);
    
    // Initialize Firebase App Check to prevent overcost and abuse
    const configRecaptchaKey = String.fromEnvironment('recaptchaSiteKey');
    final String recaptchaKey = configRecaptchaKey.isNotEmpty 
        ? configRecaptchaKey 
        : '6LdFakeKeyForOhtliLocalDevelopment';

    try {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider(recaptchaKey),
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    } catch (appCheckError) {
      print("Firebase App Check initialization error: $appCheckError");
    }

    // Enable Firestore offline persistence for Web — queues writes when offline
    // and syncs automatically when connectivity returns
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      print("Firestore persistence already enabled or not supported: $e");
    }

    // Ensure default Firebase Auth persistence on Web is LOCAL (IndexedDB)
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (e) {
        print("Firebase Auth persistence initialization error: $e");
      }
    }
  } catch (e) {
    print("Firebase initialization error: $e");
  }
  runApp(const OhtliApp());
  // Precarga el catálogo de Lugares (y despierta la API si estaba inactiva) cuando la primera
  // pantalla ya se dibujó: no compite con la descarga inicial. Lugares y Explorar lo piden
  // antes si lo necesitan.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => Future.delayed(const Duration(seconds: 2), PlacesPage.prefetch),
  );
}

class OhtliApp extends StatelessWidget {
  const OhtliApp({super.key});

  static final OhtliRouterDelegate _routerDelegate = OhtliRouterDelegate(const MainNavigationController());
  static final OhtliRouteParser _routeParser = OhtliRouteParser();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OhtliSettings.instance,
      builder: (context, _) {
        final settings = OhtliSettings.instance;

        final lightTheme = ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          scaffoldBackgroundColor: OhtliColors.cloudDancer,
          colorScheme: ColorScheme.fromSeed(
            brightness: Brightness.light,
            seedColor: OhtliColors.stormyTeal,
            primary: OhtliColors.stormyTeal,
            error: OhtliColors.xoconostle,
            surface: OhtliColors.cloudDancer,
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        );

        final darkTheme = ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF121214),
          colorScheme: ColorScheme.fromSeed(
            brightness: Brightness.dark,
            seedColor: OhtliColors.stormyTeal,
            primary: OhtliColors.stormyTeal,
            error: OhtliColors.xoconostle,
            surface: const Color(0xFF1E1E22),
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        );

        ThemeMode flutterThemeMode;
        switch (settings.themeMode) {
          case OhtliThemeMode.light:
            flutterThemeMode = ThemeMode.light;
            break;
          case OhtliThemeMode.dark:
            flutterThemeMode = ThemeMode.dark;
            break;
          case OhtliThemeMode.system:
            flutterThemeMode = ThemeMode.system;
            break;
        }

        return MaterialApp.router(
          routerDelegate: _routerDelegate,
          routeInformationParser: _routeParser,
          title: appTitleForHost(kIsWeb ? web.window.location.hostname : ''),
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: flutterThemeMode,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.textScaleFactor),
                // Brillo efectivo (tema elegido o el del sistema): al cambiarlo se redibujan
                // las pantallas, que leen sus colores de OhtliColors
                platformBrightness: settings.isDarkMode ? Brightness.dark : Brightness.light,
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}

// Enumeración para controlar la navegación fluida de Ohtli
enum OhtliScreen {
  underConstruction,
  ssoBridge, // ohtli.quest/sso: entrega la sesión a un subdominio (lab.ohtli.quest)
  login, // Pantalla unificada (maneja split en desktop y welcome/login en móvil)
  mobileWelcome, // Pantalla oscura de bienvenida exclusiva móvil
  mobileLogin, // Formulario claro exclusivo móvil
  register, // Formulario de registro en Desktop (split screen)
  mobileRegister, // Formulario de registro en Móvil
  forgotPassword, // Pantalla de recuperación de contraseña
  home, // Pantalla principal tras autenticación exitosa
  authAction, // Pantalla de acción de autenticación (recuperación/verificación)
  accountManagement, // Pantalla independiente de gestión de cuenta
  publicViewer, // Visor de viajes públicos / compartidos
  test404, // Temporal para visualizar el 404
  labLanding, // Landing Page para lab.ohtli.quest
  apiLanding, // Landing Page para api.ohtli.quest
  termsAndConditions, // Pantalla de TyC de Ohtli
  labsTermsAndConditions, // Pantalla de TyC de Ohtli Labs
  labApp, // Ohtli Labs con sesión: una sola interfaz con menú (participa, experimentos, pruebas del TT, publicación)
  labEval, // lab.ohtli.quest/eval: entrada pública para testers
  labsResults, // labs.ohtli.quest: reporte y tablero de resultados públicos
  labsNews, // labs.ohtli.quest/news: novedades publicadas
  places, // Vista del catálogo de lugares indexados por el Agente Recolector
  onboarding, // Flujo de Onboarding para recolectar gustos del turista
}

class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});

  @override
  State<MainNavigationController> createState() =>
      _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  OhtliScreen _currentScreen = OhtliScreen.underConstruction;
  late StreamSubscription<User?> _authSubscription;
  String _oobCode = '';
  String _authMode = '';
  String _publicTripId = '';
  LegalDocId _legalDoc = LegalDocId.terms;
  String _publicAuthorId = '';
  int _homeInitialIndex = 0;
  // Pantalla pedida en la URL (p. ej. /mis-viajes) que se abre al confirmar la sesión
  int? _pendingHomeIndex;
  bool _pendingAccount = false;
  // La siguiente actualización de la URL reemplaza la entrada (redirecciones automáticas)
  bool _replaceNextUrl = true;
  bool _lastIsMobile = false;
  bool _isAuthInitialized = false;
  bool _intentLabs = false;
  bool _isLabAppHost = false;
  // SSO: destino validado de ohtli.quest/sso?return=… y control del primer arranque.
  Uri? _ssoTarget;
  bool _ssoChecked = false;
  bool _hadUser = false;
  bool _switchChecked = false;
  bool _intentEval = false;
  OhtliScreen? _labsTermsReturn; // a dónde vuelve "Volver" de los TyC de Labs
  String? _labSection; // sección inicial de Labs (p. ej. exp:osrm desde /labs/osrm)
  String? _newsSlug;

  bool _isOnline = true;
  bool _showBanner = false;
  bool _bannerColorIsTeal = false;
  String _bannerText = '';
  StreamSubscription? _onlineSub;
  StreamSubscription? _offlineSub;

  void _showTemporaryBanner(String text) {
    if (!mounted) return;
    setState(() {
      _showBanner = true;
      _bannerColorIsTeal = false;
      _bannerText = text;
    });
    Future.delayed(const Duration(seconds: 7), () {
      if (mounted && _bannerText == text) setState(() => _showBanner = false);
    });
  }

  void _onConnectionChanged(bool online) {
    setState(() {
      _isOnline = online;
      if (!online) {
        _showBanner = true;
        _bannerColorIsTeal = false;
        _bannerText =
            "Sin conexión, algunos datos podrían no guardarse o estar desactualizados";
      } else {
        _bannerColorIsTeal = true;
        _bannerText = "Recuperaste la conexión";
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) {
            setState(() {
              _showBanner = false;
            });
          }
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();

    // Check for Firebase Auth Action parameters in URL on startup
    final launch = AppUrl.launchUri;
    final params = launch.queryParameters;
    // Routing de Subdominios
    if (kIsWeb) {
      final hostname = web.window.location.hostname;
      final path = launch.path;
      final fragment = launch.fragment;
      // Por segmentos completos: /news/evaluacion-… no debe abrir /eval (ver app_route.dart).
      bool hasRoute(String r) => routeMatches(r, path: path, fragment: fragment);
      final isLabsTyc = hasRoute('/labs/tyc');
      // /labs/<experimento>: abre ese experimento dentro de Labs (con sesión).
      String? experimentRoute = hasRoute('/labs/vibe') ? 'taste' : null;
      for (final e in kLabExperiments) {
        if (hasRoute(e.path)) experimentRoute = e.id;
      }
      final isPlaces = hasRoute('/lugares') || hasRoute('/places') || params.containsKey('lugares') || params.containsKey('places');
      final isAppTyc = hasRoute('/tyc');
      final legalRoute = hasRoute('/privacidad')
          ? LegalDocId.privacy
          : hasRoute('/cookies')
              ? LegalDocId.cookies
              : hasRoute('/terminos-api')
                  ? LegalDocId.api
                  : null;

      if (isLabsTyc) {
        _currentScreen = OhtliScreen.labsTermsAndConditions;
      } else if (experimentRoute != null) {
        _labSection = 'exp:$experimentRoute';
        _currentScreen = OhtliScreen.labApp;
        // En lab.ohtli.quest la sesión llega por SSO como en el resto del laboratorio.
        if (hostname == 'lab.ohtli.quest' || params.containsKey('testLabApp')) _isLabAppHost = true;
      } else if (legalRoute != null) {
        _legalDoc = legalRoute;
        _currentScreen = OhtliScreen.termsAndConditions;
      } else if (isPlaces) {
        _currentScreen = OhtliScreen.places;
        _pendingHomeIndex = 5; // con sesión abre la pestaña Lugares
      } else if ((hostname == 'lab.ohtli.quest' || hostname == 'labs.ohtli.quest' || params.containsKey('testLabApp') ||
              params.containsKey('testLab') || params.containsKey('testEval')) &&
          (hasRoute('/eval') || params.containsKey('testEval'))) {
        // /eval: entrada pública para testers de los estudios de Labs (no exige sesión para leerla)
        _currentScreen = OhtliScreen.labEval;
      } else if ((hostname == 'labs.ohtli.quest' || params.containsKey('testLab')) &&
          (hasRoute('/resultados') || hasRoute('/news'))) {
        // labs.ohtli.quest/resultados: reporte tipo paper y tablero; /news: novedades publicadas
        _currentScreen = hasRoute('/news') ? OhtliScreen.labsNews : OhtliScreen.labsResults;
        _newsSlug = newsSlugFrom(path: path, fragment: fragment);
      } else if (hostname == 'lab.ohtli.quest' || params.containsKey('testLabApp')) {
        // lab.ohtli.quest: laboratorio individual. Sin sesión pide iniciarla y luego abre el panel de Labs
        // (la consola de pruebas del TT si la sesión es del superusuario)
        _isLabAppHost = true;
        if (isAppTyc) {
          _currentScreen = OhtliScreen.labsTermsAndConditions;
        } else {
          _intentLabs = true;
          _currentScreen = OhtliScreen.login;
        }
      } else if (hostname.contains('labs.ohtli.quest') || params.containsKey('testLab')) {
        // labs.ohtli.quest: landing pública de Labs
        if (isAppTyc) {
          _currentScreen = OhtliScreen.labsTermsAndConditions;
        } else {
          _currentScreen = OhtliScreen.labLanding;
        }
      } else if (hostname.contains('api.ohtli.quest') || params.containsKey('testApi')) {
        _currentScreen = OhtliScreen.apiLanding;
      } else if (isAppTyc) {
        _currentScreen = OhtliScreen.termsAndConditions;
      }
    }

    // ohtli.quest/sso?return=https://<sub>.ohtli.quest/…: con sesión entrega la cuenta al
    // subdominio; sin sesión, primero pide iniciarla.
    if (kIsWeb && OhtliSso.isMainHost && launch.path.startsWith('/sso')) {
      _ssoTarget = OhtliSso.parseReturnTarget(params['return']);
      if (_ssoTarget != null) _currentScreen = OhtliScreen.login;
    }

    if (_currentScreen == OhtliScreen.underConstruction) {
      // Si no fue capturado por subdominios, validamos los parámetros de la URL principal
      if (params.containsKey('mode') && params.containsKey('oobCode')) {
        _authMode = params['mode']!;
        _oobCode = params['oobCode']!;
        _currentScreen = OhtliScreen.authAction;
      } else if (params.containsKey('muestra') || launch.path == '/muestra' || launch.path == '/muestra/' || launch.fragment == '/muestra') {
        // Viaje de muestra con todos los elementos (no lee ni escribe datos reales).
        _publicTripId = kSampleTripId;
        _publicAuthorId = kSampleOwnerId;
        _currentScreen = OhtliScreen.publicViewer;
      } else if (params.containsKey('tripId') && params.containsKey('authorId')) {
        _publicTripId = params['tripId']!;
        _publicAuthorId = params['authorId']!;
        _currentScreen = OhtliScreen.publicViewer;
      } else if (params.containsKey('test404')) {
        _currentScreen = OhtliScreen.test404;
      } else if (AppUrl.enabled) {
        _applyLaunchPath(launch.path);
      }
    }
    AppUrl.instance.onExternal = _onExternalUrl;

    // Initialize connection status
    if (kIsWeb) {
      _isOnline = web.window.navigator.onLine;
      if (!_isOnline) {
        _showBanner = true;
        _bannerColorIsTeal = false;
        _bannerText =
            "Sin conexión, algunos datos podrían no guardarse o estar desactualizados";
      }
      _onlineSub = web.EventStreamProviders.onlineEvent.forTarget(web.window).listen(
        (_) => _onConnectionChanged(true),
      );
      _offlineSub = web.EventStreamProviders.offlineEvent.forTarget(web.window).listen(
        (_) => _onConnectionChanged(false),
      );
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) async {
      // SSO en el subdominio (lab.ohtli.quest): sin sesión propia, canjea el código que
      // trajo de ohtli.quest o va por él. Mientras tanto se mantiene la pantalla de carga.
      // /eval también queda protegida por el SSO: sin sesión trae la de ohtli.quest
      // En cualquier subdominio se canjea el código que vuelve de ohtli.quest; la
      // redirección automática es solo para lab (api y labs son páginas públicas).
      if (user == null && !_ssoChecked && OhtliSso.isSubdomain) {
        _ssoChecked = true;
        if (OhtliSso.hasPendingCode) {
          if (await OhtliSso.redeemPendingCode()) return; // llegará otro evento con la sesión
        } else if ((_isLabAppHost || _currentScreen == OhtliScreen.labEval) && OhtliSso.maybeAutoRedirect()) {
          return; // la página está yendo a ohtli.quest
        }
      }
      // Tras cambiar de cuenta desde el menú: confirma que la cuenta elegida entró.
      if (!_switchChecked) {
        _switchChecked = true;
        final failed = SavedAccounts.checkPendingSwitch(user);
        if (failed != null) _showTemporaryBanner('La sesión de $failed ya no es válida. Inicia sesión de nuevo con esa cuenta.');
      }
      // Mantiene al día la sesión guardada de la cuenta actual si está recordada.
      if (user != null) unawaited(SavedAccounts.syncCurrent(user));
      if (user == null && _hadUser) OhtliSso.onSignedOutOnSubdomain();
      if (user != null) {
        _hadUser = true;
        OhtliSso.onSignedInOnSubdomain();
      }

      if (mounted && !_isAuthInitialized) {
        setState(() {
          _isAuthInitialized = true;
        });
      }

      if (user != null) {
        await _handlePostAuthRedirect(user);
      } else {
        // Al cerrar sesión la pantalla ya cambió antes de que terminara: actualizar la URL
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncUrl());
        WidgetsBinding.instance.scheduleFrame();
        // Sin sesión, un enlace a una pantalla privada (/mis-viajes, /cuenta…) pide iniciarla;
        // al entrar se abre esa pantalla. /lugares es pública y se queda como está.
        if (_currentScreen == OhtliScreen.underConstruction &&
            (_pendingAccount || (_pendingHomeIndex != null && _pendingHomeIndex != 5))) {
          _replaceNextUrl = true;
          _navigateTo(_loginScreen);
        }
        if (_currentScreen == OhtliScreen.labApp) {
          // Labs pide sesión: se inicia y se vuelve a la misma sección.
          _intentLabs = true;
          _navigateTo(OhtliScreen.login);
        } else if (_currentScreen == OhtliScreen.home ||
            _currentScreen == OhtliScreen.accountManagement) {
          _navigateTo(OhtliScreen.underConstruction);
        }
      }
    });
  }

  void _onAuthSuccess() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _handlePostAuthRedirect(user);
    } else {
      _navigateTo(OhtliScreen.home);
    }
  }

  Future<void> _handlePostAuthRedirect(User user) async {
    if (_ssoTarget != null) {
      _navigateTo(OhtliScreen.ssoBridge);
      return;
    }
    // 1. Sincronizar perfil en segundo plano sin bloquear la experiencia de navegación del usuario
    if (_currentScreen != OhtliScreen.labLanding && _currentScreen != OhtliScreen.apiLanding) {
      unawaited(UserProfileHelper.syncAndRestoreProfile(user).catchError((e) {
        print("Error syncing profile in background: $e");
      }));
    }

    if (_intentEval) {
      _intentEval = false;
      _navigateTo(OhtliScreen.labEval);
      return;
    }
    if (_intentLabs) {
      // Tras "Ingresar a Labs": el Labs unificado (miembros arrancan en las pruebas del TT; el resto,
      // en Participa). La landing pública se queda donde está aunque haya sesión.
      _intentLabs = false;
      _navigateTo(OhtliScreen.labApp);
      return;
    }

    // Pantallas donde la sesión autenticada se mantiene sin forzar redirección
    if (_currentScreen == OhtliScreen.home ||
        _currentScreen == OhtliScreen.authAction ||
        _currentScreen == OhtliScreen.accountManagement ||
        _currentScreen == OhtliScreen.publicViewer ||
        _currentScreen == OhtliScreen.labApp ||
        _currentScreen == OhtliScreen.labLanding ||
        _currentScreen == OhtliScreen.apiLanding ||
        _currentScreen == OhtliScreen.termsAndConditions ||
        _currentScreen == OhtliScreen.labsTermsAndConditions ||
        _currentScreen == OhtliScreen.labEval ||
        _currentScreen == OhtliScreen.labsResults ||
        _currentScreen == OhtliScreen.labsNews ||
        _currentScreen == OhtliScreen.onboarding) {
      return;
    }

    // 2. Verificar si el usuario ya completó el onboarding con timeout para evitar bloqueos
    try {
      // Perfil público + privado (el perfil de gustos vive en users/{uid}/private/account)
      final Map<String, dynamic>? userData = await UserPrivateData.get(user.uid)
          .timeout(const Duration(seconds: 4))
          .then((d) => d.isEmpty ? null : d);
      final rawVector = userData != null ? userData['taste_vector'] : null;
      bool hasTasteVector = rawVector is List && rawVector.isNotEmpty;
      final bool flagDone = userData != null && (userData['onboarding_completed'] == true);

      // Si completó el wizard antes pero taste_vector quedó en null, sintetizarlo en background
      if (flagDone && !hasTasteVector && userData['cultural_profile'] is Map) {
        unawaited(OnboardingWizardPage.synthesizeAndSaveProfile(
          user.uid,
          Map<String, dynamic>.from(userData['cultural_profile'] as Map),
        ).catchError((backfillErr) {
          print("Error backfilling taste_vector: $backfillErr");
          return <double>[];
        }));
      }

      if (!flagDone) {
        _replaceNextUrl = true;
        _navigateTo(OhtliScreen.onboarding);
      } else {
        _goHomeAfterAuth();
      }
    } catch (e) {
      print("Error or timeout checking onboarding status: $e");
      _goHomeAfterAuth();
    }
  }

  /// Tras confirmar la sesión: la pantalla que pedía la URL (/mis-viajes, /cuenta…) o Explorar.
  void _goHomeAfterAuth() {
    setState(() {
      _replaceNextUrl = true;
      if (_pendingAccount) {
        _currentScreen = OhtliScreen.accountManagement;
      } else {
        _homeInitialIndex = _pendingHomeIndex ?? _homeInitialIndex;
        _currentScreen = OhtliScreen.home;
      }
      _pendingAccount = false;
      _pendingHomeIndex = null;
    });
  }

  // ───────────────────────── URL del navegador ─────────────────────────

  static String? _legalPath(LegalDocId doc) => switch (doc) {
        LegalDocId.terms => '/tyc',
        LegalDocId.privacy => '/privacidad',
        LegalDocId.cookies => '/cookies',
        LegalDocId.api => '/terminos-api',
        LegalDocId.labs => null,
      };

  OhtliScreen get _loginScreen => _lastIsMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login;
  OhtliScreen get _registerScreen => _lastIsMobile ? OhtliScreen.mobileRegister : OhtliScreen.register;

  /// Ruta de las pantallas del sitio principal que se abren por URL (al arrancar).
  void _applyLaunchPath(String rawPath) {
    final path = AppUrl.normalize(rawPath);
    final tab = AppUrl.homeTabForPath(path);
    if (tab != null) {
      _pendingHomeIndex = tab;
    } else if (path == '/cuenta') {
      _pendingAccount = true;
    } else if (path == '/entrar') {
      _currentScreen = OhtliScreen.login;
    } else if (path == '/registro') {
      _currentScreen = OhtliScreen.register;
    } else if (path == '/recuperar') {
      _currentScreen = OhtliScreen.forgotPassword;
    }
  }

  /// Ruta que corresponde a la pantalla actual, o null si la URL no se toca.
  String? _pathForState() {
    switch (_currentScreen) {
      case OhtliScreen.home:
        return AppUrl.homeTabPaths[_homeInitialIndex] ?? '/explorar';
      case OhtliScreen.accountManagement:
        return '/cuenta';
      case OhtliScreen.places:
        return '/lugares';
      case OhtliScreen.underConstruction:
        return ConstructionPage.isOldDomain ? null : '/';
      case OhtliScreen.login:
      case OhtliScreen.mobileWelcome:
      case OhtliScreen.mobileLogin:
        return '/entrar';
      case OhtliScreen.register:
      case OhtliScreen.mobileRegister:
        return '/registro';
      case OhtliScreen.forgotPassword:
        return '/recuperar';
      case OhtliScreen.onboarding:
        return '/gustos';
      case OhtliScreen.termsAndConditions:
        return _legalPath(_legalDoc);
      default:
        return null; // visor de viajes (?tripId=…), acciones de correo, Labs…
    }
  }

  void _syncUrl() {
    if (!AppUrl.enabled || !mounted || !_isAuthInitialized || _ssoTarget != null) return;
    // Con sesión, la portada es solo un paso hacia la pantalla principal (redirección pendiente)
    if (FirebaseAuth.instance.currentUser != null && _currentScreen == OhtliScreen.underConstruction) return;
    final path = _pathForState();
    if (path == null) return;
    AppUrl.instance.show(path, replace: _replaceNextUrl);
    _replaceNextUrl = false;
  }

  /// El navegador cambió la URL (Atrás/Adelante): se muestra la pantalla de esa ruta.
  void _onExternalUrl(Uri uri) {
    if (!mounted || !AppUrl.enabled) return;
    final path = AppUrl.normalize(uri.path);
    final params = uri.queryParameters;
    final user = FirebaseAuth.instance.currentUser;
    final tab = AppUrl.homeTabForPath(path);
    final legal = {
      for (final d in LegalDocId.values)
        if (_legalPath(d) != null) _legalPath(d)!: d,
    }[path];
    setState(() {
      if (params.containsKey('tripId') && params.containsKey('authorId')) {
        _publicTripId = params['tripId']!;
        _publicAuthorId = params['authorId']!;
        _currentScreen = OhtliScreen.publicViewer;
      } else if (path == '/muestra') {
        _publicTripId = kSampleTripId;
        _publicAuthorId = kSampleOwnerId;
        _currentScreen = OhtliScreen.publicViewer;
      } else if (tab != null) {
        if (user != null) {
          _homeInitialIndex = tab;
          _currentScreen = OhtliScreen.home;
        } else if (tab == 5) {
          _currentScreen = OhtliScreen.places;
        } else {
          _pendingHomeIndex = tab;
          _currentScreen = _loginScreen;
        }
      } else if (path == '/cuenta') {
        if (user != null) {
          _currentScreen = OhtliScreen.accountManagement;
        } else {
          _pendingAccount = true;
          _currentScreen = _loginScreen;
        }
      } else if (legal != null) {
        _legalDoc = legal;
        _currentScreen = OhtliScreen.termsAndConditions;
      } else if (user != null) {
        // Con sesión, la portada y el acceso llevan a la pantalla principal
        if (path == '/gustos') {
          _currentScreen = OhtliScreen.onboarding;
        } else {
          _replaceNextUrl = true;
          _currentScreen = OhtliScreen.home;
        }
      } else if (path == '/entrar') {
        _currentScreen = _loginScreen;
      } else if (path == '/registro') {
        _currentScreen = _registerScreen;
      } else if (path == '/recuperar') {
        _currentScreen = OhtliScreen.forgotPassword;
      } else {
        _currentScreen = OhtliScreen.underConstruction;
      }
    });
  }

  @override
  void dispose() {
    if (AppUrl.instance.onExternal == _onExternalUrl) AppUrl.instance.onExternal = null;
    _authSubscription.cancel();
    _onlineSub?.cancel();
    _offlineSub?.cancel();
    super.dispose();
  }

  void _openLegal(LegalDocId doc) {
    setState(() {
      _legalDoc = doc;
      _currentScreen = OhtliScreen.termsAndConditions;
    });
  }

  /// "Volver" desde el inicio de sesión: en lab.ohtli.quest regresa a la landing de Labs y en
  /// ohtli.quest/sso al subdominio que pidió la sesión.
  void _goPublicHome() {
    // ohtli.quest/sso: quien llegó desde un subdominio (p. ej. "Participa" en Labs) vuelve allá.
    if (_ssoTarget != null && kIsWeb) {
      OhtliSso.cancelAndReturn(_ssoTarget!);
      return;
    }
    if (_isLabAppHost && kIsWeb) {
      web.window.location.href = 'https://labs.ohtli.quest/';
      return;
    }
    _navigateTo(OhtliScreen.underConstruction);
  }

  /// Cerrar sesión desde Labs: en lab.ohtli.quest vuelve al inicio de sesión; en labs.ohtli.quest
  /// /eval muestra su entrada pública y en otro caso la landing.
  Future<void> _signOutOfLabs() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    if (_isLabAppHost) {
      _intentLabs = true;
      _navigateTo(OhtliScreen.login);
    } else if (_currentScreen == OhtliScreen.labEval) {
      setState(() {});
    } else {
      _navigateTo(OhtliScreen.labLanding);
    }
  }

  void _openLabsTerms() {
    _labsTermsReturn = _currentScreen;
    _navigateTo(OhtliScreen.labsTermsAndConditions);
  }

  void _navigateTo(OhtliScreen screen) {
    setState(() {
      _currentScreen = screen;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthInitialized) {
      return Scaffold(
        backgroundColor: OhtliSettings.instance.isDarkMode ? const Color(0xFF121214) : OhtliColors.cloudDancer,
        body: const Center(
          child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;
    _lastIsMobile = isMobile;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncUrl());

    Widget activeView;
    if (_currentScreen == OhtliScreen.ssoBridge && _ssoTarget != null && FirebaseAuth.instance.currentUser != null) {
      activeView = SsoBridgePage(
        target: _ssoTarget!,
        onUseAnotherAccount: () => _navigateTo(OhtliScreen.login),
      );
    } else if (_currentScreen == OhtliScreen.underConstruction) {
      final loginScreen = isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login;
      final registerScreen = isMobile ? OhtliScreen.mobileRegister : OhtliScreen.register;
      // El dominio anterior (othli) conserva la pantalla de redirección; el resto ve la landing pública
      activeView = ConstructionPage.isOldDomain
          ? ConstructionPage(onLoginClick: () => _navigateTo(loginScreen))
          : LandingPage(
              onLoginClick: () => _navigateTo(loginScreen),
              onRegisterClick: () => _navigateTo(registerScreen),
              onOpenPlaces: () => _navigateTo(OhtliScreen.places),
              onOpenPublicTrip: (tripId, authorId) {
                setState(() {
                  _publicTripId = tripId;
                  _publicAuthorId = authorId;
                  _currentScreen = OhtliScreen.publicViewer;
                });
              },
              onOpenTerms: () => _openLegal(LegalDocId.terms),
              onOpenLegal: _openLegal,
            );
    } else if (_currentScreen == OhtliScreen.forgotPassword) {
      activeView = ForgotPasswordPage(
        onBack: () {
          if (isMobile) {
            _navigateTo(OhtliScreen.mobileLogin);
          } else {
            _navigateTo(OhtliScreen.login);
          }
        },
      );
    } else if (_currentScreen == OhtliScreen.authAction) {
      activeView = AuthActionPage(
        mode: _authMode,
        oobCode: _oobCode,
        onBackToLogin: () {
          if (isMobile) {
            _navigateTo(OhtliScreen.mobileWelcome);
          } else {
            _navigateTo(OhtliScreen.login);
          }
        },
      );
    } else if (_currentScreen == OhtliScreen.home) {
      activeView = HomePage(
        initialIndex: _homeInitialIndex,
        onTabChanged: (index) => setState(() => _homeInitialIndex = index),
        onLogout: () => _navigateTo(OhtliScreen.underConstruction),
        onNavigateToAccount: () {
          setState(() {
            _homeInitialIndex = 0; // standard reset
            _currentScreen = OhtliScreen.accountManagement;
          });
        },
      );
    } else if (_currentScreen == OhtliScreen.accountManagement) {
      activeView = AccountManagementPage(
        onBackToHome: (index) {
          setState(() {
            _homeInitialIndex = index;
            _currentScreen = OhtliScreen.home;
          });
        },
        onLogout: () async {
          try {
            _navigateTo(OhtliScreen.underConstruction);
            await FirebaseAuth.instance.signOut();
          } catch (e) {
            print("Error al cerrar sesión: $e");
          }
        },
      );
    } else if (_currentScreen == OhtliScreen.publicViewer) {
      activeView = TripViewerPage(
        tripId: _publicTripId,
        authorId: _publicAuthorId,
        isPublicLink: true,
        onLoginRedirect: () => _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login),
        onBackToDashboard: () => _navigateTo(
            FirebaseAuth.instance.currentUser != null ? OhtliScreen.home : OhtliScreen.underConstruction),
      );
    } else if (_currentScreen == OhtliScreen.test404) {
      activeView = Error404Page(
        onExploreHome: () => _navigateTo(OhtliScreen.home),
      );
    } else if (_currentScreen == OhtliScreen.labLanding) {
      activeView = DeferredView(
        load: lab_landing.loadLibrary,
        builder: (_) => lab_landing.LabLandingPage(
        onLoginRedirect: () {
          // En producción, "Ingresar a Labs" abre el laboratorio individual en lab.ohtli.quest
          final host = kIsWeb ? web.window.location.hostname : '';
          if (host == 'labs.ohtli.quest') {
            web.window.location.href = 'https://lab.ohtli.quest/';
            return;
          }
          setState(() {
            _intentLabs = true;
          });
          _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
        },
        onTryExperiment: (id) {
          // "Probar ahora": abre ese experimento dentro de Labs (en producción, en lab.ohtli.quest).
          final host = kIsWeb ? web.window.location.hostname : '';
          if (host == 'labs.ohtli.quest') {
            web.window.location.href = 'https://lab.ohtli.quest/labs/$id';
            return;
          }
          _labSection = 'exp:$id';
          if (FirebaseAuth.instance.currentUser != null) {
            _navigateTo(OhtliScreen.labApp);
          } else {
            _intentLabs = true;
            _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
          }
        },
      ),
      );
    } else if (_currentScreen == OhtliScreen.labApp ||
        (_currentScreen == OhtliScreen.labEval && FirebaseAuth.instance.currentUser != null)) {
      // Ohtli Labs con sesión: una sola interfaz con menú y vistas según el rol. /eval con sesión
      // abre en Participa.
      final user = FirebaseAuth.instance.currentUser;
      activeView = user == null
          ? const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal))
          : DeferredView(
              load: labs_app.loadLibrary,
              builder: (_) => labs_app.LabsAppPage(
                key: ValueKey('labs-${user.uid}'),
                initialSection: _currentScreen == OhtliScreen.labEval ? 'participa' : _labSection,
                onSignOut: _signOutOfLabs,
                onOpenTerms: _openLabsTerms,
              ),
            );
    } else if (_currentScreen == OhtliScreen.labEval) {
      activeView = DeferredView(
        load: lab_eval.loadLibrary,
        builder: (_) => lab_eval.LabEvalPage(
          onLogin: () {
            // En labs/lab.ohtli.quest la sesión llega por el SSO con la cuenta de Ohtli
            if (OhtliSso.isSubdomain) {
              OhtliSso.continueWithOhtli();
              return;
            }
            setState(() => _intentEval = true);
            _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
          },
        ),
      );
    } else if (_currentScreen == OhtliScreen.labsResults || _currentScreen == OhtliScreen.labsNews) {
      activeView = DeferredView(
        load: labs_results.loadLibrary,
        builder: (_) => labs_results.LabsResultsPage(
          slug: _newsSlug,
          onOpenEval: () => _navigateTo(OhtliScreen.labEval),
        ),
      );
    } else if (_currentScreen == OhtliScreen.apiLanding) {
      // En api.ohtli.quest "Iniciar sesión" usa la cuenta de Ohtli (SSO) y vuelve aquí.
      activeView = StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          return DeferredView(
            load: api_landing.loadLibrary,
            builder: (_) => api_landing.ApiLandingPage(
            onLoginRedirect: OhtliSso.isSubdomain
                ? OhtliSso.continueWithOhtli
                : () => _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login),
            onRegisterRedirect: () => _navigateTo(isMobile ? OhtliScreen.mobileRegister : OhtliScreen.register),
            onOpenLegal: _openLegal,
            accountLabel: user == null ? null : ((user.displayName ?? '').isNotEmpty ? user.displayName : user.email),
          ),
          );
        },
      );
    } else if (_currentScreen == OhtliScreen.termsAndConditions) {
      activeView = LegalCenterPage(
        key: ValueKey(_legalDoc),
        initialDoc: _legalDoc,
        onBack: () => _navigateTo(
            FirebaseAuth.instance.currentUser != null ? OhtliScreen.home : OhtliScreen.underConstruction),
      );
    } else if (_currentScreen == OhtliScreen.labsTermsAndConditions) {
      activeView = LegalCenterPage(
        initialDoc: LegalDocId.labs,
        onBack: () {
          // Vuelve a donde se abrieron (p. ej. el consentimiento de /eval); si se llegó por la URL,
          // en lab.ohtli.quest al inicio de sesión y en labs.ohtli.quest a la landing.
          final back = _labsTermsReturn;
          _labsTermsReturn = null;
          if (back != null) {
            _navigateTo(back);
          } else if (_isLabAppHost) {
            // Con sesión, directo a la consola o al espacio de testers; sin sesión, a iniciarla.
            _intentLabs = true;
            final u = FirebaseAuth.instance.currentUser;
            if (u != null) {
              _handlePostAuthRedirect(u);
            } else {
              _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
            }
          } else {
            _navigateTo(OhtliScreen.labLanding);
          }
        },
      );
    } else if (_currentScreen == OhtliScreen.onboarding) {
      activeView = OnboardingWizardPage(
        onCompleted: _goHomeAfterAuth,
      );
    } else if (_currentScreen == OhtliScreen.places) {
      final user = FirebaseAuth.instance.currentUser;
      activeView = PlacesPage(
        showBackButton: true,
        onBack: () => _navigateTo(user != null ? OhtliScreen.home : OhtliScreen.underConstruction),
        onLoginClick: () {
          _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
        },
        onRegisterClick: () {
          _navigateTo(isMobile ? OhtliScreen.mobileRegister : OhtliScreen.register);
        },
      );
    } else if (isMobile) {
      switch (_currentScreen) {
        case OhtliScreen.mobileWelcome:
          activeView = MobileWelcomePage(
            onBack: _goPublicHome,
            onLoginClick: () => _navigateTo(OhtliScreen.mobileLogin),
            onJoinClick: () => _navigateTo(OhtliScreen.mobileRegister),
          );
          break;
        case OhtliScreen.mobileLogin:
          activeView = MobileLoginPage(
            onBack: () => _navigateTo(OhtliScreen.mobileWelcome),
            onRegisterClick: () => _navigateTo(OhtliScreen.mobileRegister),
            onLoginSuccess: _onAuthSuccess,
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
          break;
        case OhtliScreen.mobileRegister:
          activeView = MobileRegisterPage(
            onBack: () => _navigateTo(OhtliScreen.mobileLogin),
            onLoginClick: () => _navigateTo(OhtliScreen.mobileLogin),
            onRegisterSuccess: _onAuthSuccess,
          );
          break;
        default:
          activeView = MobileLoginPage(
            onBack: () => _navigateTo(OhtliScreen.mobileWelcome),
            onRegisterClick: () => _navigateTo(OhtliScreen.mobileRegister),
            onLoginSuccess: _onAuthSuccess,
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
      }
    } else {
      switch (_currentScreen) {
        case OhtliScreen.login:
          activeView = DesktopLoginPage(
            onBack: _goPublicHome,
            onRegisterClick: () => _navigateTo(OhtliScreen.register),
            onLoginSuccess: _onAuthSuccess,
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
          break;
        case OhtliScreen.register:
          activeView = DesktopRegisterPage(
            onBack: () => _navigateTo(OhtliScreen.login),
            onLoginClick: () => _navigateTo(OhtliScreen.login),
            onRegisterSuccess: _onAuthSuccess,
          );
          break;
        default:
          activeView = DesktopLoginPage(
            onBack: _goPublicHome,
            onRegisterClick: () => _navigateTo(OhtliScreen.register),
            onLoginSuccess: _onAuthSuccess,
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
      }
    }

    // En lab.ohtli.quest, en el inicio de sesión: entrar con la sesión de ohtli.quest.
    if (OhtliSso.isSubdomain &&
        FirebaseAuth.instance.currentUser == null &&
        (_currentScreen == OhtliScreen.login ||
            _currentScreen == OhtliScreen.mobileLogin ||
            _currentScreen == OhtliScreen.mobileWelcome)) {
      activeView = Stack(
        children: [
          activeView,
          Positioned(
            top: 14,
            left: 12,
            right: 12,
            child: Center(child: _OhtliSsoBanner(onContinue: OhtliSso.continueWithOhtli)),
          ),
        ],
      );
    }

    // ohtli.quest/sso sin sesión: dice para qué sitio se inicia sesión y permite volver a él.
    if (_ssoTarget != null &&
        FirebaseAuth.instance.currentUser == null &&
        (_currentScreen == OhtliScreen.login ||
            _currentScreen == OhtliScreen.register ||
            _currentScreen == OhtliScreen.mobileLogin ||
            _currentScreen == OhtliScreen.mobileWelcome ||
            _currentScreen == OhtliScreen.mobileRegister)) {
      final target = _ssoTarget!;
      activeView = Stack(
        children: [
          activeView,
          Positioned(
            top: 14,
            left: 12,
            right: 12,
            child: Center(
              child: _OhtliSsoBanner(
                icon: Icons.science_outlined,
                message: 'Inicia sesión con tu cuenta de Ohtli para continuar en ${siteNameForHost(target.host)}.',
                actionLabel: 'Volver',
                outlined: true,
                onContinue: () => OhtliSso.cancelAndReturn(target),
              ),
            ),
          ),
        ],
      );
    }

    final pageView = AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: activeView,
    );

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(child: pageView),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            height: _showBanner ? 28 : 0,
            width: double.infinity,
            color: _bannerColorIsTeal
                ? OhtliColors.stormyTeal
                : OhtliColors.onyx,
            child: _showBanner
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _bannerText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: _bannerColorIsTeal
                              ? Colors.white
                              : OhtliColors.cloudDancer,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Aviso en el inicio de sesión de un subdominio: "Continuar con tu cuenta de Ohtli".
class _OhtliSsoBanner extends StatelessWidget {
  final VoidCallback onContinue;
  final String message;
  final String actionLabel;
  final IconData icon;
  final bool outlined;
  const _OhtliSsoBanner({
    required this.onContinue,
    this.message = '¿Ya iniciaste sesión en ohtli.quest?',
    this.actionLabel = 'Continuar con Ohtli',
    this.icon = Icons.verified_user_outlined,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OhtliColors.cardBg,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: OhtliColors.stormyTeal, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx),
              ),
            ),
            const SizedBox(width: 10),
            outlined
                ? OutlinedButton(
                    onPressed: onContinue,
                    style: OutlinedButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
                    child: Text(actionLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  )
                : FilledButton(
                    onPressed: onContinue,
                    style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal),
                    child: Text(actionLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
          ],
        ),
      ),
    );
  }
}
