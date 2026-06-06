// lib/main.dart

import 'package:flutter/material.dart';
import 'package:url_strategy/url_strategy.dart';
import 'screens/login_screen.dart';
import 'screens/instructor/instructor_home.dart';
import 'screens/student/student_form_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.loadToken();
  setPathUrlStrategy();
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendanceApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6c63ff),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6c63ff), width: 1.5),
          ),
        ),
      ),
      // Deep-link support: /attend/<id> goes straight to the student form.
      // All other paths fall through to the home widget.
      home: AuthService.instance.isLoggedIn
          ? const InstructorHome()
          : const LoginScreen(),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/attend/')) {
          final sessionId = name.substring('/attend/'.length).trim();
          if (sessionId.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) => StudentFormScreen(sessionId: sessionId),
              settings: settings,
            );
          }
        }
        return null;
      },
    );
  }
}
