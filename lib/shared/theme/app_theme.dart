import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sophisticated Modern Dark Slate Theme for Bar Rooms Trivia
class AppTheme {
  static const Color darkBackground = Color(0xFF0F172A); // Slate 900
  static const Color cardSurface = Color(0xFF1E293B); // Slate 800
  static const Color cardSurfaceElevated = Color(0xFF334155); // Slate 700
  
  // Refined Sophisticated Accents
  static const Color neonCyan = Color(0xFF38BDF8); // Sky 400
  static const Color neonPink = Color(0xFFF43F5E); // Rose 500
  static const Color neonPurple = Color(0xFF818CF8); // Indigo 400
  static const Color neonGreen = Color(0xFF10B981); // Emerald 500
  static const Color neonYellow = Color(0xFFF59E0B); // Amber 500

  // Controller Button Colors
  static const Color buttonA = Color(0xFFEF4444); // Red 500
  static const Color buttonB = Color(0xFF3B82F6); // Blue 500
  static const Color buttonC = Color(0xFFEAB308); // Yellow 500
  static const Color buttonD = Color(0xFF22C55E); // Green 500

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonPink,
        surface: cardSurface,
        background: darkBackground,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 48,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.outfit(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 36,
        ),
        headlineMedium: GoogleFonts.outfit(
          color: neonCyan,
          fontWeight: FontWeight.w600,
          fontSize: 24,
        ),
        bodyLarge: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
          fontSize: 18,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
        ),
      ),
    );
  }
}
