// lib/models/session.dart

class Session {
  final String id;
  final String courseName;
  final String createdAt;
  final bool isActive;
  final double? geoLat;
  final double? geoLon;
  final double geoRadius;

  const Session({
    required this.id,
    required this.courseName,
    required this.createdAt,
    required this.isActive,
    this.geoLat,
    this.geoLon,
    this.geoRadius = 100,
  });

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        courseName: j['course_name'] as String,
        createdAt: j['created_at'] as String,
        isActive: (j['is_active'] as int) == 1,
        geoLat: (j['geo_lat'] as num?)?.toDouble(),
        geoLon: (j['geo_lon'] as num?)?.toDouble(),
        geoRadius: (j['geo_radius'] as num?)?.toDouble() ?? 100,
      );
}
