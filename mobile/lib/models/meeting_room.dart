import 'package:cloud_firestore/cloud_firestore.dart';

enum MeetingRoomStatus { available, occupied, maintenance, inactive }

class MeetingRoom {
  const MeetingRoom({
    this.id = '',
    required this.name,
    required this.capacity,
    required this.floor,
    required this.amenities,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String name;
  final int capacity;
  final String floor;
  final List<String> amenities;
  final MeetingRoomStatus status;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'capacity': capacity,
      'floor': floor,
      'amenities': amenities,
      'status': status.name,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }

  factory MeetingRoom.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Meeting room document is empty');
    }

    final statusValue =
        data['status'] as String? ?? MeetingRoomStatus.inactive.name;

    final status = MeetingRoomStatus.values.firstWhere(
      (value) => value.name == statusValue,
      orElse: () => MeetingRoomStatus.inactive,
    );

    final amenities = List<String>.from(
      data['amenities'] as List<dynamic>? ?? <dynamic>[],
    );

    final createdAtValue = data['createdAt'];

    return MeetingRoom(
      id: document.id,
      name: data['name'] as String? ?? '',
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      floor: data['floor'] as String? ?? '',
      amenities: amenities,
      status: status,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
    );
  }
}
