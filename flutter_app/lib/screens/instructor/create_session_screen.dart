// lib/screens/instructor/create_session_screen.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import 'session_detail_screen.dart';
import '../../models/session.dart';
import 'package:flutter/foundation.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '100');

  bool _geoEnabled = false;
  double? _lat, _lon;
  bool _fetchingLocation = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      // geolocator not supported on Linux desktop
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        // Hardcode or ask user to type coordinates manually
        throw Exception('GPS not available on desktop. Please disable geofencing or deploy on mobile/web.');
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled.');

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) throw Exception('Location permission denied.');
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() { _lat = pos.latitude; _lon = pos.longitude; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_geoEnabled && (_lat == null || _lon == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture your current location first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ApiService.createSession(
        courseName: _nameCtrl.text.trim(),
        geoLat: _geoEnabled ? _lat : null,
        geoLon: _geoEnabled ? _lon : null,
        geoRadius: double.tryParse(_radiusCtrl.text) ?? 100,
      );

      // Fetch full session object then navigate to detail
      final session = await ApiService.getSession(result['session_id']);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181C),
        title: const Text('New Session', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('Course Name'),
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'e.g. Data Structures — Lecture 4'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 24),

            Row(children: [
              const Text('Enable Geofencing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              const Spacer(),
              Switch(
                value: _geoEnabled,
                onChanged: (v) => setState(() => _geoEnabled = v),
                activeColor: const Color(0xFF7C6AF7),
              ),
            ]),

            if (_geoEnabled) ...[
              const SizedBox(height: 12),
              _label('Allowed Radius (metres)'),
              TextFormField(
                controller: _radiusCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: '100'),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  if (d == null || d <= 0) return 'Enter a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _fetchingLocation ? null : _useCurrentLocation,
                icon: _fetchingLocation
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                label: Text(_lat == null ? 'Use Current Location' : 'Location Captured ✓'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _lat == null ? Colors.white70 : const Color(0xFF4ADE80),
                  side: BorderSide(color: _lat == null ? Colors.white24 : const Color(0xFF4ADE80)),
                ),
              ),
              if (_lat != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white.withOpacity(0.4)),
                  ),
                ),
            ],

            const SizedBox(height: 32),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C6AF7),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Session', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.5), letterSpacing: 0.5)),
  );
}
