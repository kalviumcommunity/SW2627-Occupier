class Occupancy {
  final String occupancyId;
  final String branchId;
  final String resourceId;
  final String resourceType;
  final String userId;
  final String? bookingId;
  final OccupancyStatus status;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final OccupancySource source;
  final DateTime createdAt;

  Occupancy({
    required this.occupancyId,
    required this.branchId,
    required this.resourceId,
    required this.resourceType,
    required this.userId,
    this.bookingId,
    required this.status,
    required this.checkInTime,
    this.checkOutTime,
    required this.source,
    required this.createdAt,
  });
}

enum OccupancyStatus {
  active,
  completed,
}

enum OccupancySource {
  booking,
  walkIn,
}