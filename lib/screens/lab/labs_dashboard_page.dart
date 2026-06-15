import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
import '../../widgets/user_profile_helper.dart';

class LabsDashboardPage extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onTryOsrm;

  const LabsDashboardPage({
    super.key,
    required this.onLogout,
    required this.onTryOsrm,
  });

  @override
  State<LabsDashboardPage> createState() => _LabsDashboardPageState();
}

class _LabsDashboardPageState extends State<LabsDashboardPage> {
  bool _acceptedTerms = false;
  bool _isLoading = false;

  Future<void> _joinWaitlist() async {
    if (!_acceptedTerms) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await UserProfileHelper.syncLabsWaitlistProfile(user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ocurrió un error: $e', style: GoogleFonts.inter()),
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9), // Fondo claro para Labs
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0A090C),
        leading: const SizedBox.shrink(), // Sin botón de atrás, LabsDashboard es la raíz
        leadingWidth: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('labs_waitlist').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error al cargar información: ${snapshot.error}', style: GoogleFonts.inter()),
            );
          }

          final doc = snapshot.data;
          final bool isRegistered = doc != null && doc.exists;
          final Map<String, dynamic> data = isRegistered ? doc.data() as Map<String, dynamic> : {};
          final String status = data['status'] ?? 'pending';

          if (!isRegistered) {
            return _buildTermsView();
          } else if (status == 'pending') {
            return _buildWaitlistView();
          } else if (status == 'approved') {
            return _buildApprovedView();
          } else {
            return _buildRejectedView();
          }
        },
      ),
    );
  }

  Widget _buildTermsView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A090C).withValues(alpha: 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.science_rounded, color: OhtliColors.stormyTeal, size: 32),
              ),
              const SizedBox(height: 24),
              Text(
                'Aceptación de Labs',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0A090C),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Al unirte a Ohtli Labs, obtienes acceso anticipado a nuestras funcionalidades experimentales. Estas herramientas están en fase de prueba, por lo que podrían ser inestables, presentar errores o ser eliminadas sin previo aviso.',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: const Color(0xFF0A090C).withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
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
                        side: BorderSide(color: const Color(0xFF0A090C).withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          text: 'Acepto los ',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF0A090C).withValues(alpha: 0.8),
                            height: 1.4,
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
                                    html.window.open('/#/labs/tyc', '_blank');
                                  }
                                },
                            ),
                            const TextSpan(
                              text: ' y comprendo que el software en Labs es experimental e inestable.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _acceptedTerms ? 1.0 : 0.4,
                  child: ElevatedButton(
                    onPressed: _isLoading || !_acceptedTerms ? null : _joinWaitlist,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Aceptar y Unirme a Labs',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitlistView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_empty_rounded, color: OhtliColors.stormyTeal, size: 64),
            ),
            const SizedBox(height: 32),
            Text(
              'Estás en la lista de espera',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A090C),
                height: 1.1,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text(
                'Tu solicitud ha sido registrada exitosamente con estado pendiente. Te notificaremos cuando tu acceso a Ohtli Labs sea aprobado.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  color: const Color(0xFF0A090C).withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A090C).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFF0A090C),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildApprovedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_rounded, color: OhtliColors.stormyTeal, size: 32),
              const SizedBox(width: 16),
              Text(
                '¡Bienvenido a Labs!',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0A090C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tienes acceso habilitado a los siguientes experimentos:',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: const Color(0xFF0A090C).withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              _buildExperimentCard(
                title: 'Caza Lugares',
                desc: 'Consolida información de lugares a través de múltiples fuentes de datos.',
                icon: Icons.travel_explore_rounded,
                color: OhtliColors.stormyTeal,
              ),
              _buildExperimentCard(
                title: 'Descubre tu Vibe',
                desc: 'Te develamos tu "vibe" y lugares en la ciudad que te gustarían.',
                icon: Icons.auto_awesome_rounded,
                color: OhtliColors.xoconostle,
              ),
              _buildExperimentCard(
                title: 'Ruteo OSRM',
                desc: 'Motor de ruteo experimental impulsado por OSRM y Ye.',
                icon: Icons.directions_car_rounded,
                color: const Color(0xFFE2711D),
                onTap: widget.onTryOsrm,
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildRejectedView() {
    return Center(
      child: Text(
        'Lo sentimos, tu acceso a Labs no pudo ser habilitado en este momento.',
        style: GoogleFonts.inter(fontSize: 18),
      ),
    );
  }

  Widget _buildExperimentCard({required String title, required String desc, required IconData icon, required Color color, VoidCallback? onTap}) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 24),
          Text(title, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0A090C))),
          const SizedBox(height: 8),
          Text(desc, style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0A090C).withValues(alpha: 0.6))),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap ?? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Experimento no disponible aún.')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Probar'),
            ),
          )
        ],
      ),
    );
  }
}
