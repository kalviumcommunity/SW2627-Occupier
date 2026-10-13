import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<OccupierUser?> getUser(String uid) async {
    final document = await _users.doc(uid).get();

    if (!document.exists) {
      return null;
    }

    return OccupierUser.fromFirestore(document);
  }

  Future<void> saveUser(OccupierUser user) async {
    final document = _users.doc(user.uid);
    final existingDocument = await document.get();

    final data = user.toFirestore();

    if (existingDocument.exists) {
      data.remove('createdAt');
    } else {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await document.set(data, SetOptions(merge: true));
  }

  Future<void> updateProfile({
    required String uid,
    required String name,
    String? photoUrl,
  }) async {
    await _users.doc(uid).update({
      'name': name.trim(),
      'photoUrl': photoUrl,
    });
  }
}