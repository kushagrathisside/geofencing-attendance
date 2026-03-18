// lib/screens/instructor/session_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
//import 'package:url_launcher/url_launcher.dart';
import '../../config.dart';
import '../../models/session.dart';
import '../../models/attendance_record.dart';
import '../../services/api_service.dart';
import 'dart:io';
import 'package:http/io_client.dart';
import '../../config.dart';

class SessionDetailScreen extends StatefulWidget {
  final Session session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Session _session;
  List<AttendanceRecord> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _loadRecords();
  }

  String get _link => '$kBaseUrl/attend/${_session.id}';

  Future<void> _loadRecords() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.getRecords(_session.id);
      final list = (data['records'] as List)
          .map((j) => AttendanceRecord.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() { _records = list; });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleSession() async {
    try {
      if (_session.isActive) {
        await ApiService.closeSession(_session.id);
      } else {
        await ApiService.openSession(_session.id);
      }
      final updated = await ApiService.getSession(_session.id);
      setState(() => _session = updated);
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181C),
        title: const Text('Reset Records'),
        content: const Text('This will permanently delete all attendance records for this session. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.resetSession(_session.id);
      _loadRecords();
      _snack('Records cleared.');
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _export() async {
    try {
      final uri = Uri.parse(ApiService.exportUrl(_session.id));
      final response = await IOClient(
        HttpClient()..badCertificateCallback = (cert, host, port) => true,
      ).get(uri, headers: {'X-Admin-Key': kAdminKey}).timeout(kTimeout);

      if (response.statusCode == 200) {
        final home = Platform.environment['HOME'] ?? '.';
        final path = '$home/Desktop/${_session.id}-attendance.csv';
        final file = File(path);
        await file.writeAsString(response.body);
        _snack('Saved to Desktop/${_session.id}-attendance.csv');
      } else {
        _snack('Export failed: ${response.statusCode}', error: true);
      }
    } catch (e) {
      _snack('Export error: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : const Color(0xFF4ADE80),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181C),
        title: Text(_session.courseName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadRecords),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildActions()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  Text('${_records.length} Record${_records.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  const Spacer(),
                  if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              ),
            if (_records.isEmpty && !_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No submissions yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.35))),
                ),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _RecordTile(record: _records[i], index: i + 1),
                childCount: _records.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // QR code
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: _link, size: 120, version: QrVersions.auto),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _session.id,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF7C6AF7)),
              ),
              const SizedBox(height: 4),
              Text(_session.createdAt.substring(0, 16),
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
              const SizedBox(height: 12),
              _StatusBadge(active: _session.isActive),
              const SizedBox(height: 12),
              // Copy link
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _link));
                  _snack('Link copied!');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF7C6AF7)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_link,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70)),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _ActionChip(
          icon: Icons.share_rounded,
          label: 'Share Link',
          onTap: () => Share.share(_link),
        ),
        _ActionChip(
          icon: Icons.download_rounded,
          label: 'Export CSV',
          onTap: _export,
        ),
        _ActionChip(
          icon: _session.isActive ? Icons.lock_rounded : Icons.lock_open_rounded,
          label: _session.isActive ? 'Close Session' : 'Reopen Session',
          onTap: _toggleSession,
          color: _session.isActive ? Colors.orangeAccent : const Color(0xFF4ADE80),
        ),
        _ActionChip(
          icon: Icons.delete_sweep_rounded,
          label: 'Reset Records',
          onTap: _reset,
          color: Colors.redAccent,
        ),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF4ADE80).withOpacity(0.1)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: active ? const Color(0xFF4ADE80).withOpacity(0.4) : Colors.white12,
        ),
      ),
      child: Text(
        active ? '● Active' : '○ Closed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: active ? const Color(0xFF4ADE80) : Colors.white38,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionChip({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final AttendanceRecord record;
  final int index;
  const _RecordTile({required this.record, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Text('$index', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white.withOpacity(0.25), fontWeight: FontWeight.w600)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
          const SizedBox(height: 2),
          Text(record.rollNo, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF7C6AF7))),
          if (record.comments.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(record.comments, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
          ],
        ])),
        Text(
          record.submittedAt.length > 16 ? record.submittedAt.substring(11, 16) : '',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white.withOpacity(0.3)),
        ),
      ]),
    );
  }
}
