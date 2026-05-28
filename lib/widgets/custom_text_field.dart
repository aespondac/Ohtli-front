import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

Widget buildCustomTextField({
  required TextEditingController controller,
  required String hintText,
  bool obscureText = false,
  Widget? suffixIcon,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    validator: validator,
    style: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: OhtliColors.onyx,
    ),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: OhtliColors.onyx.withOpacity(0.45),
      ),
      errorStyle: GoogleFonts.inter(
        color: OhtliColors.xoconostle,
        fontSize: 12,
      ),
      filled: true,
      fillColor: OhtliColors.inputBg,
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
        borderSide: const BorderSide(color: OhtliColors.xoconostle, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: OhtliColors.xoconostle, width: 1.5),
      ),
    ),
  );
}
