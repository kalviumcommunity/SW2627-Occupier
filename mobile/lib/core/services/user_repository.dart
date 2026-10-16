import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'permission_service.dart';
import '../../models/user.dart';

class UserRepository {
  UserRepository({
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

  Future<OccupierUser?> getUser(String uid) async {
    _requireOwnProfile(uid);
    final document = await _users.doc(uid).get();

    if (!document.exists) {
      return null;
    }

    return OccupierUser.fromFirestore(document);
  }

  Future<void> saveUser(OccupierUser user) async {
    _requireOwnProfile(user.uid);
    final document = _users.doc(user.uid);
    final existingDocument = await document.get();

    if (existingDocument.exists) {
      final existingData = existingDocument.data()!;
      final existingRole = UserRoleFirestoreValue.fromFirestoreValue(
        existingData['role'],
      );

      if (user.role != existingRole) {
        throw StateError('Profile roles can only be changed by an admin.');
      }

      await document.update({
        'name': user.name.trim(),
        'photoUrl': user.photoUrl,
      });
      return;
    }

    if (user.role != UserRole.member) {
      throw StateError('New profiles must use the member role.');
    }

    final data = user.toFirestore()
      ..['name'] = user.name.trim()
      ..['role'] = UserRole.member.name
      ..['createdAt'] = FieldValue.serverTimestamp();

    await document.set(data, SetOptions(merge: true));
  }

  Future<void> updateProfile({
    required String uid,
    required String name,
    String? photoUrl,
  }) async {
    _requireOwnProfile(uid);

    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName.length > 100) {
      throw ArgumentError.value(name, 'name', 'Must be 1-100 characters.');
    }
    if (photoUrl != null && photoUrl.length > 2048) {
      throw ArgumentError.value(
        photoUrl,
        'photoUrl',
        'Must be at most 2048 characters.',
      );
    }

    final updates = <String, Object?>{'name': trimmedName};
    if (photoUrl != null) {
      updates['photoUrl'] = photoUrl;
    }

    await _users.doc(uid).update(updates);
  }

  void _requireOwnProfile(String uid) {
    if (!_permissions.canAccessOwnProfile(
      authenticatedUid: _currentUserId(),
      profileUid: uid,
    )) {
      throw StateError('You can access only your own profile.');
    }
  }
}
