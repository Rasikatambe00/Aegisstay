import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0C0908);
  static const Color accent = Color(0xFFFFB29A);
  static const Color card = Color(0xFF1C1614);
  static const Color button = Color(0xFF4A342E);
  static const Color white = Colors.white;
}

class AppTheme {
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(24));

  static ThemeData darkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.card,
      onPrimary: AppColors.background,
      onSecondary: AppColors.background,
      onSurface: AppColors.white,
      onError: AppColors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: colorScheme,
      cardColor: AppColors.card,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: AppColors.white),
        bodyMedium: TextStyle(color: AppColors.white),
        labelLarge: TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        labelStyle: const TextStyle(color: AppColors.accent),
        prefixIconColor: AppColors.accent,
        suffixIconColor: AppColors.accent,
        border: OutlineInputBorder(
          borderRadius: cardRadius,
          borderSide: const BorderSide(color: AppColors.accent, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: cardRadius,
          borderSide: const BorderSide(color: AppColors.accent, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: cardRadius,
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: cardRadius),
          backgroundColor: AppColors.button,
          foregroundColor: AppColors.accent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.accent),
          shape: RoundedRectangleBorder(borderRadius: cardRadius),
          foregroundColor: AppColors.accent,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.35),
      ),
    );
  }
}

class StandardButton extends StatelessWidget {
  const StandardButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.isOutlined = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isOutlined;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    if (isOutlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor ?? AppColors.accent,
          side: BorderSide(color: foregroundColor ?? AppColors.accent),
        ),
        child: child,
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.button,
        foregroundColor: foregroundColor ?? AppColors.accent,
      ),
      child: child,
    );
  }
}

class StandardInput extends StatelessWidget {
  const StandardInput({
    super.key,
    this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.hintText,
  });

  final TextEditingController? controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
