import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/colors.dart';
import '../../widgets/custom_text_field.dart';

class MobileLoginPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onRegisterClick;
  final VoidCallback onLoginSuccess;
  final VoidCallback onForgotPasswordClick;
  const MobileLoginPage({
    super.key,
    required this.onBack,
    required this.onRegisterClick,
    required this.onLoginSuccess,
    required this.onForgotPasswordClick,
  });

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
  bool _rememberSession = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(
          _rememberSession ? Persistence.LOCAL : Persistence.SESSION,
        );
      }
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Bienvenido de nuevo, ${credential.user?.displayName ?? credential.user?.email ?? "viajero"}!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
        widget.onLoginSuccess();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Ocurrió un error inesperado al iniciar sesión.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No se encontró ninguna cuenta con este correo.';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'La contraseña ingresada es incorrecta.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'El formato del correo electrónico no es válido.';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'Esta cuenta ha sido inhabilitada.';
      } else if (e.code == 'too-many-requests') {
        errorMessage = 'Demasiados intentos fallidos. Intenta más tarde.';
      } else if (e.code == 'invalid-credential') {
        errorMessage = 'Credenciales inválidas. Verifica tu correo y contraseña.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString()}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(
          _rememberSession ? Persistence.LOCAL : Persistence.SESSION,
        );
      }
      final googleProvider = GoogleAuthProvider();
      final credential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Sesión iniciada con Google como ${credential.user?.displayName ?? "viajero"}!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
        widget.onLoginSuccess();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Error de autenticación con Google: ${e.message}';
      if (e.code == 'popup-closed-by-user') {
        errorMessage = 'La ventana de inicio de sesión con Google fue cerrada.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al iniciar sesión con Google: ${e.toString()}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Stack(
        children: [
          // Botón superior izquierdo de regreso
          Positioned(
            top: 24,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx),
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
                        width: 250,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Text(
                          'Ohtli',
                          style: GoogleFonts.inter(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: OhtliColors.stormyTeal,
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
                          color: OhtliColors.onyx.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 36),

                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
                        )
                      else ...[
                        // INPUT CORREO
                        buildCustomTextField(
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
                        buildCustomTextField(
                          controller: _passwordController,
                          hintText: 'Contraseña',
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: OhtliColors.stormyTeal.withOpacity(0.7),
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Ingresa tu contraseña';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Opciones adicionales: Recordar sesión y Olvidaste tus credenciales
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Recordar sesión
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Checkbox(
                                    value: _rememberSession,
                                    activeColor: OhtliColors.stormyTeal,
                                    checkColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    side: BorderSide(
                                      color: OhtliColors.onyx.withOpacity(0.4),
                                      width: 1.2,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _rememberSession = val ?? false;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Recordar sesión',
                                  style: GoogleFonts.inter(
                                    color: OhtliColors.onyx.withOpacity(0.7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),

                            // ¿Olvidaste tus credenciales? Recuperarlas
                            RichText(
                              text: TextSpan(
                                text: '¿Olvidaste tus credenciales? ',
                                style: GoogleFonts.inter(
                                  color: OhtliColors.onyx.withOpacity(0.6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Recuperarlas',
                                    style: GoogleFonts.inter(
                                      color: OhtliColors.xoconostle,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: TapGestureRecognizer()..onTap = widget.onForgotPasswordClick,
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                                        color: OhtliColors.stormyTeal.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: ElevatedButton(
                              onPressed: _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OhtliColors.stormyTeal,
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
                                color: OhtliColors.onyx.withOpacity(0.12),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'ó',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: OhtliColors.onyx.withOpacity(0.4),
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: OhtliColors.onyx.withOpacity(0.12),
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
                                color: OhtliColors.onyx.withOpacity(0.12),
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
                              onTap: _handleGoogleSignIn,
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
                                        color: OhtliColors.onyx.withOpacity(0.8),
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
                              color: OhtliColors.onyx.withOpacity(0.6),
                              fontSize: 12,
                            ),
                            children: [
                              TextSpan(
                                text: 'Empecemos tu viaje',
                                style: GoogleFonts.inter(
                                  color: OhtliColors.xoconostle,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = widget.onRegisterClick,
                              ),
                            ],
                          ),
                        ),
                      ],
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
