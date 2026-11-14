import 'services/user_private_data.dart';
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'screens/error_404_page.dart';
import 'screens/lab/lab_landing_page.dart';
import 'screens/lab/labs_dashboard_page.dart';
import 'labs/lab_console_page.dart';
import 'labs/lab_eval_page.dart';
import 'labs/labs_results_page.dart';
import 'labs/lab_access.dart';
import 'config/admin.dart' show isSuperUser;
import 'screens/api/api_landing_page.dart';
import 'screens/legal/legal_center_page.dart';
import 'screens/legal/legal_content.dart';
import 'screens/lab/experiments/recolector_experiment_page.dart';
import 'screens/lab/experiments/osrm_experiment_page.dart';
import 'screens/lab/experiments/agents_experiment_page.dart';
import 'screens/lab/experiments/apis_experiment_page.dart';
import 'screens/onboarding/onboarding_wizard_page.dart';
import 'screens/lab/experiments/taste_vector_experiment_page.dart';
import 'screens/places/places_page.dart';
import 'widgets/user_profile_helper.dart';
import 'services/ohtli_sso.dart';
import 'services/saved_accounts.dart';
import 'screens/login/sso_bridge_page.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // SSO entre subdominios: toma el código #ohtli_sso=… antes de que el enrutador lea la URL.
  OhtliSso.captureFromUrl();
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
  // Precarga el catálogo de Lugares (y despierta la API si estaba inactiva)
  PlacesPage.prefetch();
  runApp(const OhtliApp());
}

class OhtliApp extends StatelessWidget {
  const OhtliApp({super.key});

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

