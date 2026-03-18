// lib/models/attendance_record.dart

class AttendanceRecord {
  final int id;
  final String submittedAt;
  final String name;
  final String rollNo;
  final String comments;
  final double? latitude;
  final double? longitude;

  const AttendanceRecord({
    required this.id,
    required this.submittedAt,
    required this.name,
    required this.rollNo,
    required this.comments,
    this.latitude,
    this.longitude,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: j['id'] as int,
        submittedAt: j['submitted_at'] as String,
        name: j['name'] as String,
        rollNo: j['roll_no'] as String,
        comments: j['comments'] as String? ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}
