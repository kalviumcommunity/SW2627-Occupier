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

    await _firestore.runTransaction((transaction) async {
      final existingDocument = await transaction.get(document);

      if (existingDocument.exists) {
        final existingData = existingDocument.data();
        if (existingData == null) {
          throw StateError('User profile is empty.');
        }

        final existingRole = UserRoleFirestoreValue.fromFirestoreValue(
          existingData['role'],
        );

        if (user.role != existingRole) {
          throw StateError('Profile roles can only be changed by an admin.');
        }

        transaction.update(document, {
          'name': user.name.trim(),
          'photoUrl': user.photoUrl,
        });
        return;
      }

      if (user.role != UserRole.member) {
        throw StateError('New profiles must use the member role.');
      }

      transaction.set(document, _newProfileData(user));
    });
  }

  Future<void> ensureUserProfile(OccupierUser user) async {
    _requireOwnProfile(user.uid);
    if (user.role != UserRole.member) {
      throw StateError('New profiles must use the member role.');
    }

    final document = _users.doc(user.uid);
    final data = _newProfileData(user);

    await _firestore.runTransaction((transaction) async {
      final existingDocument = await transaction.get(document);
      if (!existingDocument.exists) {
        transaction.set(document, data);
      }
    });
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

  Map<String, dynamic> _newProfileData(OccupierUser user) {
    final name = user.name.trim();
    final email = user.email.trim();

    if (name.isEmpty || name.length > 100) {
      throw ArgumentError.value(user.name, 'name', 'Must be 1-100 characters.');
    }
    if (email.isEmpty || email.length > 254) {
      throw ArgumentError.value(
        user.email,
        'email',
        'Must be 1-254 characters.',
      );
    }
    if (user.photoUrl != null && user.photoUrl!.length > 2048) {
      throw ArgumentError.value(
        user.photoUrl,
        'photoUrl',
        'Must be at most 2048 characters.',
      );
    }

    return user.toFirestore()
      ..['name'] = name
      ..['email'] = email
      ..['role'] = UserRole.member.name
      ..['createdAt'] = FieldValue.serverTimestamp();
  }
}
