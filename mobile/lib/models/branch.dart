import 'package:cloud_firestore/cloud_firestore.dart';

enum BranchStatus { active, inactive }

class Branch {
  const Branch({
    this.id = '',
    required this.name,
    required this.address,
    required this.city,
    required this.contactNumber,
    required this.totalDeskCapacity,
    required this.totalRoomCapacity,
    required this.openingTime,
    required this.closingTime,
    required this.status,
    this.imageUrl,
    this.createdAt,
  });

  final String id;
  final String name;
  final String address;
  final String city;
  final String contactNumber;
  final int totalDeskCapacity;
  final int totalRoomCapacity;
  final String openingTime;
  final String closingTime;
  final BranchStatus status;
  final String? imageUrl;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'address': address,
      'city': city,
      'contactNumber': contactNumber,
      'totalDeskCapacity': totalDeskCapacity,
      'totalRoomCapacity': totalRoomCapacity,
      'openingTime': openingTime,
      'closingTime': closingTime,
      'status': status.name,
      'imageUrl': imageUrl,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }

  factory Branch.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Branch document is empty');
    }

    final statusValue = data['status'] as String? ?? BranchStatus.active.name;

    final status = BranchStatus.values.firstWhere(
      (value) => value.name == statusValue,
      orElse: () => BranchStatus.active,
    );

    final createdAtValue = data['createdAt'];

    return Branch(
      id: document.id,
      name: data['name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      city: data['city'] as String? ?? '',
      contactNumber: data['contactNumber'] as String? ?? '',
      totalDeskCapacity: (data['totalDeskCapacity'] as num?)?.toInt() ?? 0,
      totalRoomCapacity: (data['totalRoomCapacity'] as num?)?.toInt() ?? 0,
      openingTime: data['openingTime'] as String? ?? '',
      closingTime: data['closingTime'] as String? ?? '',
      status: status,
      imageUrl: data['imageUrl'] as String?,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
    );
  }
}
