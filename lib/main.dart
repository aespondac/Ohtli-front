import 'dart:async';
import 'dart:html' as html;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
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
        scaffoldBackgroundColor: const Color(0xFFF0EEE9), // Cloud Dancer
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C666E), // Stormy Teal
          primary: const Color(0xFF2C666E),
          error: const Color(0xFF6C3953), // Xoconostle
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
}

class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});

  @override
  State<MainNavigationController> createState() => _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  OhtliScreen _currentScreen = OhtliScreen.underConstruction;

  void _navigateTo(OhtliScreen screen) {
    setState(() {
      _currentScreen = screen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    // Redirección interna si estamos en móvil e intentamos ver el login unificado,
    // lo mandamos a la pantalla de bienvenida oscura (Mockup 2).
    Widget activeView;
    if (_currentScreen == OhtliScreen.underConstruction) {
      activeView = ConstructionPage(onLoginClick: () {
        if (isMobile) {
          _navigateTo(OhtliScreen.mobileWelcome);
        } else {
          _navigateTo(OhtliScreen.login);
        }
      });
    } else if (isMobile) {
      if (_currentScreen == OhtliScreen.mobileWelcome) {
        activeView = MobileWelcomePage(
          onBack: () => _navigateTo(OhtliScreen.underConstruction),
          onLoginClick: () => _navigateTo(OhtliScreen.mobileLogin),
          onJoinClick: () => _navigateTo(OhtliScreen.mobileLogin),
        );
      } else {
        activeView = MobileLoginPage(
          onBack: () => _navigateTo(OhtliScreen.mobileWelcome),
        );
      }
    } else {
      activeView = DesktopLoginPage(
        onBack: () => _navigateTo(OhtliScreen.underConstruction),
      );
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

// ---------------------------------------------------------
// 1. PÁGINA DE SITIO EN CONSTRUCCIÓN (Mejorada con botón de entrar)
// ---------------------------------------------------------
class ConstructionPage extends StatefulWidget {
  final VoidCallback onLoginClick;
  const ConstructionPage({super.key, required this.onLoginClick});

  @override
  State<ConstructionPage> createState() => _ConstructionPageState();
}

class _ConstructionPageState extends State<ConstructionPage> with SingleTickerProviderStateMixin {
  final List<String> _travelPhrases = [
    'el viaje empieza aquí',
    'estamos preparando todo',
    'trazando tus rutas ideales',
    'diseñando tu camino por la CDMX',
    'explorando nuevas perspectivas',
  ];

  int _currentPhraseIndex = 0;
  late Timer _phraseTimer;
  late AnimationController _fadeController;
  bool _isHoveringEnter = false;

  bool get _isOldDomain {
    try {
      final host = Uri.base.host.toLowerCase();
      final hasOldParam = Uri.base.queryParameters['old'] == 'true';
      final isFirebaseDomain = host.contains('web.app') || host.contains('firebaseapp.com');
      return ((host.contains('othli') && !host.contains('ohtli') && !isFirebaseDomain)) || hasOldParam;
    } catch (e) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _phraseTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          _currentPhraseIndex = (_currentPhraseIndex + 1) % _travelPhrases.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _phraseTimer.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    const colorStormyTeal = Color(0xFF2C666E);
    const colorOnyx = Color(0xFF0A090C);
    const colorCantera = Color(0xFFD1CDC4);
    const colorXoconostle = Color(0xFF6C3953);

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeController,
        child: Stack(
          children: [
            // Líneas de mapa decorativas
            Positioned.fill(
              child: CustomPaint(
                painter: RouteBackgroundPainter(colorCantera.withOpacity(0.95)),
              ),
            ),

            // Botón flotante superior de "Iniciar Sesión" (Solo si no es el dominio de desvío)
            if (!_isOldDomain)
              Positioned(
                top: 24,
                right: 24,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isHoveringEnter = true),
                  onExit: (_) => setState(() => _isHoveringEnter = false),
                  child: TextButton(
                    onPressed: widget.onLoginClick,
                    style: TextButton.styleFrom(
                      foregroundColor: _isHoveringEnter ? colorXoconostle : colorStormyTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: Text(
                      'iniciar sesión',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                ),
              ),

            // Contenido Central
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_isOldDomain)
                      _buildRedirectView(colorStormyTeal, colorOnyx, colorXoconostle, isMobile)
                    else
                      _buildMainView(colorStormyTeal, colorOnyx, colorXoconostle, isMobile),
                  ],
                ),
              ),
            ),

            // Footer
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'ohtli  •  cdmx',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 4.0,
                    color: colorOnyx.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainView(Color colorStormyTeal, Color colorOnyx, Color colorXoconostle, bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          constraints: const BoxConstraints(
            maxWidth: 280,
            maxHeight: 90,
          ),
          child: SvgPicture.asset(
            'assets/logo.svg',
            width: 240,
            fit: BoxFit.contain,
            placeholderBuilder: (BuildContext context) => _buildLogoFallback(colorStormyTeal, colorXoconostle),
            errorBuilder: (context, error, stackTrace) => _buildLogoFallback(colorStormyTeal, colorXoconostle),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey<int>(_currentPhraseIndex),
            child: Text(
              _travelPhrases[_currentPhraseIndex],
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w300,
                color: colorOnyx,
                letterSpacing: 2.0,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRedirectView(Color colorStormyTeal, Color colorOnyx, Color colorXoconostle, bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Oh - tli!',
          style: GoogleFonts.caprasimo(
            fontSize: isMobile ? 72 : 110,
            color: colorXoconostle,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '¡no te preocupes, a todos nos pasa!',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 22 : 28,
            fontWeight: FontWeight.w300,
            color: colorOnyx,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Escribiste Othli en lugar de Ohtli (con la "h" antes de la "t"). En náhuatl, "ohtli" significa camino y el camino correcto te está esperando.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.w300,
            color: colorOnyx.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 40),
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringEnter = true),
          onExit: (_) => setState(() => _isHoveringEnter = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 220,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: _isHoveringEnter
                  ? [
                      BoxShadow(
                        color: colorStormyTeal.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: ElevatedButton(
              onPressed: () {
                html.window.location.href = 'https://ohtli.quest';
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorStormyTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                'seguir mi camino',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoFallback(Color primaryColor, Color accentColor) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: primaryColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primaryColor.withOpacity(0.06),
          border: Border.all(
            color: primaryColor,
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.explore_outlined,
          color: primaryColor,
          size: 48,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. MOCKUP 1: INICIO DE SESIÓN EN DESKTOP (Split Screen)
// ---------------------------------------------------------
class DesktopLoginPage extends StatefulWidget {
  final VoidCallback onBack;
  const DesktopLoginPage({super.key, required this.onBack});

  @override
  State<DesktopLoginPage> createState() => _DesktopLoginPageState();
}

class _DesktopLoginPageState extends State<DesktopLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isGoogleHovering = false;
  bool _isSubmitHovering = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    const colorStormyTeal = Color(0xFF2C666E);
    const colorOnyx = Color(0xFF0A090C);
    const colorCantera = Color(0xFFD1CDC4);
    const colorXoconostle = Color(0xFF6C3953);

    return Scaffold(
      body: Row(
        children: [
          // 1. PANEL IZQUIERDO (43% de ancho) - Imagen de concierto y frase Bebas Neue
          Expanded(
            flex: 43,
            child: Stack(
              children: [
                // Imagen de fondo con guitarrista
                Positioned.fill(
                  child: Image.asset(
                    'assets/bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
                // Overlay oscuro dramático
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
                // Botón discreto superior para volver a Home
                Positioned(
                  top: 24,
                  left: 24,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: widget.onBack,
                    tooltip: 'Volver',
                  ),
                ),
                // Contenido textual
                Positioned(
                  left: 48,
                  bottom: 60,
                  right: 48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MÉXICO DESDE TU\nPROPIA VIBE',
                        style: GoogleFonts.bebasNeue(
                          fontSize: screenSize.height * 0.08,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.05,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. PANEL DERECHO (57% de ancho) - Formulario Claro
          Expanded(
            flex: 57,
            child: Container(
              color: const Color(0xFFF0EEE9), // Cloud Dancer
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // LOGOTIPO OHTLI
                          SvgPicture.asset(
                            'assets/logo.svg',
                            width: 140,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: colorStormyTeal, width: 1.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Ohtli',
                                style: GoogleFonts.inter(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: colorStormyTeal,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Slogan
                          Text(
                            'a un paso de tu destino',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                              color: colorOnyx.withOpacity(0.6),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 36),

                          // INPUT CORREO ELECTRÓNICO
                          _buildCustomTextField(
                            controller: _emailController,
                            hintText: 'Correo electrónico',
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Ingresa tu correo';
                              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                                return 'Correo no válido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // INPUT CONTRASEÑA
                          _buildCustomTextField(
                            controller: _passwordController,
                            hintText: 'Contraseña',
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: SvgPicture.asset(
                                _obscurePassword ? 'assets/Visibility_Off.svg' : 'assets/Visibility.svg',
                                width: 22,
                                height: 22,
                                colorFilter: const ColorFilter.mode(
                                  colorStormyTeal,
                                  BlendMode.srcIn,
                                ),
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Ingresa tu contraseña';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // ¿Olvidaste tus credenciales? Recuperarlas
                          Align(
                            alignment: Alignment.centerRight,
                            child: RichText(
                              text: TextSpan(
                                text: '¿Olvidaste tus credenciales? ',
                                style: GoogleFonts.inter(
                                  color: colorOnyx.withOpacity(0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Recuperarlas',
                                    style: GoogleFonts.inter(
                                      color: colorXoconostle,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // BOTÓN INICIAR SESIÓN
                          MouseRegion(
                            onEnter: (_) => setState(() => _isSubmitHovering = true),
                            onExit: (_) => setState(() => _isSubmitHovering = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: double.infinity,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: _isSubmitHovering
                                    ? [
                                        BoxShadow(
                                          color: colorStormyTeal.withOpacity(0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_formKey.currentState!.validate()) {
                                    // Simulación de inicio de sesión exitosa
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Iniciando sesión...')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorStormyTeal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: Text(
                                  'Iniciar sesión',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Separador "ó"
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: colorOnyx.withOpacity(0.12),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'ó',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: colorOnyx.withOpacity(0.4),
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: colorOnyx.withOpacity(0.12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // BOTÓN GOOGLE
                          MouseRegion(
                            onEnter: (_) => setState(() => _isGoogleHovering = true),
                            onExit: (_) => setState(() => _isGoogleHovering = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: double.infinity,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: colorOnyx.withOpacity(0.12),
                                  width: 1,
                                ),
                                boxShadow: _isGoogleHovering
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: InkWell(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Iniciando sesión con Google...'),
                                      backgroundColor: colorStormyTeal,
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(30),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SvgPicture.network(
                                        'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                        width: 18,
                                        height: 18,
                                        placeholderBuilder: (context) => const Icon(Icons.g_mobiledata, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Iniciar sesión con Google',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: colorOnyx.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // ¿Primera vez? Empecemos tu viaje
                          RichText(
                            text: TextSpan(
                              text: '¿Primera vez? ',
                              style: GoogleFonts.inter(
                                color: colorOnyx.withOpacity(0.6),
                                fontSize: 13,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Empecemos tu viaje',
                                  style: GoogleFonts.inter(
                                    color: colorXoconostle,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// Helper para construir Inputs en Ohtli (Mockups)
// ---------------------------------------------------------
Widget _buildCustomTextField({
  required TextEditingController controller,
  required String hintText,
  bool obscureText = false,
  Widget? suffixIcon,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  const colorInputBg = Color(0xFFDCD8CF); // Warm beige/gray de los mockups
  const colorOnyx = Color(0xFF0A090C);
  const colorXoconostle = Color(0xFF6C3953);

  return TextFormField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    validator: validator,
    style: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: colorOnyx,
    ),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: colorOnyx.withOpacity(0.45),
      ),
      errorStyle: GoogleFonts.inter(
        color: colorXoconostle,
        fontSize: 12,
      ),
      filled: true,
      fillColor: colorInputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: colorXoconostle, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: colorXoconostle, width: 1.5),
      ),
    ),
  );
}

// ---------------------------------------------------------
// 3. MOCKUP 2: BIENVENIDA MÓVIL OSCURA (Mobile Welcome Page)
// ---------------------------------------------------------
class MobileWelcomePage extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLoginClick;
  final VoidCallback onJoinClick;

  const MobileWelcomePage({
    super.key,
    required this.onBack,
    required this.onLoginClick,
    required this.onJoinClick,
  });

  @override
  Widget build(BuildContext context) {
    const colorStormyTeal = Color(0xFF2C666E);
    const colorOnyx = Color(0xFF0A090C);

    return Scaffold(
      body: Stack(
        children: [
          // Imagen de fondo full screen
          Positioned.fill(
            child: Image.asset(
              'assets/bg.png',
              fit: BoxFit.cover,
            ),
          ),
          // Overlay oscuro
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.45),
            ),
          ),
          
          // Icono brújula superior izquierdo (tappable para volver)
          Positioned(
            top: 40,
            left: 24,
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SvgPicture.asset(
                    'assets/icon_isologo.svg',
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF0A090C),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Texto central e inferior del Mockup 2
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MÉXICO DESDE TU PROPIA VIBE
                Text(
                  'MÉXICO DESDE\nTU PROPIA\nVIBE',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 48),

                // BOTÓN: Unete al viaje
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onJoinClick,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorStormyTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Unete al viaje',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // LINK: Iniciar sesión
                Center(
                  child: TextButton(
                    onPressed: onLoginClick,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'Iniciar sesión',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 4. MOCKUP 3: INICIO DE SESIÓN MÓVIL CLARO (Mobile Login Page)
// ---------------------------------------------------------
class MobileLoginPage extends StatefulWidget {
  final VoidCallback onBack;
  const MobileLoginPage({super.key, required this.onBack});

  @override
  State<MobileLoginPage> createState() => _MobileLoginPageState();
}

class _MobileLoginPageState extends State<MobileLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isSubmitHovering = false;
  bool _isGoogleHovering = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colorStormyTeal = Color(0xFF2C666E);
    const colorOnyx = Color(0xFF0A090C);
    const colorXoconostle = Color(0xFF6C3953);

    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9), // Cloud Dancer
      body: Stack(
        children: [
          // Botón superior izquierdo de regreso
          Positioned(
            top: 24,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: colorOnyx),
              onPressed: widget.onBack,
            ),
          ),

          // Formulario Central del Mockup 3
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // LOGOTIPO OHTLI
                      SvgPicture.asset(
                        'assets/logo.svg',
                        width: 130,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Text(
                          'Ohtli',
                          style: GoogleFonts.inter(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: colorStormyTeal,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Slogan
                      Text(
                        'a un paso de tu destino',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          color: colorOnyx.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 36),

                      // INPUT CORREO
                      _buildCustomTextField(
                        controller: _emailController,
                        hintText: 'Correo electrónico',
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Ingresa tu correo';
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                            return 'Correo no válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // INPUT CONTRASEÑA
                      _buildCustomTextField(
                        controller: _passwordController,
                        hintText: 'Contraseña',
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: SvgPicture.asset(
                            _obscurePassword ? 'assets/Visibility_Off.svg' : 'assets/Visibility.svg',
                            width: 22,
                            height: 22,
                            colorFilter: const ColorFilter.mode(
                              colorStormyTeal,
                              BlendMode.srcIn,
                            ),
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Ingresa tu contraseña';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // ¿Olvidaste tus credenciales? Recuperarlas
                      Align(
                        alignment: Alignment.centerRight,
                        child: RichText(
                          text: TextSpan(
                            text: '¿Olvidaste tus credenciales? ',
                            style: GoogleFonts.inter(
                              color: colorOnyx.withOpacity(0.6),
                              fontSize: 11,
                            ),
                            children: [
                              TextSpan(
                                text: 'Recuperarlas',
                                style: GoogleFonts.inter(
                                  color: colorXoconostle,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // BOTÓN: Iniciar sesión
                      MouseRegion(
                        onEnter: (_) => setState(() => _isSubmitHovering = true),
                        onExit: (_) => setState(() => _isSubmitHovering = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: _isSubmitHovering
                                ? [
                                    BoxShadow(
                                      color: colorStormyTeal.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Iniciando sesión...')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorStormyTeal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: Text(
                              'Iniciar sesión',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Separador "ó"
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: colorOnyx.withOpacity(0.12),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'ó',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: colorOnyx.withOpacity(0.4),
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: colorOnyx.withOpacity(0.12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // BOTÓN GOOGLE
                      MouseRegion(
                        onEnter: (_) => setState(() => _isGoogleHovering = true),
                        onExit: (_) => setState(() => _isGoogleHovering = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: colorOnyx.withOpacity(0.12),
                              width: 1,
                            ),
                            boxShadow: _isGoogleHovering
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : [],
                          ),
                          child: InkWell(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Iniciando sesión con Google...'),
                                  backgroundColor: colorStormyTeal,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.network(
                                    'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                    width: 18,
                                    height: 18,
                                    placeholderBuilder: (context) => const Icon(Icons.g_mobiledata, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Iniciar sesión con Google',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: colorOnyx.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ¿Primera vez? Empecemos tu viaje
                      RichText(
                        text: TextSpan(
                          text: '¿Primera vez? ',
                          style: GoogleFonts.inter(
                            color: colorOnyx.withOpacity(0.6),
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: 'Empecemos tu viaje',
                              style: GoogleFonts.inter(
                                color: colorXoconostle,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Pintor personalizado para dibujar líneas de ruta minimalistas
class RouteBackgroundPainter extends CustomPainter {
  final Color lineColor;

  RouteBackgroundPainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final path = Path();

    path.moveTo(0, size.height * 0.25);
    path.quadraticBezierTo(
      size.width * 0.35,
      size.height * 0.2,
      size.width * 0.5,
      size.height * 0.45,
    );
    path.quadraticBezierTo(
      size.width * 0.65,
      size.height * 0.7,
      size.width,
      size.height * 0.65,
    );

    path.moveTo(size.width * 0.2, size.height);
    path.lineTo(size.width * 0.8, 0);

    const double dashLength = 8.0;
    const double gapLength = 5.0;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double nextDistance = distance + dashLength;
        final Path extract = metric.extractPath(distance, nextDistance);
        canvas.drawPath(extract, paint);
        distance = nextDistance + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CenterPlayground {
  static const alignment = CrossAxisAlignment.center;
}
