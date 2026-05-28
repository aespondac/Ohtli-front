import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    options = const FirebaseOptions(
      apiKey: configApiKey,
      authDomain: configAuthDomain,
      projectId: configProjectId,
      storageBucket: configStorageBucket,
      messagingSenderId: configMessagingSenderId,
      appId: configAppId,
      measurementId: configMeasurementId,
    );
  } else {
    // Fallback local con credenciales de desarrollo para evitar fallos de carga inicial
    options = const FirebaseOptions(
      apiKey: "AIzaSyD-localDevFakeKeyForOhtliQuestAuth",
      authDomain: "othli-497404.firebaseapp.com",
      projectId: "othli-497404",
      storageBucket: "othli-497404.appspot.com",
      messagingSenderId: "1234567890",
      appId: "1:1234567890:web:fakeAppId",
    );
  }

  try {
    await Firebase.initializeApp(options: options);
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
    return MaterialApp(
      title: 'Ohtli | El viaje empieza aquí',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: OhtliColors.cloudDancer,
        colorScheme: ColorScheme.fromSeed(
          seedColor: OhtliColors.stormyTeal,
          primary: OhtliColors.stormyTeal,
          error: OhtliColors.xoconostle,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      ),
      home: const MainNavigationController(),
    );
  }
}

// Enumeración para controlar la navegación fluida de Ohtli
enum OhtliScreen {
  underConstruction,
  login,          // Pantalla unificada (maneja split en desktop y welcome/login en móvil)
  mobileWelcome,  // Pantalla oscura de bienvenida exclusiva móvil
  mobileLogin,    // Formulario claro exclusivo móvil
  register,       // Formulario de registro en Desktop (split screen)
  mobileRegister, // Formulario de registro en Móvil
  forgotPassword, // Pantalla de recuperación de contraseña
  home,           // Pantalla principal tras autenticación exitosa
  authAction,     // Pantalla de acción de autenticación (recuperación/verificación)
  accountManagement, // Pantalla independiente de gestión de cuenta
}

class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});

  @override
  State<MainNavigationController> createState() => _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  OhtliScreen _currentScreen = OhtliScreen.underConstruction;
  late StreamSubscription<User?> _authSubscription;
  String _oobCode = '';
  String _authMode = '';

  @override
  void initState() {
    super.initState();

    // Check for Firebase Auth Action parameters in URL on startup
    final params = Uri.base.queryParameters;
    if (params.containsKey('mode') && params.containsKey('oobCode')) {
      _authMode = params['mode']!;
      _oobCode = params['oobCode']!;
      _currentScreen = OhtliScreen.authAction;
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        if (_currentScreen != OhtliScreen.home && 
            _currentScreen != OhtliScreen.authAction && 
            _currentScreen != OhtliScreen.accountManagement) {
          _navigateTo(OhtliScreen.home);
        }
      } else {
        if (_currentScreen == OhtliScreen.home || _currentScreen == OhtliScreen.accountManagement) {
          _navigateTo(OhtliScreen.underConstruction);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _navigateTo(OhtliScreen screen) {
    setState(() {
      _currentScreen = screen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    Widget activeView;
    if (_currentScreen == OhtliScreen.underConstruction) {
      activeView = ConstructionPage(onLoginClick: () {
        if (isMobile) {
          _navigateTo(OhtliScreen.mobileWelcome);
        } else {
          _navigateTo(OhtliScreen.login);
        }
      });
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
        onLogout: () => _navigateTo(OhtliScreen.underConstruction),
        onNavigateToAccount: () => _navigateTo(OhtliScreen.accountManagement),
      );
    } else if (_currentScreen == OhtliScreen.accountManagement) {
      activeView = AccountManagementPage(
        onBackToHome: () => _navigateTo(OhtliScreen.home),
        onLogout: () async {
          try {
            await FirebaseAuth.instance.signOut();
            _navigateTo(OhtliScreen.underConstruction);
          } catch (e) {
            print("Error al cerrar sesión: $e");
          }
        },
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
            onLoginSuccess: () => _navigateTo(OhtliScreen.home),
            onForgotPasswordClick: () => _navigateTo(OhtliScreen.forgotPassword),
          );
          break;
        case OhtliScreen.mobileRegister:
          activeView = MobileRegisterPage(
            onBack: () => _navigateTo(OhtliScreen.mobileLogin),
            onLoginClick: () => _navigateTo(OhtliScreen.mobileLogin),
            onRegisterSuccess: () => _navigateTo(OhtliScreen.home),
          );
          break;
        default:
          activeView = MobileLoginPage(
            onBack: () => _navigateTo(OhtliScreen.mobileWelcome),
            onRegisterClick: () => _navigateTo(OhtliScreen.mobileRegister),
            onLoginSuccess: () => _navigateTo(OhtliScreen.home),
            onForgotPasswordClick: () => _navigateTo(OhtliScreen.forgotPassword),
          );
      }
    } else {
      switch (_currentScreen) {
        case OhtliScreen.login:
          activeView = DesktopLoginPage(
            onBack: () => _navigateTo(OhtliScreen.underConstruction),
            onRegisterClick: () => _navigateTo(OhtliScreen.register),
            onLoginSuccess: () => _navigateTo(OhtliScreen.home),
            onForgotPasswordClick: () => _navigateTo(OhtliScreen.forgotPassword),
          );
          break;
        case OhtliScreen.register:
          activeView = DesktopRegisterPage(
            onBack: () => _navigateTo(OhtliScreen.login),
            onLoginClick: () => _navigateTo(OhtliScreen.login),
            onRegisterSuccess: () => _navigateTo(OhtliScreen.home),
          );
          break;
        default:
          activeView = DesktopLoginPage(
            onBack: () => _navigateTo(OhtliScreen.underConstruction),
            onRegisterClick: () => _navigateTo(OhtliScreen.register),
            onLoginSuccess: () => _navigateTo(OhtliScreen.home),
            onForgotPasswordClick: () => _navigateTo(OhtliScreen.forgotPassword),
          );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: activeView,
    );
  }
}
