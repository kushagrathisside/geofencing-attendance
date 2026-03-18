// lib/screens/instructor/instructor_home.dart

import 'package:flutter/material.dart';
import '../../models/session.dart';
import '../../services/api_service.dart';
import 'create_session_screen.dart';
import 'session_detail_screen.dart';

class InstructorHome extends StatefulWidget {
  const InstructorHome({super.key});

  @override
  State<InstructorHome> createState() => _InstructorHomeState();
}

class _InstructorHomeState extends State<InstructorHome> {
  List<Session> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _sessions = await ApiService.listSessions();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181C),
        title: const Text('Sessions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateSessionScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Session'),
        backgroundColor: const Color(0xFF7C6AF7),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Text('No sessions yet.\nTap + to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.4))),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _SessionTile(
          session: _sessions[i],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: _sessions[i]),
              ),
            );
            _load();
          },
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;
  const _SessionTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF18181C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: session.isActive ? const Color(0xFF4ADE80) : Colors.white24,
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.courseName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 3),
                Text(
                  '${session.id}  ·  ${session.createdAt.substring(0, 10)}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white.withOpacity(0.4)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ]),
        ),
      ),
    );
  }
}
