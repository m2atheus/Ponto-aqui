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

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final background = isDark
        ? const Color(0xFF15191D)
        : BrandColors.background;
    final container = isDark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFF8FAFC);
    final primary = isDark ? const Color(0xFFA8D0F5) : BrandColors.navy;
    final secondary = isDark ? const Color(0xFF77DED4) : BrandColors.teal;
    final onSurface = isDark ? const Color(0xFFE7EDF2) : BrandColors.ink;
    final muted = isDark ? const Color(0xFFAAB9C5) : BrandColors.muted;
    final border = isDark ? const Color(0xFF414B54) : BrandColors.border;
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.navy,
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? BrandColors.navy : Colors.white,
      secondary: secondary,
      onSecondary: isDark ? const Color(0xFF003D39) : Colors.white,
      secondaryContainer: isDark ? const Color(0xFF163D3A) : BrandColors.mint,
      onSecondaryContainer: secondary,
      tertiary: isDark ? const Color(0xFFF4CB85) : BrandColors.warning,
      tertiaryContainer: isDark
          ? const Color(0xFF3F3322)
          : BrandColors.warningSurface,
      onTertiaryContainer: isDark
          ? const Color(0xFFF4CB85)
          : BrandColors.warning,
      surface: surface,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: container,
      surfaceContainerHigh: container,
      surfaceContainerHighest: isDark
          ? const Color(0xFF353535)
          : BrandColors.border,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: border,
    );
    final base = (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
      colorScheme: scheme,
    );
    final text = base.textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: border),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 76,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: rounded,
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        insetPadding: const EdgeInsets.all(24),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: container,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: secondary, width: 2),
        ),
        prefixIconColor: muted,
        floatingLabelStyle: TextStyle(color: secondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: secondary),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: primary),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: primary,
        selectedColor: scheme.onPrimary,
        iconColor: muted,
        textColor: onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.secondaryContainer),
        headingTextStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        dataTextStyle: TextStyle(color: onSurface, fontSize: 14),
        headingRowHeight: 56,
        dataRowMinHeight: 60,
        dataRowMaxHeight: 72,
        dividerThickness: 0.6,
        horizontalMargin: 24,
        columnSpacing: 32,
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? background : null,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: scheme.secondaryContainer,
        checkmarkColor: secondary,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: secondary),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: BrandColors.navy,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        width: 280,
      ),
    );
  }
}

// Compatibilidade com widgets e testes que usam o tema claro original.
ThemeData buildAdminTheme() => AppTheme.light;
