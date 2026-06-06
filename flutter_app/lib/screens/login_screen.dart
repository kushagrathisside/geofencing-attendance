// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'instructor/instructor_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl   = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = AuthService.instance.serverUrl;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Please enter username and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    // Persist server URL before attempting login so api calls use it
    final serverUrl = _serverCtrl.text.trim();
    if (serverUrl.isNotEmpty) {
      await AuthService.instance.setServerUrl(serverUrl);
    }

    final err = await AuthService.instance.login(u, p);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const InstructorHome()),
      );
    } else {
      setState(() { _error = err; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),

                  // Logo
                  Container(
                    width: 56, height: 56,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6c63ff).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFF6c63ff).withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.school_rounded,
                        color: Color(0xFF6c63ff), size: 28),
                  ),

                  const Text(
                    'AttendanceApp',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 5,
                        color: Color(0xFF6c63ff),
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Instructor Login',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to manage sessions and attendance.',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  const SizedBox(height: 36),

                  // Error banner
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Username
                  _label('Username'),
                  TextField(
                    controller: _userCtrl,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: _inputDeco('e.g. prof.sharma'),
                  ),
                  const SizedBox(height: 14),

                  // Password
                  _label('Password'),
                  TextField(
                    controller: _passCtrl,
                    style: const TextStyle(color: Colors.white),
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: _inputDeco('••••••••').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white38,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6c63ff),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Sign In',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),

                  const SizedBox(height: 20),

                  // Advanced — server URL
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Advanced',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      iconColor: Colors.white38,
                      collapsedIconColor: Colors.white24,
                      children: [
                        const SizedBox(height: 4),
                        _label('Server URL'),
                        TextField(
                          controller: _serverCtrl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          autocorrect: false,
                          decoration:
                              _inputDeco('http://192.168.x.x:8080'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Change only if the Flask server is on a different address.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'Contact your administrator if you don\'t have an account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.25)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
                letterSpacing: 0.3)),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
        filled: true,
        fillColor: const Color(0xFF13131a),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF6c63ff), width: 1.5)),
      );
}
