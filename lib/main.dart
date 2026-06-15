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
import 'screens/api/api_landing_page.dart';
import 'screens/legal/terms_and_conditions_page.dart';
import 'screens/legal/labs_terms_and_conditions_page.dart';
import 'screens/lab/experiments/osrm_experiment_page.dart';
import 'widgets/user_profile_helper.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  } catch (e) {
    print("Firebase initialization error: $e");
  }
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
  String _publicAuthorId = '';
  int _homeInitialIndex = 0;
  bool _isAuthInitialized = false;
  bool _intentLabs = false;

  bool _isOnline = true;
  bool _showBanner = false;
  bool _bannerColorIsTeal = false;
  String _bannerText = '';
  StreamSubscription? _onlineSub;
  StreamSubscription? _offlineSub;

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
      final isAppTyc = path.contains('/tyc') || fragment.contains('/tyc');

      if (isLabsTyc) {
        _currentScreen = OhtliScreen.labsTermsAndConditions;
      } else if (hostname.contains('labs.ohtli.quest') || params.containsKey('testLab')) {
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
      if (mounted && !_isAuthInitialized) {
        setState(() {
          _isAuthInitialized = true;
        });
      }

      if (user != null) {
        // If the user signed in through Labs Waitlist, DO NOT create an app profile.
        // Waitlist-specific sync logic is handled directly in LabWaitlistDialog.
        if (_currentScreen != OhtliScreen.labLanding && _currentScreen != OhtliScreen.apiLanding) {
          try {
            await UserProfileHelper.syncAndRestoreProfile(user);
          } catch (e) {
            print("Error syncing profile in main auth state listener: $e");
          }
        }

        if (_currentScreen == OhtliScreen.labLanding) {
          _navigateTo(OhtliScreen.labsDashboard);
        } else if (_intentLabs) {
          _intentLabs = false;
          _navigateTo(OhtliScreen.labsDashboard);
        } else if (_currentScreen != OhtliScreen.home &&
            _currentScreen != OhtliScreen.authAction &&
            _currentScreen != OhtliScreen.accountManagement &&
            _currentScreen != OhtliScreen.publicViewer &&
            _currentScreen != OhtliScreen.labsDashboard &&
            _currentScreen != OhtliScreen.apiLanding &&
            _currentScreen != OhtliScreen.termsAndConditions &&
            _currentScreen != OhtliScreen.labsTermsAndConditions &&
            _currentScreen != OhtliScreen.labsOsrm) {
          _navigateTo(OhtliScreen.home);
        }
      } else {
        if (_currentScreen == OhtliScreen.labsDashboard) {
          _navigateTo(OhtliScreen.labLanding);
        } else if (_currentScreen == OhtliScreen.home ||
            _currentScreen == OhtliScreen.accountManagement) {
          _navigateTo(OhtliScreen.underConstruction);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _onlineSub?.cancel();
    _offlineSub?.cancel();
    super.dispose();
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
    if (_currentScreen == OhtliScreen.underConstruction) {
      activeView = ConstructionPage(
        onLoginClick: () {
          if (isMobile) {
            _navigateTo(OhtliScreen.mobileWelcome);
          } else {
            _navigateTo(OhtliScreen.login);
          }
        },
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
        onBackToDashboard: () => _navigateTo(OhtliScreen.home),
      );
    } else if (_currentScreen == OhtliScreen.test404) {
      activeView = Error404Page(
        onExploreHome: () => _navigateTo(OhtliScreen.home),
      );
    } else if (_currentScreen == OhtliScreen.labLanding) {
      activeView = LabLandingPage(
        onLoginRedirect: () {
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
          _navigateTo(OhtliScreen.labLanding);
        },
        onTryOsrm: () => _navigateTo(OhtliScreen.labsOsrm),
      );
    } else if (_currentScreen == OhtliScreen.apiLanding) {
      activeView = ApiLandingPage(
        onLoginRedirect: () => _navigateTo(isMobile ? OhtliScreen.mobileWelcome : OhtliScreen.login),
      );
    } else if (_currentScreen == OhtliScreen.termsAndConditions) {
      activeView = TermsAndConditionsPage(
        onBack: () => _navigateTo(OhtliScreen.underConstruction),
      );
    } else if (_currentScreen == OhtliScreen.labsTermsAndConditions) {
      activeView = LabsTermsAndConditionsPage(
        onBack: () => _navigateTo(OhtliScreen.labLanding),
      );
    } else if (_currentScreen == OhtliScreen.labsOsrm) {
      activeView = OsrmExperimentPage(
        onBack: () => _navigateTo(OhtliScreen.labsDashboard),
      );
    } else if (isMobile) {
      switch (_currentScreen) {
        case OhtliScreen.mobileWelcome:
          activeView = MobileWelcomePage(
            onBack: () => _navigateTo(OhtliScreen.underConstruction),
            onLoginClick: () => _navigateTo(OhtliScreen.mobileLogin),
            onJoinClick: () => _navigateTo(OhtliScreen.mobileRegister),
          );
          break;
        case OhtliScreen.mobileLogin:
          activeView = MobileLoginPage(
            onBack: () => _navigateTo(OhtliScreen.mobileWelcome),
            onRegisterClick: () => _navigateTo(OhtliScreen.mobileRegister),
            onLoginSuccess: () {}, // Auth listener handles redirect
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
          break;
        case OhtliScreen.mobileRegister:
          activeView = MobileRegisterPage(
            onBack: () => _navigateTo(OhtliScreen.mobileLogin),
            onLoginClick: () => _navigateTo(OhtliScreen.mobileLogin),
            onRegisterSuccess: () {}, // Auth listener handles redirect
          );
          break;
        default:
          activeView = MobileLoginPage(
            onBack: () => _navigateTo(OhtliScreen.mobileWelcome),
            onRegisterClick: () => _navigateTo(OhtliScreen.mobileRegister),
            onLoginSuccess: () {}, // Auth listener handles redirect
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
      }
    } else {
      switch (_currentScreen) {
        case OhtliScreen.login:
          activeView = DesktopLoginPage(
            onBack: () => _navigateTo(OhtliScreen.underConstruction),
            onRegisterClick: () => _navigateTo(OhtliScreen.register),
            onLoginSuccess: () {}, // Auth listener handles redirect
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
          break;
        case OhtliScreen.register:
          activeView = DesktopRegisterPage(
            onBack: () => _navigateTo(OhtliScreen.login),
            onLoginClick: () => _navigateTo(OhtliScreen.login),
            onRegisterSuccess: () {}, // Auth listener handles redirect
          );
          break;
        default:
          activeView = DesktopLoginPage(
            onBack: () => _navigateTo(OhtliScreen.underConstruction),
            onRegisterClick: () => _navigateTo(OhtliScreen.register),
            onLoginSuccess: () {}, // Auth listener handles redirect
            onForgotPasswordClick: () =>
                _navigateTo(OhtliScreen.forgotPassword),
          );
      }
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
