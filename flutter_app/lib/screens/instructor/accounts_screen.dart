// lib/screens/instructor/accounts_screen.dart

import 'package:flutter/material.dart';
import '../../models/instructor.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Instructor> _accounts = [];
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
      _accounts = await ApiService.listAccounts();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateAccountDialog(onCreated: _load),
    );
  }

  void _showResetDialog(Instructor account) {
    showDialog(
      context: context,
      builder: (_) => _ResetPasswordDialog(
        account: account,
        onReset: () => _snack('Password reset for ${account.username}'),
        onError: (e) => _snack(e, error: true),
      ),
    );
  }

  Future<void> _delete(Instructor account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181c),
        title: const Text('Delete Account'),
        content: Text('Delete "${account.username}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.deleteAccount(account.id);
      _load();
      _snack('Account deleted');
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : const Color(0xFF4ade80),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181c),
        title: const Text('Accounts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('New Account'),
        backgroundColor: const Color(0xFF6c63ff),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: const TextStyle(color: Colors.redAccent)));
    }
    if (_accounts.isEmpty) {
      return Center(
          child: Text('No accounts.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4))));
    }

    final me = AuthService.instance.username;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _accounts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a      = _accounts[i];
        final isSelf = a.username == me;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF18181c),
            borderRadius: BorderRadius.circular(12),
            border: isSelf
                ? Border.all(
                    color: const Color(0xFF6c63ff).withValues(alpha: 0.4))
                : null,
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: a.isAdmin
                  ? const Color(0xFF6c63ff).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              child: Text(
                a.fullName.isNotEmpty
                    ? a.fullName[0].toUpperCase()
                    : a.username[0].toUpperCase(),
                style: TextStyle(
                    color: a.isAdmin
                        ? const Color(0xFF6c63ff)
                        : Colors.white54,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Row(children: [
                Text(
                  a.fullName.isNotEmpty ? a.fullName : a.username,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 14),
                ),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6c63ff).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text('you',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFF6c63ff))),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text('@${a.username}  ·  ${a.role.toUpperCase()}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.4),
                      fontFamily: 'monospace')),
            ])),
            if (!isSelf) ...[
              IconButton(
                icon: const Icon(Icons.lock_reset_rounded,
                    size: 18, color: Colors.white38),
                onPressed: () => _showResetDialog(a),
                tooltip: 'Reset password',
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded,
                    size: 18, color: Colors.redAccent),
                onPressed: () => _delete(a),
                tooltip: 'Delete',
              ),
            ],
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Create Account Dialog — StatefulWidget with proper dispose
// ---------------------------------------------------------------------------

class _CreateAccountDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateAccountDialog({required this.onCreated});

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _userCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _role = 'ta';
  String? _err;

  @override
  void dispose() {
    _userCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF18181c),
      title: const Text('Create Account'),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          if (_err != null) ...[
            Text(_err!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          _field('Full Name', _nameCtrl),
          const SizedBox(height: 10),
          _field('Username', _userCtrl, hint: 'e.g. prof.sharma'),
          const SizedBox(height: 10),
          _field('Password (min 6 chars)', _passCtrl, obscure: true),
          const SizedBox(height: 14),
          const Text('Role',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ta', label: Text('TA')),
              ButtonSegment(value: 'admin', label: Text('Admin')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            try {
              await ApiService.createAccount(
                username: _userCtrl.text.trim(),
                password: _passCtrl.text,
                fullName: _nameCtrl.text.trim(),
                role: _role,
              );
              navigator.pop();
              widget.onCreated();
            } catch (e) {
              if (mounted) setState(() => _err = e.toString());
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl,
          {String? hint, bool obscure = false}) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
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
// Reset Password Dialog — StatefulWidget with proper dispose
// ---------------------------------------------------------------------------

class _ResetPasswordDialog extends StatefulWidget {
  final Instructor account;
  final VoidCallback onReset;
  final void Function(String) onError;
  const _ResetPasswordDialog(
      {required this.account,
      required this.onReset,
      required this.onError});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF18181c),
      title: Text('Reset password for ${widget.account.username}'),
      content: TextField(
        controller: _passCtrl,
        obscureText: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'New Password (min 6 chars)',
          filled: true,
          fillColor: const Color(0xFF0a0a0f),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF6c63ff))),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            try {
              await ApiService.resetAccountPassword(
                  widget.account.id, _passCtrl.text);
              navigator.pop();
              widget.onReset();
            } catch (e) {
              navigator.pop();
              widget.onError(e.toString());
            }
          },
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
