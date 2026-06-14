import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../../theme/colors.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/user_profile_helper.dart';

class DesktopRegisterPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onLoginClick;
  final VoidCallback onRegisterSuccess;
  const DesktopRegisterPage({
    super.key,
    required this.onBack,
    required this.onLoginClick,
    required this.onRegisterSuccess,
  });

  @override
  State<DesktopRegisterPage> createState() => _DesktopRegisterPageState();
}

class _DesktopRegisterPageState extends State<DesktopRegisterPage> {
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleHovering = false;
  bool _isSubmitHovering = false;

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las contraseñas no coinciden.'),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: password,
          );

      final fullName =
          '${_nombresController.text.trim()} ${_apellidosController.text.trim()}'
              .trim();
      await credential.user?.updateDisplayName(fullName);

      // Initialize user document in Cloud Firestore with restore support
      final user = credential.user;
      if (user != null) {
        try {
          await UserProfileHelper.syncAndRestoreProfile(
            user,
            customDisplayName: fullName,
          );
          print(
            "Successfully initialized Firestore user document upon email registration.",
          );
        } catch (fsError) {
          print(
            "Error initializing Firestore document upon email registration: $fsError",
          );
        }
      }

      // Enviar correo de verificación de dirección de correo con redirección estética
      final actionCodeSettings = ActionCodeSettings(
        url: '${Uri.base.origin}/?mode=verifyEmail',
        handleCodeInApp: true,
      );
      await credential.user?.sendEmailVerification(actionCodeSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Cuenta creada! Hemos enviado un correo de verificación a ${_emailController.text.trim()}.',
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
        widget.onRegisterSuccess();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Ocurrió un error al crear la cuenta.';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'El correo electrónico ya está registrado.';
      } else if (e.code == 'weak-password') {
        errorMessage =
            'La contraseña es muy débil. Intenta con una más fuerte.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'El formato del correo electrónico no es válido.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
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
      final googleProvider = GoogleAuthProvider();
      final credential = await FirebaseAuth.instance.signInWithPopup(
        googleProvider,
      );

      // Initialize/verify user document in Cloud Firestore with restore support
      final user = credential.user;
      if (user != null) {
        try {
          await UserProfileHelper.syncAndRestoreProfile(user);
        } catch (fsError) {
          print(
            "Error checking/initializing Firestore user document upon Google Sign In: $fsError",
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Sesión iniciada con Google como ${credential.user?.displayName ?? "viajero"}!',
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
        widget.onRegisterSuccess();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Error con Google: ${e.message}';
      if (e.code == 'popup-closed-by-user') {
        errorMessage = 'Se cerró la ventana de Google.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
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
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Row(
        children: [
          // 1. PANEL IZQUIERDO (43% de ancho) - Imagen de concierto y lema Bebas Neue
          Expanded(
            flex: 43,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/bg.png',
                    fit: BoxFit.cover,
                    alignment: const Alignment(-0.4, 0.0),
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.45)),
                ),
                Positioned(
                  top: 24,
                  left: 24,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: widget.onBack,
                    tooltip: 'Volver',
                  ),
                ),
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

          // 2. PANEL DERECHO (57% de ancho) - Formulario de Registro
          Expanded(
            flex: 57,
            child: Container(
              color: OhtliColors.cloudDancer,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/logo.svg',
                            width: 250,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 16),

                          Text(
                            'Registro',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w400,
                              color: OhtliColors.onyx.withValues(alpha: 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 24),

                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: CircularProgressIndicator(
                                color: OhtliColors.stormyTeal,
                              ),
                            )
                          else ...[
                            buildCustomTextField(
                              controller: _nombresController,
                              hintText: 'Nombres',
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Ingresa tus nombres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),

                            buildCustomTextField(
                              controller: _apellidosController,
                              hintText: 'Apellidos',
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Ingresa tus apellidos';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),

                            buildCustomTextField(
                              controller: _emailController,
                              hintText: 'Correo Electronico',
                              keyboardType: TextInputType.emailAddress,
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'Ingresa tu correo';
                                }
                                if (!RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                ).hasMatch(val)) {
                                  return 'Correo no válido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),

                            buildCustomTextField(
                              controller: _passwordController,
                              hintText: 'Contraseña',
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: OhtliColors.stormyTeal.withValues(
                                    alpha: 0.7,
                                  ),
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }
                                if (val.length < 6) {
                                  return 'Debe tener al menos 6 caracteres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),

                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                r'Una contraseña segura debe incluir: Letras mayúsculas y minúsculas (por ejemplo, A, a, B, b) Números (por ejemplo, 1, 2, 3) Caracteres especiales (por ejemplo, !, @, #, $, %)',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: OhtliColors.onyx.withValues(alpha: 0.55),
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            buildCustomTextField(
                              controller: _confirmPasswordController,
                              hintText: 'Confirma Contrseña',
                              obscureText: _obscureConfirmPassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: OhtliColors.stormyTeal.withValues(
                                    alpha: 0.7,
                                  ),
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'Confirma tu contraseña';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  text: 'Al registrarte aceptas nuestros ',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: OhtliColors.onyx.withValues(alpha: 0.6),
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Términos y Condiciones',
                                      style: GoogleFonts.inter(
                                        color: OhtliColors.stormyTeal,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          if (kIsWeb) {
                                            html.window.open('/tyc', '_blank');
                                          }
                                        },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            MouseRegion(
                              onEnter: (_) =>
                                  setState(() => _isSubmitHovering = true),
                              onExit: (_) =>
                                  setState(() => _isSubmitHovering = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: _isSubmitHovering
                                      ? [
                                          BoxShadow(
                                            color: OhtliColors.stormyTeal
                                                .withValues(alpha: 0.25),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: ElevatedButton(
                                  onPressed: _handleRegister,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: OhtliColors.stormyTeal,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  child: Text(
                                    'Crear Cuenta',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: OhtliColors.onyx.withValues(alpha: 0.12),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    'ó',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: OhtliColors.onyx.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: OhtliColors.onyx.withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            MouseRegion(
                              onEnter: (_) =>
                                  setState(() => _isGoogleHovering = true),
                              onExit: (_) =>
                                  setState(() => _isGoogleHovering = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: OhtliSettings.instance.isDarkMode
                                      ? const Color(0xFF1E1E22)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: OhtliSettings.instance.isDarkMode
                                        ? const Color(0xFF2C2C32)
                                        : OhtliColors.onyx.withValues(alpha: 0.12),
                                  ),
                                  boxShadow: _isGoogleHovering
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: InkWell(
                                  onTap: _handleGoogleSignIn,
                                  borderRadius: BorderRadius.circular(30),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SvgPicture.network(
                                        'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                        width: 18,
                                        height: 18,
                                        placeholderBuilder: (context) =>
                                            const Icon(Icons.g_mobiledata),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Iniciar sesión con Google',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: OhtliColors.onyx.withValues(
                                            alpha: 0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            RichText(
                              text: TextSpan(
                                text: '¿Ya tienes cuenta? ',
                                style: GoogleFonts.inter(
                                  color: OhtliColors.onyx.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Iniciar sesión',
                                    style: GoogleFonts.inter(
                                      color: OhtliColors.xoconostle,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = widget.onLoginClick,
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
            ),
          ),
        ],
      ),
    );
  }
}
