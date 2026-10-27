import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user.dart';

void main() {
  group('OccupierUser', () {
    test('uses member as the default role', () {
      const user = OccupierUser(
        uid: 'user-123',
        name: 'Test User',
        email: 'test@example.com',
      );

      expect(user.role, UserRole.member);
      expect(user.photoUrl, isNull);
      expect(user.createdAt, isNull);
    });

    test('serializes user data for Firestore', () {
      final createdAt = DateTime(2026, 10, 13);

      final user = OccupierUser(
        uid: 'user-123',
        name: 'Test User',
        email: 'test@example.com',
        role: UserRole.branchManager,
        photoUrl: 'https://example.com/photo.png',
        createdAt: createdAt,
      );

      final data = user.toFirestore();

      expect(data['uid'], 'user-123');
      expect(data['name'], 'Test User');
      expect(data['email'], 'test@example.com');
      expect(data['role'], 'branchManager');
      expect(data['photoUrl'], 'https://example.com/photo.png');
      expect(data['createdAt'], Timestamp.fromDate(createdAt));
    });

    test('supports all defined roles', () {
      expect(UserRole.values, contains(UserRole.admin));
      expect(UserRole.values, contains(UserRole.branchManager));
      expect(UserRole.values, contains(UserRole.staff));
      expect(UserRole.values, contains(UserRole.member));
    });

    test('rejects missing and malformed role values', () {
      expect(
        () => UserRoleFirestoreValue.fromFirestoreValue(null),
        throwsFormatException,
      );
      expect(
        () => UserRoleFirestoreValue.fromFirestoreValue(12),
        throwsFormatException,
      );
      expect(
        () => UserRoleFirestoreValue.fromFirestoreValue('unknown'),
        throwsFormatException,
      );
    });
  });
}
