import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/cdmx_photos.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';

/// Marco de las pantallas de acceso (entrar, crear cuenta, recuperar contraseña), con la
/// misma línea visual que la portada: en escritorio, una foto de la ciudad a la izquierda y
/// el formulario a la derecha; en teléfono, una franja de foto y el formulario debajo.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.onBack,
    required this.title,
    this.subtitle = '',
    required this.children,
    this.photo = 0,
    this.backTooltip = 'Volver',
    this.logoHeader = false,
  });

  final VoidCallback onBack;
  final String backTooltip;
  final String title;
  final String subtitle;
  final List<Widget> children;

  /// Índice de [CdmxPhotos.covers] para la foto del panel.
  final int photo;

  /// Encabeza el formulario con el logotipo de Ohtli en lugar del título y el subtítulo
  /// ([title] queda solo para lectores de pantalla). En teléfono se omite la franja de foto.
  final bool logoHeader;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = ohtliIsMobileWidth(width);
    final form = _form(isMobile);

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: isMobile
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _BackButton(onBack: onBack, tooltip: backTooltip),
                        if (!logoHeader) ...[
                          const Spacer(),
                          SvgPicture.asset('assets/logo.svg', height: 26),
                          const Spacer(),
                          const SizedBox(width: 48),
                        ],
                      ],
                    ),
                    if (logoHeader)
                      const SizedBox(height: 24)
                    else ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 132,
                        child: _PhotoPanel(photo: photo, compact: true),
                      ),
                      const SizedBox(height: 28),
                    ],
                    form,
                  ],
                ),
              )
            : Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _PhotoPanel(photo: photo, showLogo: !logoHeader),
                    ),
                  ),
                  Expanded(
                    flex: 11,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 20,
                          left: 12,
                          child: _BackButton(onBack: onBack, tooltip: backTooltip),
                        ),
                        Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 64),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: form,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _form(bool isMobile) {
    if (logoHeader) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: Center(child: SvgPicture.asset('assets/logo.svg', height: isMobile ? 56 : 64)),
            ),
          ),
          SizedBox(height: isMobile ? 32 : 40),
          ...children,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 30 : 36,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
              height: 1.08,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 15, height: 1.5, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 28),
        ...children,
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onBack, required this.tooltip});

  final VoidCallback onBack;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onBack,
      tooltip: tooltip,
      icon: Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx),
    );
  }
}

/// Foto de la ciudad con el lema de la portada.
class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({required this.photo, this.compact = false, this.showLogo = true});

  final int photo;
  final bool compact;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final url = CdmxPhotos.covers[photo % CdmxPhotos.covers.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 22 : 32),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: OhtliColors.stormyTeal.withValues(alpha: 0.35)),
          LayoutBuilder(
            builder: (context, c) => Image.network(
              CdmxPhotos.sized(url, c.maxWidth, MediaQuery.devicePixelRatioOf(context)),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: compact ? 0.05 : 0.15),
                  Colors.black.withValues(alpha: compact ? 0.55 : 0.72),
                ],
              ),
            ),
          ),
          if (!compact && showLogo)
            Positioned(
              top: 32,
              left: 36,
              child: SvgPicture.asset(
                'assets/logo.svg',
                height: 34,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                semanticsLabel: 'Ohtli',
              ),
            ),
          Positioned(
            left: compact ? 18 : 36,
            right: compact ? 18 : 36,
            bottom: compact ? 16 : 40,
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Tu camino por la Ciudad de México, '),
                  TextSpan(
                    text: 'a tu medida.',
                    style: TextStyle(color: OhtliColors.accent.withValues(alpha: 0.95)),
                  ),
                ],
              ),
              style: GoogleFonts.outfit(
                fontSize: compact ? 21 : 44,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.05,
                letterSpacing: compact ? -0.4 : -1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo con su etiqueta visible arriba (no solo como texto de ayuda que desaparece al
/// escribir) y un borde claro al enfocarlo.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.validator,
    this.trailingLabel,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;

  /// Si no es null, el campo es de contraseña y muestra el botón para verla.
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  /// A la derecha de la etiqueta (p. ej. "¿Olvidaste tu contraseña?").
  final Widget? trailingLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.onyx,
                ),
              ),
            ),
            ?trailingLabel,
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          onChanged: onChanged,
          validator: validator,
          autocorrect: false,
          enableSuggestions: onToggleObscure == null && keyboardType != TextInputType.emailAddress,
          style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx),
          cursorColor: OhtliColors.accentText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx.withValues(alpha: 0.4)),
            errorStyle: GoogleFonts.inter(fontSize: 12.5, color: _errorColor),
            errorMaxLines: 3,
            filled: true,
            fillColor: OhtliColors.inputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: onToggleObscure,
                    tooltip: obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(
                      obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: OhtliColors.subtleText,
                    ),
                  ),
            border: border(OhtliColors.cardBorder, 1),
            enabledBorder: border(OhtliColors.cardBorder, 1),
            focusedBorder: border(OhtliColors.accentText, 1.8),
            errorBorder: border(_errorColor, 1.2),
            focusedErrorBorder: border(_errorColor, 1.8),
          ),
        ),
      ],
    );
  }
}

/// Rojo de error legible en ambos modos (el xoconostle de la marca es muy oscuro sobre negro).
Color get _errorColor =>
    OhtliSettings.instance.isDarkMode ? const Color(0xFFF2A3A3) : const Color(0xFFB3261E);

/// Aviso de error dentro del formulario, junto al botón que lo provocó.
class AuthErrorBox extends StatelessWidget {
  const AuthErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _errorColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _errorColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 19, color: _errorColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: OhtliColors.onyx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón principal: mientras trabaja muestra un indicador dentro, sin esconder el formulario.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: OhtliColors.stormyTeal,
          disabledBackgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

const String _googleG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
    '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>'
    '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>'
    '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>'
    '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>'
    '</svg>';

class AuthGoogleButton extends StatelessWidget {
  const AuthGoogleButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: OhtliColors.cardBg,
          foregroundColor: OhtliColors.onyx,
          side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.16)),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(_googleG, width: 19, height: 19, excludeFromSemantics: true),
            const SizedBox(width: 12),
            const Text('Continuar con Google'),
          ],
        ),
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: OhtliColors.onyx.withValues(alpha: 0.12)));
    return ExcludeSemantics(
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('o', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText)),
          ),
          line,
        ],
      ),
    );
  }
}

/// Enlace de texto en el color de acento (p. ej. "Crear cuenta", "¿Olvidaste tu contraseña?").
class AuthLink extends StatelessWidget {
  const AuthLink(this.label, {super.key, required this.onTap, this.fontSize = 14});

  final String label;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: OhtliColors.accentText,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: GoogleFonts.inter(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

/// "¿Primera vez? Crear cuenta" al pie del formulario.
class AuthSwitchLine extends StatelessWidget {
  const AuthSwitchLine({super.key, required this.prompt, required this.action, required this.onTap});

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText)),
        AuthLink(action, onTap: onTap),
      ],
    );
  }
}

/// Validación de correo compartida por las pantallas de acceso.
String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Escribe tu correo.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v)) {
    return 'Revisa el correo: parece incompleto (ej. nombre@correo.com).';
  }
  return null;
}