        return MaterialApp(
          title: 'Ohtli | El viaje empieza aquí',
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
          home: const MainNavigationController(),
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
  labsDashboard, // Dashboard interno de Labs (T&C y experimentos)
  apiLanding, // Landing Page para api.ohtli.quest
  termsAndConditions, // Pantalla de TyC de Ohtli
  labsTermsAndConditions, // Pantalla de TyC de Ohtli Labs
  labsOsrm, // Experimento de OSRM
  labsAgents, // Experimento de Agentes
  labsApis, // Experimento de APIs
  labsRecolector, // Experimento de Caza Lugares (Recolector)
  labsTasteVector, // Experimento de Vector de Gustos e Identidad Cultural
  labConsole, // lab.ohtli.quest: consola de pruebas del TT (superusuario)
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
  bool _isAuthInitialized = false;
  bool _intentLabs = false;
  bool _isLabAppHost = false;
  // SSO: destino validado de ohtli.quest/sso?return=… y control del primer arranque.
  Uri? _ssoTarget;
  bool _ssoChecked = false;
  bool _hadUser = false;
  bool _switchChecked = false;
  bool _intentEval = false;
  LabRole _labRole = LabRole.none;
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
    final params = Uri.base.queryParameters;
    // Routing de Subdominios
    if (kIsWeb) {
      final hostname = html.window.location.hostname ?? '';
      final path = Uri.base.path;
      final fragment = Uri.base.fragment;
      final isLabsTyc = path.contains('/labs/tyc') || fragment.contains('/labs/tyc');
      final isLabsOsrm = path.contains('/labs/osrm') || fragment.contains('/labs/osrm');
      final isLabsAgents = path.contains('/labs/agents') || fragment.contains('/labs/agents');
      final isLabsApis = path.contains('/labs/apis') || fragment.contains('/labs/apis');
      final isLabsRecolector = path.contains('/labs/recolector') || fragment.contains('/labs/recolector');
      final isLabsTaste = path.contains('/labs/taste') || fragment.contains('/labs/taste') || path.contains('/labs/vibe') || fragment.contains('/labs/vibe');
      final isPlaces = path.contains('/lugares') || fragment.contains('/lugares') || path.contains('/places') || fragment.contains('/places') || params.containsKey('lugares') || params.containsKey('places');
      final isAppTyc = path.contains('/tyc') || fragment.contains('/tyc');
      bool hasRoute(String r) => path.contains(r) || fragment.contains(r);
      final legalRoute = hasRoute('/privacidad')
          ? LegalDocId.privacy
          : hasRoute('/cookies')
              ? LegalDocId.cookies
              : hasRoute('/terminos-api')
                  ? LegalDocId.api
                  : null;

      if (isLabsTyc) {
        _currentScreen = OhtliScreen.labsTermsAndConditions;
      } else if (isLabsOsrm) {
        _currentScreen = OhtliScreen.labsOsrm;
      } else if (isLabsAgents) {
        _currentScreen = OhtliScreen.labsAgents;
      } else if (isLabsApis) {
        _currentScreen = OhtliScreen.labsApis;
      } else if (isLabsRecolector) {
        _currentScreen = OhtliScreen.labsRecolector;
      } else if (isLabsTaste) {
        _currentScreen = OhtliScreen.labsTasteVector;
      } else if (legalRoute != null) {
        _legalDoc = legalRoute;
        _currentScreen = OhtliScreen.termsAndConditions;
      } else if (isPlaces) {
        _currentScreen = OhtliScreen.places;
      } else if ((hostname == 'lab.ohtli.quest' || hostname == 'labs.ohtli.quest' || params.containsKey('testLabApp') ||
              params.containsKey('testLab') || params.containsKey('testEval')) &&
          (hasRoute('/eval') || params.containsKey('testEval'))) {
        // /eval: entrada pública para testers de los estudios de Labs (no exige sesión para leerla)
        _currentScreen = OhtliScreen.labEval;
      } else if ((hostname == 'labs.ohtli.quest' || params.containsKey('testLab')) &&
          (hasRoute('/resultados') || hasRoute('/news'))) {
        // labs.ohtli.quest/resultados: reporte tipo paper y tablero; /news: novedades publicadas
        _currentScreen = hasRoute('/news') ? OhtliScreen.labsNews : OhtliScreen.labsResults;
        final m = RegExp(r'/news/([A-Za-z0-9-]+)').firstMatch('$path $fragment');
        _newsSlug = m?.group(1);
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
    if (kIsWeb && OhtliSso.isMainHost && Uri.base.path.startsWith('/sso')) {
      _ssoTarget = OhtliSso.parseReturnTarget(params['return']);
      if (_ssoTarget != null) _currentScreen = OhtliScreen.login;
    }

    if (_currentScreen == OhtliScreen.underConstruction) {
      // Si no fue capturado por subdominios, validamos los parámetros de la URL principal
      if (params.containsKey('mode') && params.containsKey('oobCode')) {
        _authMode = params['mode']!;
        _oobCode = params['oobCode']!;
        _currentScreen = OhtliScreen.authAction;
      } else if (params.containsKey('tripId') && params.containsKey('authorId')) {
        _publicTripId = params['tripId']!;
        _publicAuthorId = params['authorId']!;
        _currentScreen = OhtliScreen.publicViewer;
      } else if (params.containsKey('test404')) {
        _currentScreen = OhtliScreen.test404;
      }
    }

    // Initialize connection status
    if (kIsWeb) {
      _isOnline = html.window.navigator.onLine ?? true;
      if (!_isOnline) {
        _showBanner = true;
        _bannerColorIsTeal = false;
        _bannerText =
            "Sin conexión, algunos datos podrían no guardarse o estar desactualizados";
      }
      _onlineSub = html.window.onOnline.listen(
        (_) => _onConnectionChanged(true),
      );
      _offlineSub = html.window.onOffline.listen(
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
        if (_currentScreen == OhtliScreen.labsDashboard || _currentScreen == OhtliScreen.labConsole) {
          if (_isLabAppHost) _intentLabs = true;
          _navigateTo(_isLabAppHost ? OhtliScreen.login : OhtliScreen.labLanding);
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
    if (_currentScreen == OhtliScreen.labLanding || _intentLabs) {
      // Miembros del laboratorio → consola de pruebas; el resto → espacio de testers
      _intentLabs = false;
      _labRole = await LabAccess.roleOf(user);
      _navigateTo(_labRole.isMember ? OhtliScreen.labConsole : OhtliScreen.labEval);
      return;
    }

    // Pantallas donde la sesión autenticada se mantiene sin forzar redirección
    if (_currentScreen == OhtliScreen.home ||
        _currentScreen == OhtliScreen.authAction ||
        _currentScreen == OhtliScreen.accountManagement ||
        _currentScreen == OhtliScreen.publicViewer ||
        _currentScreen == OhtliScreen.labsDashboard ||
        _currentScreen == OhtliScreen.apiLanding ||
        _currentScreen == OhtliScreen.termsAndConditions ||
        _currentScreen == OhtliScreen.labsTermsAndConditions ||
        _currentScreen == OhtliScreen.labsOsrm ||
        _currentScreen == OhtliScreen.labsAgents ||
        _currentScreen == OhtliScreen.labsApis ||
        _currentScreen == OhtliScreen.labsRecolector ||
        _currentScreen == OhtliScreen.labsTasteVector ||
        _currentScreen == OhtliScreen.labConsole ||
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
        _navigateTo(OhtliScreen.onboarding);
      } else {
        _navigateTo(OhtliScreen.home);
      }
    } catch (e) {
      print("Error or timeout checking onboarding status: $e");
      _navigateTo(OhtliScreen.home);
    }
  }

  @override
  void dispose() {
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

  /// "Volver" desde el inicio de sesión: en lab.ohtli.quest regresa a la landing de Labs.
  void _goPublicHome() {
    if (_isLabAppHost && kIsWeb) {
      html.window.location.href = 'https://labs.ohtli.quest/';
      return;
    }
    _navigateTo(OhtliScreen.underConstruction);
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
      activeView = LabLandingPage(
        onLoginRedirect: () {
          // En producción, "Ingresar a Labs" abre el laboratorio individual en lab.ohtli.quest
          final host = kIsWeb ? (html.window.location.hostname ?? '') : '';
          if (host == 'labs.ohtli.quest') {
            html.window.location.href = 'https://lab.ohtli.quest/';
            return;
          }
          setState(() {
            _intentLabs = true;
          });
          _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
        },
      );
    } else if (_currentScreen == OhtliScreen.labsDashboard) {
      activeView = LabsDashboardPage(
        onLogout: () async {
          await FirebaseAuth.instance.signOut();
          if (_isLabAppHost) _intentLabs = true;
          _navigateTo(_isLabAppHost ? OhtliScreen.login : OhtliScreen.labLanding);
        },
        onTryOsrm: () => _navigateTo(OhtliScreen.labsOsrm),
        onTryAgents: () => _navigateTo(OhtliScreen.labsAgents),
        onTryApis: () => _navigateTo(OhtliScreen.labsApis),
        onTryRecolector: () => _navigateTo(OhtliScreen.labsRecolector),
        onTryTasteVector: () => _navigateTo(OhtliScreen.labsTasteVector),
      );
    } else if (_currentScreen == OhtliScreen.labConsole) {
      activeView = LabConsolePage(
        role: isSuperUser(FirebaseAuth.instance.currentUser) ? LabRole.admin : _labRole,
        onOpenTechnical: () => _navigateTo(OhtliScreen.labsDashboard),
        onLogout: () async {
          await FirebaseAuth.instance.signOut();
          if (_isLabAppHost) _intentLabs = true;
          _navigateTo(_isLabAppHost ? OhtliScreen.login : OhtliScreen.labLanding);
        },
      );
    } else if (_currentScreen == OhtliScreen.labEval) {
      activeView = LabEvalPage(
        onLogin: () {
          // En labs/lab.ohtli.quest la sesión llega por el SSO con la cuenta de Ohtli
          if (OhtliSso.isSubdomain) {
            OhtliSso.continueWithOhtli();
            return;
          }
          setState(() => _intentEval = true);
          _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login);
        },
        onOpenTerms: () => _navigateTo(OhtliScreen.labsTermsAndConditions),
        onOpenConsole: () async {
          _labRole = await LabAccess.roleOf(FirebaseAuth.instance.currentUser);
          if (_labRole.isMember) _navigateTo(OhtliScreen.labConsole);
        },
        onOpenTechnical: () => _navigateTo(OhtliScreen.labsDashboard),
      );
    } else if (_currentScreen == OhtliScreen.labsResults || _currentScreen == OhtliScreen.labsNews) {
      activeView = LabsResultsPage(
        slug: _newsSlug,
        onOpenEval: () => _navigateTo(OhtliScreen.labEval),
      );
    } else if (_currentScreen == OhtliScreen.apiLanding) {
      // En api.ohtli.quest "Iniciar sesión" usa la cuenta de Ohtli (SSO) y vuelve aquí.
      activeView = StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          return ApiLandingPage(
            onLoginRedirect: OhtliSso.isSubdomain
                ? OhtliSso.continueWithOhtli
                : () => _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login),
            onRegisterRedirect: () => _navigateTo(isMobile ? OhtliScreen.mobileRegister : OhtliScreen.register),
            onOpenLegal: _openLegal,
            accountLabel: user == null ? null : ((user.displayName ?? '').isNotEmpty ? user.displayName : user.email),
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
        onBack: () => _navigateTo(OhtliScreen.labLanding),
      );
    } else if (_currentScreen == OhtliScreen.labsOsrm) {
      activeView = OsrmExperimentPage(
        onBack: () => _navigateTo(OhtliScreen.labsDashboard),
      );
    } else if (_currentScreen == OhtliScreen.labsAgents) {
      activeView = AgentsExperimentPage(
        onBack: () => _navigateTo(OhtliScreen.labsDashboard),
      );
    } else if (_currentScreen == OhtliScreen.labsApis) {
      activeView = ApisExperimentPage(
        onBack: () => _navigateTo(OhtliScreen.labsDashboard),
      );
    } else if (_currentScreen == OhtliScreen.labsRecolector) {
      activeView = RecolectorExperimentPage(
        onBack: () => _navigateTo(OhtliScreen.labsDashboard),
      );
    } else if (_currentScreen == OhtliScreen.onboarding) {
      activeView = OnboardingWizardPage(
        onCompleted: () => _navigateTo(OhtliScreen.home),
      );
    } else if (_currentScreen == OhtliScreen.labsTasteVector) {
      activeView = TasteVectorExperimentPage(
        onBack: () => _navigateTo(OhtliScreen.labsDashboard),
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
  const _OhtliSsoBanner({required this.onContinue});

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
            const Icon(Icons.verified_user_outlined, color: OhtliColors.stormyTeal, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '¿Ya iniciaste sesión en ohtli.quest?',
                style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal),
              child: Text('Continuar con Ohtli', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
