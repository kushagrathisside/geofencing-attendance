// lib/screens/instructor/instructor_home.dart

import 'package:flutter/material.dart';
import '../../models/session.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'create_session_screen.dart';
import 'session_detail_screen.dart';
import 'accounts_screen.dart';

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
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _forceLogout();
      } else {
        _error = e.message;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _forceLogout() {
    AuthService.instance.logout();
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181c),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () { Navigator.pop(context); _forceLogout(); },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showChangePassword() {
    showDialog(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onSuccess: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Password changed!'),
                backgroundColor: Color(0xFF4ade80),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth    = AuthService.instance;
    final isAdmin = auth.isAdmin;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181c),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sessions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('@${auth.username}  ·  ${auth.role.toUpperCase()}',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.4),
                  fontFamily: 'monospace')),
        ]),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.manage_accounts_rounded),
              tooltip: 'Manage Accounts',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AccountsScreen())),
            ),
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          PopupMenuButton<String>(
            color: const Color(0xFF18181c),
            onSelected: (v) {
              if (v == 'password') _showChangePassword();
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'password', child: Text('Change Password')),
              const PopupMenuItem(
                  value: 'logout',
                  child: Text('Sign Out',
                      style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CreateSessionScreen()));
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Session'),
        backgroundColor: const Color(0xFF6c63ff),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
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
            await Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(session: _sessions[i])));
            _load();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Change Password Dialog — proper StatefulWidget so controllers are disposed
// ---------------------------------------------------------------------------

class _ChangePasswordDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const _ChangePasswordDialog({required this.onSuccess});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currCtrl = TextEditingController();
  final _newCtrl  = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _currCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF18181c),
      title: const Text('Change Password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_err != null) ...[
          Text(_err!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 8),
        ],
        _passField('Current Password', _currCtrl),
        const SizedBox(height: 10),
        _passField('New Password', _newCtrl),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final e = await AuthService.instance
                .changePassword(_currCtrl.text, _newCtrl.text);
            if (!mounted) return;
            if (e == null) {
              navigator.pop();
              widget.onSuccess();
            } else {
              setState(() => _err = e);
            }
          },
          child: const Text('Update'),
        ),
      ],
    );
  }

  Widget _passField(String label, TextEditingController ctrl) => TextField(
        controller: ctrl,
        obscureText: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFF0a0a0f),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF6c63ff))),
        ),
      );
}

// ---------------------------------------------------------------------------
// Session list tile
// ---------------------------------------------------------------------------

class _SessionTile extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;
  const _SessionTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF18181c),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 10, height: 10,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: session.isActive
                    ? const Color(0xFF4ade80)
                    : Colors.white24,
              ),
            ),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(session.courseName,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 3),
              Text(
                '${session.id}  ·  ${session.createdAt.substring(0, 10)}',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4)),
              ),
            ])),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ]),
        ),
      ),
    );
  }
}
