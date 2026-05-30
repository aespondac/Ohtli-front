import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/colors.dart';
import '../../widgets/custom_text_field.dart';
import '../construction_page.dart'; // To reuse RouteBackgroundPainter

class ForgotPasswordPage extends StatefulWidget {
  final VoidCallback onBack;
  const ForgotPasswordPage({super.key, required this.onBack});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSubmitHovering = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final actionCodeSettings = ActionCodeSettings(
        url: '${Uri.base.origin}/?mode=resetPassword',
        handleCodeInApp: true,
      );
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
        actionCodeSettings: actionCodeSettings,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Correo de recuperación enviado! Revisa la bandeja de entrada de ${_emailController.text.trim()}.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.stormyTeal,
            duration: const Duration(seconds: 5),
          ),
        );
        widget.onBack();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Ocurrió un error al enviar el correo.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No se encontró ninguna cuenta con este correo.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'El formato del correo electrónico no es válido.';
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
    final isMobile = screenSize.width < 600;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Stack(
        children: [
          // Líneas de mapa decorativas de fondo
          Positioned.fill(
            child: CustomPaint(
              painter: RouteBackgroundPainter(OhtliColors.cantera.withValues(alpha: 0.95)),
            ),
          ),

          // Botón de regreso superior izquierdo
          Positioned(
            top: 24,
            left: 16,
            child: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx),
              onPressed: widget.onBack,
              tooltip: 'Volver al Inicio',
            ),
          ),

          // Formulario central
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: OhtliColors.cloudDancer, // Solid color to mask background lines
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(color: OhtliColors.cantera.withValues(alpha: 0.5)),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // LOGOTIPO OHTLI
                        SvgPicture.asset(
                          'assets/logo.svg',
                          width: 200,
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
                        const SizedBox(height: 20),

                        Text(
                          'Recuperar Cuenta',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: OhtliColors.onyx.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          'Ingresa tu correo electrónico registrado y te enviaremos un enlace para restablecer tu contraseña.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w300,
                            color: OhtliColors.onyx.withValues(alpha: 0.6),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),

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
                          const SizedBox(height: 24),

                          // BOTÓN ENVIAR
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
                                          color: OhtliColors.stormyTeal.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: ElevatedButton(
                                onPressed: _handleResetPassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: OhtliColors.stormyTeal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: Text(
                                  'Enviar enlace',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // BOTÓN DE REGRESO EXPLICÍTCO
                        TextButton(
                          onPressed: widget.onBack,
                          child: Text(
                            'Volver al inicio de sesión',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: OhtliColors.stormyTeal,
                            ),
                          ),
                        ),
                      ],
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
