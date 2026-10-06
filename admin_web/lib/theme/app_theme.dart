import 'package:flutter/material.dart';

abstract final class BrandColors {
  static const navy = Color(0xFF0B3158);
  static const teal = Color(0xFF008E89);
  static const mint = Color(0xFFE7F5F3);
  static const background = Color(0xFFF3F7F9);
  static const ink = Color(0xFF18334B);
  static const muted = Color(0xFF5F7485);
  static const border = Color(0xFFDCE6EC);
  static const warning = Color(0xFF875614);
  static const warningSurface = Color(0xFFFFF4DF);
}

ThemeData buildAdminTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.navy,
    primary: BrandColors.navy,
    onPrimary: Colors.white,
    secondary: BrandColors.teal,
    onSecondary: Colors.white,
    secondaryContainer: BrandColors.mint,
    onSecondaryContainer: BrandColors.teal,
    tertiary: BrandColors.warning,
    tertiaryContainer: BrandColors.warningSurface,
    onTertiaryContainer: BrandColors.warning,
    surface: Colors.white,
    onSurface: BrandColors.ink,
    onSurfaceVariant: BrandColors.muted,
    outline: BrandColors.muted,
    outlineVariant: BrandColors.border,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: BrandColors.border),
  );
  return base.copyWith(
    scaffoldBackgroundColor: BrandColors.background,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: BrandColors.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 76,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded,
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
      insetPadding: const EdgeInsets.all(24),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BrandColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BrandColors.teal, width: 2),
      ),
      prefixIconColor: BrandColors.muted,
      floatingLabelStyle: const TextStyle(color: BrandColors.teal),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BrandColors.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: BrandColors.teal),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: BrandColors.navy),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selectedTileColor: BrandColors.navy,
      selectedColor: Colors.white,
      iconColor: BrandColors.muted,
      textColor: BrandColors.ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(BrandColors.mint),
      headingTextStyle: const TextStyle(
        color: BrandColors.navy,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      dataTextStyle: const TextStyle(color: BrandColors.ink, fontSize: 14),
      headingRowHeight: 56,
      dataRowMinHeight: 60,
      dataRowMaxHeight: 72,
      dividerThickness: 0.6,
      horizontalMargin: 24,
      columnSpacing: 32,
      dataRowColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? BrandColors.background
            : null,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: BrandColors.mint,
      checkmarkColor: BrandColors.teal,
      side: const BorderSide(color: BrandColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme: const DividerThemeData(
      color: BrandColors.border,
      thickness: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BrandColors.teal,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: BrandColors.navy,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      width: 280,
    ),
  );
}
