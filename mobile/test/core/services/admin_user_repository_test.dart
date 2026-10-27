import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/admin_user_repository.dart';
import 'package:mobile/models/user.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AdminUserRepository repository;
  late String? authenticatedUserId;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    authenticatedUserId = 'admin-1';
    await firestore.collection('users').doc('admin-1').set({
      'uid': 'admin-1',
      'name': 'Admin',
      'email': 'admin@example.com',
      'role': 'admin',
    });
    repository = AdminUserRepository(
      firestore: firestore,
      currentUserId: () => authenticatedUserId,
    );
  });

  test('administrator can view registered users in name order', () async {
    await firestore.collection('users').doc('member-2').set({
      'uid': 'member-2',
      'name': 'Zoe Member',
      'email': 'zoe@example.com',
      'role': 'member',
    });
    await firestore.collection('users').doc('member-1').set({
      'uid': 'member-1',
      'name': 'Alice Member',
      'email': 'alice@example.com',
      'role': 'staff',
    });

    final users = await repository.watchUsers().first;

    expect(users.map((user) => user.name), [
      'Admin',
      'Alice Member',
      'Zoe Member',
    ]);
    expect(users.last.email, 'zoe@example.com');
    expect(users[1].role, UserRole.staff);
  });

  test('a normal member cannot list registered users', () async {
    authenticatedUserId = 'member-1';
    await firestore.collection('users').doc('member-1').set({
      'uid': 'member-1',
      'name': 'Member',
      'email': 'member@example.com',
      'role': 'member',
    });

    await expectLater(
      repository.watchUsers().first,
      throwsA(isA<StateError>()),
    );
  });

  test(
    'administrator assigns a role without changing other profile fields',
    () async {
      final createdAt = DateTime.utc(2026, 1, 2);
      await firestore.collection('users').doc('member-1').set({
        'uid': 'member-1',
        'name': 'Member',
        'email': 'member@example.com',
        'role': 'member',
        'photoUrl': 'https://example.com/avatar.png',
        'createdAt': Timestamp.fromDate(createdAt),
      });

      await repository.updateUserRole(
        userId: 'member-1',
        role: UserRole.branchManager,
      );

      final profile = await firestore.collection('users').doc('member-1').get();
      expect(profile.data(), {
        'uid': 'member-1',
        'name': 'Member',
        'email': 'member@example.com',
        'role': 'branchManager',
        'photoUrl': 'https://example.com/avatar.png',
        'createdAt': Timestamp.fromDate(createdAt),
      });
    },
  );

  test('non-admin users cannot assign roles', () async {
    authenticatedUserId = 'member-1';
    await firestore.collection('users').doc('member-1').set({
      'uid': 'member-1',
      'name': 'Member',
      'email': 'member@example.com',
      'role': 'member',
    });
    await firestore.collection('users').doc('target').set({
      'uid': 'target',
      'name': 'Target',
      'email': 'target@example.com',
      'role': 'member',
    });

    await expectLater(
      repository.updateUserRole(userId: 'target', role: UserRole.staff),
      throwsA(isA<StateError>()),
    );
  });

  test('staff and branch managers cannot assign admin permissions', () async {
    for (final role in ['staff', 'branchManager']) {
      authenticatedUserId = 'manager-$role';
      await firestore.collection('users').doc(authenticatedUserId).set({
        'uid': authenticatedUserId,
        'name': 'Non-admin',
        'email': 'non-admin@example.com',
        'role': role,
      });

      await expectLater(
        repository.updateUserRole(userId: 'member-1', role: UserRole.admin),
        throwsA(isA<StateError>()),
      );
    }
  });

  test('rejects malformed stored roles before updating', () async {
    await firestore.collection('users').doc('target').set({
      'uid': 'target',
      'name': 'Target',
      'email': 'target@example.com',
      'role': 'superuser',
    });

    await expectLater(
      repository.updateUserRole(userId: 'target', role: UserRole.staff),
      throwsA(isA<FormatException>()),
    );
  });

  test('administrator cannot change their own role', () async {
    await expectLater(
      repository.updateUserRole(userId: 'admin-1', role: UserRole.member),
      throwsA(isA<StateError>()),
    );
  });
}
