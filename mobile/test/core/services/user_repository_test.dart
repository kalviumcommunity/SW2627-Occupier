import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/user_repository.dart';
import 'package:mobile/models/user.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repository;
  late String? authenticatedUserId;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    authenticatedUserId = 'user-123';
    repository = UserRepository(
      firestore: firestore,
      currentUserId: () => authenticatedUserId,
    );
  });

  const testUser = OccupierUser(
    uid: 'user-123',
    name: 'Test User',
    email: 'test@example.com',
    role: UserRole.member,
  );

  group('UserRepository', () {
    test('saves and retrieves a user profile', () async {
      await repository.saveUser(testUser);

      final user = await repository.getUser('user-123');

      expect(user, isNotNull);
      expect(user!.uid, 'user-123');
      expect(user.name, 'Test User');
      expect(user.email, 'test@example.com');
      expect(user.role, UserRole.member);
    });

    test('creates a missing profile with the member role', () async {
      await repository.ensureUserProfile(testUser);

      final user = await repository.getUser('user-123');

      expect(user, isNotNull);
      expect(user!.role, UserRole.member);
      expect(user.name, 'Test User');
      expect(user.email, 'test@example.com');
    });

    test('does not overwrite an existing profile or role', () async {
      await firestore.collection('users').doc('user-123').set({
        'uid': 'user-123',
        'name': 'Existing Admin',
        'email': 'admin@example.com',
        'role': 'admin',
      });

      await repository.ensureUserProfile(testUser);

      final document = await firestore
          .collection('users')
          .doc('user-123')
          .get();

      expect(document.data()!['name'], 'Existing Admin');
      expect(document.data()!['email'], 'admin@example.com');
      expect(document.data()!['role'], 'admin');
    });

    test('returns null for a missing user', () async {
      authenticatedUserId = 'missing-user';
      final user = await repository.getUser('missing-user');

      expect(user, isNull);
    });

    test('does not allow reading another user profile', () async {
      await expectLater(
        repository.getUser('other-user'),
        throwsA(isA<StateError>()),
      );
    });

    test('updates a user profile', () async {
      await repository.saveUser(testUser);

      await repository.updateProfile(
        uid: 'user-123',
        name: 'Updated User',
        photoUrl: 'https://example.com/photo.png',
      );

      final user = await repository.getUser('user-123');

      expect(user, isNotNull);
      expect(user!.name, 'Updated User');
      expect(user.photoUrl, 'https://example.com/photo.png');
    });

    test('preserves the photo URL when only the name is changed', () async {
      await repository.saveUser(
        const OccupierUser(
          uid: 'user-123',
          name: 'Test User',
          email: 'test@example.com',
          photoUrl: 'https://example.com/photo.png',
        ),
      );

      await repository.updateProfile(uid: 'user-123', name: 'Updated User');

      final user = await repository.getUser('user-123');
      expect(user!.photoUrl, 'https://example.com/photo.png');
    });

    test('preserves createdAt when saving an existing profile', () async {
      await repository.saveUser(testUser);

      final before = await firestore.collection('users').doc('user-123').get();

      await repository.saveUser(
        const OccupierUser(
          uid: 'user-123',
          name: 'Updated Name',
          email: 'test@example.com',
        ),
      );

      final after = await firestore.collection('users').doc('user-123').get();

      expect(after.data()!['createdAt'], before.data()!['createdAt']);
    });

    test('does not allow changing the stored role through saveUser', () async {
      await repository.saveUser(testUser);

      await expectLater(
        repository.saveUser(
          const OccupierUser(
            uid: 'user-123',
            name: 'Test User',
            email: 'test@example.com',
            role: UserRole.admin,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('does not allow profile updates when signed out', () async {
      authenticatedUserId = null;

      await expectLater(
        repository.updateProfile(uid: 'user-123', name: 'Updated User'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
