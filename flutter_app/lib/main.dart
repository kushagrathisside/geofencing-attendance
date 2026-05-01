// lib/main.dart

import 'package:flutter/material.dart';
import 'package:url_strategy/url_strategy.dart';
import 'screens/home_screen.dart';
import 'screens/instructor/instructor_home.dart';
import 'screens/student/student_form_screen.dart';

void main() {
  setPathUrlStrategy(); // removes # from web URLs
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      // Simple path-based routing:
      //   /             → role selector
      //   /instructor   → instructor home
      //   /attend/:id   → student form for that session
      onGenerateRoute: _router,
      initialRoute: '/',
    );
  }

  ThemeData _buildTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6AF7),
          brightness: Brightness.dark,
        ),
        fontFamily: 'sans-serif',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF7C6AF7), width: 1.5),
          ),
        ),
      );

  Route<dynamic>? _router(RouteSettings settings) {
    final name = settings.name ?? '/';

    // /attend/<session_id>
    if (name.startsWith('/attend/')) {
      final sessionId = name.replaceFirst('/attend/', '');
      return MaterialPageRoute(
        builder: (_) => StudentFormScreen(sessionId: sessionId),
        settings: settings,
      );
    }

    switch (name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/instructor':
        return MaterialPageRoute(builder: (_) => const InstructorHome());
      default:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
    }
  }
}
