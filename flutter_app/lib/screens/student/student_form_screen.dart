// lib/screens/student/student_form_screen.dart
//
// Students arrive here via QR scan → /attend/<session_id>
// Steps: load session → capture GPS + fingerprint → submit

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/session.dart';
import '../../services/api_service.dart';
import '../../services/fingerprint_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum _SubmitState { idle, locating, submitting, success, denied, error, closed, notFound }

class StudentFormScreen extends StatefulWidget {
  final String sessionId;
  const StudentFormScreen({super.key, required this.sessionId});

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();

  Session? _session;
  bool _sessionLoading = true;
  _SubmitState _state = _SubmitState.idle;
  String _statusMsg = '';

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    try {
      final s = await ApiService.getSession(widget.sessionId);
      setState(() {
        _session = s;
        _sessionLoading = false;
        if (!s.isActive) _state = _SubmitState.closed;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        setState(() { _state = _SubmitState.notFound; _sessionLoading = false; });
      } else {
        setState(() { _state = _SubmitState.error; _statusMsg = e.message; _sessionLoading = false; });
      }
    } catch (e) {
      setState(() { _state = _SubmitState.error; _statusMsg = e.toString(); _sessionLoading = false; });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _state = _SubmitState.locating; _statusMsg = 'Getting your location…'; });

    try {
      double lat = 0.0;
      double lon = 0.0;

      // geolocator only works on Android, iOS, and Web — not Linux desktop
      if (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) throw Exception('Location services are disabled.');

        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
          if (perm == LocationPermission.denied) throw Exception('Location permission denied.');
        }
        if (perm == LocationPermission.deniedForever) {
          throw Exception('Location permission permanently denied. Enable it in Settings.');
        }
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lat = pos.latitude;
        lon = pos.longitude;
      }
      // On Linux desktop: lat/lon stay 0.0 (geofencing should be disabled for testing)

      setState(() => _statusMsg = 'Verifying device…');
      final fingerprint = await FingerprintService.getFingerprint();

      setState(() { _state = _SubmitState.submitting; _statusMsg = 'Submitting…'; });
      await ApiService.submitAttendance(
        sessionId: widget.sessionId,
        name: _nameCtrl.text.trim(),
        rollNo: _rollCtrl.text.trim(),
        fingerprint: fingerprint,
        latitude: lat,
        longitude: lon,
        comments: _commentsCtrl.text.trim(),
      );

      setState(() => _state = _SubmitState.success);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        setState(() => _state = _SubmitState.denied);
      } else {
        setState(() { _state = _SubmitState.error; _statusMsg = e.message; });
      }
    } catch (e) {
      setState(() { _state = _SubmitState.error; _statusMsg = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F11),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _SubmitState.success:
        return _ResultView(
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF4ADE80),
          title: 'Attendance Marked!',
          subtitle: 'Your attendance for ${_session?.courseName ?? 'this session'} has been recorded.',
        );
      case _SubmitState.denied:
        return _ResultView(
          icon: Icons.block_rounded,
          iconColor: Colors.orangeAccent,
          title: 'Already Submitted',
          subtitle: 'Attendance from this device has already been recorded for this session.',
        );
      case _SubmitState.closed:
        return _ResultView(
          icon: Icons.lock_rounded,
          iconColor: Colors.white38,
          title: 'Session Closed',
          subtitle: 'This session is no longer accepting submissions.',
        );
      case _SubmitState.notFound:
        return _ResultView(
          icon: Icons.search_off_rounded,
          iconColor: Colors.redAccent,
          title: 'Session Not Found',
          subtitle: 'The session ID "${widget.sessionId}" does not exist. Please check with your instructor.',
        );
      case _SubmitState.error:
        return _ResultView(
          icon: Icons.error_outline_rounded,
          iconColor: Colors.redAccent,
          title: 'Something went wrong',
          subtitle: _statusMsg,
          action: TextButton(onPressed: () => setState(() => _state = _SubmitState.idle), child: const Text('Try Again')),
        );
      default:
        return _buildForm();
    }
  }

  Widget _buildForm() {
    final busy = _state == _SubmitState.locating || _state == _SubmitState.submitting;
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Text(
          'ATTENDANCE',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 5,
            color: const Color(0xFF7C6AF7).withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _session?.courseName ?? 'Mark Attendance',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          'Session · ${widget.sessionId}',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white.withOpacity(0.3)),
        ),
        const SizedBox(height: 32),

        _FieldLabel(text: 'Full Name'),
        TextFormField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your full name'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          enabled: !busy,
        ),
        const SizedBox(height: 16),

        _FieldLabel(text: 'Roll Number'),
        TextFormField(
          controller: _rollCtrl,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. CS2301047'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          enabled: !busy,
        ),
        const SizedBox(height: 16),

        _FieldLabel(text: 'Comments (optional)'),
        TextFormField(
          controller: _commentsCtrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Anything to note?'),
          enabled: !busy,
        ),
        const SizedBox(height: 28),

        // Status message
        if (busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(_statusMsg, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
            ]),
          ),

        FilledButton(
          onPressed: busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C6AF7),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Mark My Attendance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 16),
        Text(
          'Your location will be captured to verify you are on-premises.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.25)),
        ),
      ]),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.5), letterSpacing: 0.3),
    ),
  );
}

class _ResultView extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? action;
  const _ResultView({required this.icon, required this.iconColor, required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(height: 48),
      Icon(icon, size: 72, color: iconColor),
      const SizedBox(height: 24),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 12),
      Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5), height: 1.5)),
      if (action != null) ...[const SizedBox(height: 24), action!],
    ]);
  }
}
