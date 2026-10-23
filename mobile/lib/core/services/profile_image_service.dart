import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class ProfileImageService {
  ProfileImageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String> uploadProfilePhoto({
    required String uid,
    required File imageFile,
  }) async {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'User ID cannot be empty.');
    }

    final storageRef = _storage.ref().child('profile_photos').child('$uid.jpg');

    final uploadTask = await storageRef.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return uploadTask.ref.getDownloadURL();
  }
}
