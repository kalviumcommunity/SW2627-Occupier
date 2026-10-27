import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/user.dart';
import 'permission_service.dart';

class AdminUserRepository {
  AdminUserRepository({
    FirebaseFirestore? firestore,
    String? Function()? currentUserId,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _currentUserId =
           currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final FirebaseFirestore _firestore;
  final String? Function() _currentUserId;
  static const PermissionService _permissions = PermissionService();

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Stream<List<OccupierUser>> watchUsers() async* {
    await _requireAdministrator();
    yield* _users.snapshots().map((snapshot) {
      final users =
          snapshot.docs.map((document) {
            final user = OccupierUser.fromFirestore(document);
            if (user.uid != document.id) {
              throw FormatException(
                'User profile ID does not match its document ID.',
              );
            }
            return user;
          }).toList()..sort(
            (first, second) =>
                first.name.toLowerCase().compareTo(second.name.toLowerCase()),
          );
      return users;
    });
  }

  Future<void> updateUserRole({
    required String userId,
    required UserRole role,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    if (!UserRole.values.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported user role.');
    }

    final administratorId = await _requireAdministrator();
    if (userId == administratorId) {
      throw StateError('Administrators cannot change their own role.');
    }

    final userDocument = _users.doc(userId);
    final existingDocument = await userDocument.get();
    if (!existingDocument.exists) {
      throw StateError('The selected user no longer exists.');
    }

    final data = existingDocument.data();
    if (data == null) {
      throw StateError('The selected user profile is empty.');
    }

    final existingRole = UserRoleFirestoreValue.fromFirestoreValue(
      data['role'],
    );
    if (existingRole == role) return;

    if (existingRole == UserRole.admin && role != UserRole.admin) {
      final administrators = await _users
          .where('role', isEqualTo: UserRole.admin.name)
          .get();
      if (administrators.docs.length <= 1) {
        throw StateError('At least one administrator must remain.');
      }
    }

    await userDocument.update({'role': role.name});
  }

  Future<String> _requireAdministrator() async {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      throw StateError('Sign in with an administrator account to continue.');
    }

    final profile = await _users.doc(userId).get();
    if (!profile.exists) {
      throw StateError('The administrator profile is unavailable.');
    }

    final data = profile.data();
    if (data == null) {
      throw StateError('The administrator profile is empty.');
    }

    final role = UserRoleFirestoreValue.fromFirestoreValue(data['role']);
    if (!_permissions.canAssignRoles(role)) {
      throw StateError('Only administrators can manage user roles.');
    }

    return userId;
  }
}
