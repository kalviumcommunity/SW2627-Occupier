import 'package:cloud_firestore/cloud_firestore.dart';

enum BookingResourceType { desk, room }

enum BookingStatus { pending, confirmed, cancelled, completed }

class Booking {
  const Booking({
    this.id = '',
    required this.userId,
    required this.branchId,
    required this.resourceId,
    required this.resourceType,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String branchId;
  final String resourceId;
  final BookingResourceType resourceType;
  final DateTime startTime;
  final DateTime endTime;
  final BookingStatus status;
  final DateTime? createdAt;
  final String createdBy;

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'branchId': branchId,
      'resourceId': resourceId,
      'resourceType': resourceType.name,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'status': status.name,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'createdBy': createdBy,
    };
  }

  factory Booking.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Booking document is empty');
    }

    final resourceTypeValue = data['resourceType'] as String?;

    final resourceType = BookingResourceType.values.firstWhere(
      (value) => value.name == resourceTypeValue,
      orElse: () {
        throw StateError('Invalid booking resource type: $resourceTypeValue');
      },
    );

    final statusValue =
        data['status'] as String? ?? BookingStatus.cancelled.name;

    final status = BookingStatus.values.firstWhere(
      (value) => value.name == statusValue,
      orElse: () => BookingStatus.cancelled,
    );

    DateTime readDateTime(dynamic value, String fieldName) {
      if (value is Timestamp) {
        return value.toDate();
      }

      throw StateError(
        'Booking field "$fieldName" must be a Firestore Timestamp.',
      );
    }

    final createdAtValue = data['createdAt'];

    return Booking(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      resourceId: data['resourceId'] as String? ?? '',
      resourceType: resourceType,
      startTime: readDateTime(data['startTime'], 'startTime'),
      endTime: readDateTime(data['endTime'], 'endTime'),
      status: status,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}
