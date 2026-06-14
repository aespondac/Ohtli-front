import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/colors.dart';
import '../../../widgets/user_profile_helper.dart';

class LabWaitlistDialog extends StatefulWidget {
  const LabWaitlistDialog({super.key});

  @override
  State<LabWaitlistDialog> createState() => _LabWaitlistDialogState();
}

class _LabWaitlistDialogState extends State<LabWaitlistDialog> {
  bool _acceptedTerms = false;
  bool _isLoading = false;
  bool _isSuccess = false;

  Future<void> _handleGoogleSignIn() async {
    if (!_acceptedTerms) return;

    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }
      final googleProvider = GoogleAuthProvider();
      final credential = await FirebaseAuth.instance.signInWithPopup(googleProvider);

      final user = credential.user;
      if (user != null) {
        // Here we call the specialized labs waitlist sync profile
        await UserProfileHelper.syncLabsWaitlistProfile(user);
        
        if (mounted) {
          setState(() {
            _isSuccess = true;
            _isLoading = false;
          });
          
          // Close dialog after 3 seconds of showing success
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
      }
    } catch (e) {
      print("Error signing into labs waitlist: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ocurrió un error: ${e.toString()}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF0A090C).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFFF0EEE9).withValues(alpha: 0.1),
              ),
            ),
            child: _isSuccess ? _buildSuccessView() : _buildRegistrationForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.science_rounded, color: OhtliColors.stormyTeal, size: 28),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Color(0xFFF0EEE9)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Unirse a Ohtli Labs',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF0EEE9),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Regístrate para obtener acceso anticipado a nuestras funcionalidades experimentales. La aprobación está sujeta a disponibilidad.',
          style: GoogleFonts.outfit(
            fontSize: 16,
            color: const Color(0xFFF0EEE9).withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        // Terms & Conditions Checkbox
        GestureDetector(
          onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _acceptedTerms,
                  onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                  activeColor: OhtliColors.stormyTeal,
                  side: BorderSide(color: const Color(0xFFF0EEE9).withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Acepto los Términos y Condiciones y comprendo que el software en Labs es experimental, inestable y puede presentar errores.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFFF0EEE9).withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // Google Auth Button
        SizedBox(
          width: double.infinity,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _acceptedTerms ? 1.0 : 0.4,
            child: ElevatedButton(
              onPressed: _isLoading || !_acceptedTerms ? null : _handleGoogleSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF0EEE9),
                foregroundColor: const Color(0xFF0A090C),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0A090C),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/google.svg',
                          height: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Unirme con Google',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 64),
        ),
        const SizedBox(height: 32),
        Text(
          '¡Estás en la lista!',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF0EEE9),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tu solicitud ha sido registrada exitosamente con estado pendiente. Te notificaremos cuando tu acceso a Ohtli Labs sea aprobado.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 16,
            color: const Color(0xFFF0EEE9).withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
