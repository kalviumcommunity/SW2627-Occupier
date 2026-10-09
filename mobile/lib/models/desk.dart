import 'package:cloud_firestore/cloud_firestore.dart';

enum DeskStatus { available, occupied, maintenance, inactive }

class Desk {
  const Desk({
    this.id = '',
    required this.name,
    required this.type,
    required this.floor,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String name;
  final String type;
  final String floor;
  final DeskStatus status;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'type': type,
      'floor': floor,
      'status': status.name,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }

  factory Desk.fromFirestore(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();

    if (data == null) {
      throw StateError('Desk document is empty');
    }

    final statusValue = data['status'] as String? ?? DeskStatus.inactive.name;

    final status = DeskStatus.values.firstWhere(
      (value) => value.name == statusValue,
      orElse: () => DeskStatus.inactive,
    );

    final createdAtValue = data['createdAt'];

    return Desk(
      id: document.id,
      name: data['name'] as String? ?? '',
      type: data['type'] as String? ?? '',
      floor: data['floor'] as String? ?? '',
      status: status,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
    );
  }
}
