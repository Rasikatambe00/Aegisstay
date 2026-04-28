import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

void main() async {
  // Required whenever you do async work before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase BEFORE the app starts
  // Without this, every Supabase call crashes with a "not initialized" error
  // which gets caught by catch(_) and falsely shows "Login failed. Check your connection."
  await Supabase.initialize(
    url: 'https://ykhszzmabsmsvafffjkk.supabase.co',   // ← replace this
    anonKey: 'sb_publishable_u6zK3CaG4TNTM1QkbffyGg_GdQm5OhS', // ← replace this
  );

  runApp(const AegisStayApp());
}

class AegisStayApp extends StatelessWidget {
  const AegisStayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AegisStay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      home: const LoginPage(),
    );
  }
}