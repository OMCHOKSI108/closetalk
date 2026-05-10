import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _brown = Color(0xFF5D4037);
  static const _brownDark = Color(0xFF3E2723);
  static const _brownLight = Color(0xFFD7CCC8);
  static const _cream = Color(0xFFFFF8F0);
  static const _warmWhite = Color(0xFFFAFAF5);
  static const _gold = Color(0xFFC2924A);
  static const _goldLight = Color(0xFFF5E6CC);

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: _brown,
      onPrimary: Colors.white,
      primaryContainer: _brownLight,
      onPrimaryContainer: _brownDark,
      secondary: _gold,
      onSecondary: Colors.white,
      secondaryContainer: _goldLight,
      onSecondaryContainer: _brownDark,
      tertiary: const Color(0xFF8D6E63),
      surface: _warmWhite,
      onSurface: _brownDark,
      surfaceContainerHighest: _cream,
      onSurfaceVariant: const Color(0xFF6D5A52),
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      outline: const Color(0xFFB8A69E),
    );

    final headlineLarge = GoogleFonts.playfairDisplay(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: _brownDark,
      letterSpacing: -0.5,
    );

    final headlineMedium = GoogleFonts.playfairDisplay(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: _brownDark,
      letterSpacing: -0.3,
    );

    final headlineSmall = GoogleFonts.playfairDisplay(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: _brownDark,
    );

    final titleLarge = GoogleFonts.playfairDisplay(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: _brownDark,
    );

    final titleMedium = GoogleFonts.nunito(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: _brownDark,
    );

    final titleSmall = GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: _brown,
    );

    final bodyLarge = GoogleFonts.nunito(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: _brownDark,
      height: 1.5,
    );

    final bodyMedium = GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: _brownDark,
      height: 1.4,
    );

    final bodySmall = GoogleFonts.nunito(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _brown,
      height: 1.3,
    );

    final labelLarge = GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: _brownDark,
    );

    final labelMedium = GoogleFonts.nunito(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _brown,
    );

    final labelSmall = GoogleFonts.nunito(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: _brown,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: TextTheme(
        displayLarge: headlineLarge,
        displayMedium: headlineMedium,
        displaySmall: headlineSmall,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _warmWhite,
        foregroundColor: _brownDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _warmWhite,
        indicatorColor: _brownLight,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _brown, size: 24);
          }
          return const IconThemeData(
            color: Color(0xFFB8A69E),
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _brown,
            );
          }
          return GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFFB8A69E),
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEFE6DF), width: 1),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0D5CD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0D5CD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brown, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
        ),
        labelStyle: GoogleFonts.nunito(
          color: const Color(0xFF8D7A70),
          fontWeight: FontWeight.w500,
        ),
        hintStyle: GoogleFonts.nunito(
          color: const Color(0xFFB8A69E),
        ),
        prefixIconColor: const Color(0xFF8D7A70),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _brown,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brown,
          side: const BorderSide(color: _brown),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _brown,
          textStyle: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _brown,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _brownDark,
        contentTextStyle: GoogleFonts.nunito(
          color: Colors.white,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEFE6DF),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _brownDark,
        ),
      ),
      scaffoldBackgroundColor: _warmWhite,
      splashColor: _brownLight.withValues(alpha: 0.3),
      highlightColor: _brownLight.withValues(alpha: 0.1),
    );
  }
}
