import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/colors.dart';
import '../../widgets/custom_text_field.dart';
import '../construction_page.dart'; // To reuse RouteBackgroundPainter

class AuthActionPage extends StatefulWidget {
  final String mode;
  final String oobCode;
  final VoidCallback onBackToLogin;

  const AuthActionPage({
    super.key,
    required this.mode,
    required this.oobCode,
    required this.onBackToLogin,
  });

  @override
  State<AuthActionPage> createState() => _AuthActionPageState();
}

class _AuthActionPageState extends State<AuthActionPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isVerifying = true;
  bool _isLoading = false;
  bool _hasError = false;
  bool _success = false;
  String _email = '';
  String _errorText = '';
  bool _isSubmitHovering = false;

  @override
  void initState() {
    super.initState();
    _executeAction();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _executeAction() async {
    try {
      if (widget.mode == 'resetPassword') {
        // Verify code is valid and get associated email
        final email = await FirebaseAuth.instance.verifyPasswordResetCode(widget.oobCode);
        setState(() {
          _email = email;
          _isVerifying = false;
        });
      } else if (widget.mode == 'verifyEmail') {
        // Automatically verify email
        await FirebaseAuth.instance.applyActionCode(widget.oobCode);
        setState(() {
          _success = true;
          _isVerifying = false;
        });
      } else {
        // Unsupported mode
        setState(() {
          _hasError = true;
          _errorText = 'La acción solicitada no es compatible.';
          _isVerifying = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'El enlace no es válido o ha expirado.';
      if (e.code == 'expired-action-code') {
        msg = 'El enlace de verificación ha expirado. Por favor, solicita uno nuevo.';
      } else if (e.code == 'invalid-action-code') {
        msg = 'El enlace no es válido. Asegúrate de copiar el URL completo.';
      } else if (e.code == 'user-disabled') {
        msg = 'El usuario asociado con este enlace ha sido deshabilitado.';
      } else if (e.code == 'user-not-found') {
        msg = 'No se encontró el usuario asociado con este enlace.';
      }
      setState(() {
        _hasError = true;
        _errorText = msg;
        _isVerifying = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorText = 'Ocurrió un error inesperado al procesar tu solicitud.';
        _isVerifying = false;
      });
    }
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: _passwordController.text,
      );
      setState(() {
        _success = true;
      });
    } on FirebaseAuthException catch (e) {
      String msg = 'No se pudo restablecer la contraseña.';
      if (e.code == 'expired-action-code') {
        msg = 'El enlace ha expirado. Por favor, solicita uno nuevo.';
      } else if (e.code == 'invalid-action-code') {
        msg = 'El código de acción no es válido.';
      } else if (e.code == 'weak-password') {
        msg = 'La nueva contraseña ingresada es demasiado débil.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Stack(
        children: [
          // CDMX Decorative lines
          Positioned.fill(
            child: CustomPaint(
              painter: RouteBackgroundPainter(OhtliColors.cantera.withValues(alpha: 0.95)),
            ),
          ),

          // Central card container
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: OhtliColors.cloudDancer.withValues(alpha: 0.9),
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
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isVerifying) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: OhtliColors.stormyTeal),
          const SizedBox(height: 24),
          Text(
            'Verificando enlace...',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: OhtliColors.onyx.withValues(alpha: 0.8),
            ),
          ),
        ],
      );
    }

    if (_hasError) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFDE8E8),
            ),
            child: const Icon(
              Icons.link_off_rounded,
              color: OhtliColors.xoconostle,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Enlace inválido o expirado',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorText.isNotEmpty
                ? _errorText
                : 'Este enlace ya fue utilizado, venció su tiempo de validez o el código es incorrecto. Por favor, solicita uno nuevo.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: OhtliColors.onyx.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: widget.onBackToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                'Regresar al Inicio',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.mode == 'verifyEmail') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE6F4EA),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: OhtliColors.stormyTeal,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '¡Correo Verificado!',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tu dirección de correo electrónico ha sido confirmada con éxito. Ya puedes viajar con tranquilidad en Ohtli.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: OhtliColors.onyx.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: widget.onBackToLogin,
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
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      );
    }

    if (_success) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE6F4EA),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: OhtliColors.stormyTeal,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Contraseña restablecida',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tu contraseña ha sido actualizada exitosamente. Ya puedes utilizar tus nuevas credenciales para acceder a Ohtli.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: OhtliColors.onyx.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: widget.onBackToLogin,
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
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      );
    }

    // mode == 'resetPassword' form
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          const SizedBox(height: 16),
          Text(
            'Nueva Contraseña',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: OhtliColors.onyx.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresa la nueva contraseña para $_email',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w300,
              color: OhtliColors.onyx.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),

          buildCustomTextField(
            controller: _passwordController,
            hintText: 'Nueva contraseña',
            obscureText: true,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Ingresa tu contraseña';
              if (val.length < 6) return 'Debe tener al menos 6 caracteres';
              return null;
            },
          ),
          const SizedBox(height: 16),

          buildCustomTextField(
            controller: _confirmPasswordController,
            hintText: 'Confirmar contraseña',
            obscureText: true,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Confirma tu contraseña';
              if (val != _passwordController.text) return 'Las contraseñas no coinciden';
              return null;
            },
          ),
          const SizedBox(height: 28),

          if (_isLoading)
            const CircularProgressIndicator(color: OhtliColors.stormyTeal)
          else
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
                    'Guardar contraseña',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
