import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';

class TermsAndConditionsPage extends StatelessWidget {
  final VoidCallback onBack;

  const TermsAndConditionsPage({
    super.key,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0A090C),
        title: Text('Términos y Condiciones', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
          tooltip: 'Regresar',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Términos y Condiciones de Uso de Ohtli',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0A090C),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Última actualización: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF0A090C).withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 40),
                _buildSection(
                  '1. Aceptación de los Términos',
                  'Al acceder y utilizar Ohtli ("la Aplicación"), usted acepta estar legalmente vinculado por estos Términos y Condiciones. Si no está de acuerdo con alguno de los términos aquí descritos, se le prohíbe el uso de la Aplicación y sus servicios.',
                ),
                _buildSection(
                  '2. Descripción del Servicio',
                  'Ohtli es una plataforma digital diseñada para descubrir lugares, planificar viajes y documentar crónicas de viajes. La Aplicación proporciona herramientas basadas en geolocalización y bases de datos colaborativas.',
                ),
                _buildSection(
                  '3. Cuentas de Usuario',
                  'Para utilizar ciertas funcionalidades, usted debe registrarse y crear una cuenta. Usted es responsable de mantener la confidencialidad de su cuenta y contraseña, y acepta la responsabilidad de todas las actividades que ocurran bajo su cuenta. Ohtli se reserva el derecho de rechazar el servicio, cancelar cuentas o eliminar contenido a su entera discreción.',
                ),
                _buildSection(
                  '4. Privacidad y Datos Personales',
                  'La recopilación y el uso de su información personal están regidos por nuestra Política de Privacidad. Al utilizar Ohtli, usted consiente el procesamiento de sus datos de geolocalización para ofrecerle sugerencias personalizadas y mejorar nuestros servicios.',
                ),
                _buildSection(
                  '5. Contenido Generado por el Usuario',
                  'Usted retiene los derechos sobre el contenido que publique en la Aplicación (fotos, crónicas, reseñas). Sin embargo, al publicarlo, otorga a Ohtli una licencia mundial, no exclusiva y libre de regalías para utilizar, reproducir, modificar y mostrar dicho contenido en relación con los servicios de la Aplicación.',
                ),
                _buildSection(
                  '6. Conducta Prohibida',
                  'Usted acepta no utilizar la Aplicación para:\n- Violar leyes locales, nacionales o internacionales.\n- Acosar, abusar o dañar a otras personas.\n- Interferir o interrumpir los servidores o redes conectadas a la Aplicación.\n- Extraer datos (scraping) sin consentimiento previo y por escrito.',
                ),
                _buildSection(
                  '7. Limitación de Responsabilidad',
                  'Ohtli se proporciona "tal cual" y "según disponibilidad". No garantizamos que el servicio será ininterrumpido, seguro o libre de errores. En ningún caso Ohtli será responsable de daños indirectos, incidentales, especiales o consecuentes derivados del uso o la imposibilidad de uso de la Aplicación.',
                ),
                _buildSection(
                  '8. Modificaciones a los Términos',
                  'Nos reservamos el derecho de modificar estos Términos y Condiciones en cualquier momento. Le notificaremos sobre cambios significativos a través de la Aplicación o por correo electrónico. Su uso continuado de la Aplicación tras dichas modificaciones constituirá su aceptación de las mismas.',
                ),
                _buildSection(
                  '9. Ley Aplicable',
                  'Estos Términos y Condiciones se regirán e interpretarán de acuerdo con las leyes vigentes aplicables en la jurisdicción operativa principal de Ohtli, sin dar efecto a ningún principio de conflictos de leyes.',
                ),
                const SizedBox(height: 40),
                Divider(color: const Color(0xFF0A090C).withValues(alpha: 0.2)),
                const SizedBox(height: 24),
                Text(
                  'Si tiene alguna pregunta sobre estos Términos y Condiciones, por favor contáctenos a través de los canales oficiales de soporte de Ohtli.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF0A090C).withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0A090C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: const Color(0xFF0A090C).withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
