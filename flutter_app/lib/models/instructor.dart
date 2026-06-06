// lib/models/instructor.dart

class Instructor {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final String createdAt;

  const Instructor({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';

  factory Instructor.fromJson(Map<String, dynamic> j) => Instructor(
        id:        j['id'] as int,
        username:  j['username'] as String,
        fullName:  j['full_name'] as String? ?? '',
        role:      j['role'] as String,
        createdAt: j['created_at'] as String? ?? '',
      );
}