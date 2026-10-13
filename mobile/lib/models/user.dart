import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, branchManager, staff, member }

class OccupierUser {
  const OccupierUser({
    required this.uid,
    required this.name,
    required this.email,
    this.role = UserRole.member,
    this.photoUrl,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? photoUrl;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role.name,
      'photoUrl': photoUrl,
      'createdAt':
          createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }

  factory OccupierUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('User document is empty');
    }

    final roleValue = data['role'] as String? ?? UserRole.member.name;

    final role = UserRole.values.firstWhere(
      (value) => value.name == roleValue,
      orElse: () => UserRole.member,
    );

    final createdAtValue = data['createdAt'];

    return OccupierUser(
      uid: data['uid'] as String? ?? document.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: role,
      photoUrl: data['photoUrl'] as String?,
      createdAt:
          createdAtValue is Timestamp ? createdAtValue.toDate() : null,
    );
  }
}