import 'package:flutter/material.dart';

class KizunaTheme {
  static const Color primaryBlue = Color(0xFF00D2FF);
  static const Color accentCyan = Color(0xFF3A7BD5);
  static const Color backgroundBlack = Color(0xFF050505);
  static const Color surfaceGlass = Color(0xFF151515);

  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [primaryBlue, accentCyan],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Color getKarmaColor(double score) {
    final double t = (score.clamp(1.0, 100.0) - 1.0) / 99.0;
    
    // An "infinite" spectrum feeling by interpolating through 5 vibrant stops
    final colors = [
      const Color(0xFFFF3D00), // Deep Red (Force)
      const Color(0xFFFFD600), // Electric Yellow (Ambition)
      const Color(0xFF00E676), // Spring Green (Growth)
      const Color(0xFF00B0FF), // Azure Blue (Integrity)
      const Color(0xFFAA00FF), // Deep Purple (Enlightenment)
    ];

    if (t <= 0) return colors.first;
    if (t >= 1) return colors.last;

    final double segment = 1.0 / (colors.length - 1);
    final int index = (t / segment).floor();
    final double localT = (t - (index * segment)) / segment;

    return Color.lerp(colors[index], colors[index + 1], localT)!;
  }

  static String getKarmaDescription(double score) {
    if (score < 20) return "A NEW SOUL, READY TO IGNITE.";
    if (score < 40) return "AMBITIOUS VIBES, BUILDING MOMENTUM.";
    if (score < 60) return "IN THE FLOW, RADIATING GROWTH.";
    if (score < 80) return "A PILLAR OF TRUST, CALM & STEADY.";
    return "GOD-TIER INTEGRITY. ABSOLUTE LEGEND.";
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
        surface: surfaceGlass,
        primary: primaryBlue,
      ),
      scaffoldBackgroundColor: backgroundBlack,
      fontFamily: 'Inter', // Assuming Inter is available or fallback to system
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: Colors.white70,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 58),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceGlass.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white12, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white10, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
    );
  }
}
