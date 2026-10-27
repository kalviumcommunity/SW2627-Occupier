import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/constants/app_routes.dart';
import 'package:mobile/core/services/permission_service.dart';
import 'package:mobile/models/user.dart';

void main() {
  const permissions = PermissionService();

  group('PermissionService', () {
    test('requires an authenticated UID and limits profile access to self', () {
      expect(permissions.isAuthenticated(null), isFalse);
      expect(permissions.isAuthenticated(''), isFalse);
      expect(permissions.isAuthenticated('member-1'), isTrue);
      expect(
        permissions.canAccessOwnProfile(
          authenticatedUid: 'member-1',
          profileUid: 'member-1',
        ),
        isTrue,
      );
      expect(
        permissions.canAccessOwnProfile(
          authenticatedUid: 'member-1',
          profileUid: 'member-2',
        ),
        isFalse,
      );
      expect(
        permissions.canAccessOwnProfile(
          authenticatedUid: null,
          profileUid: 'member-1',
        ),
        isFalse,
      );
    });

    test('missing roles do not grant role permissions', () {
      expect(permissions.isOrdinaryUser(null), isFalse);
      expect(permissions.isAdministrator(null), isFalse);
      expect(permissions.canManageUsers(null), isFalse);
      expect(permissions.canViewOccupancy(null), isFalse);
      expect(permissions.canAssignRoles(null), isFalse);
      expect(permissions.isOrdinaryUser(UserRole.member), isTrue);
      expect(permissions.isAdministrator(UserRole.admin), isTrue);
    });

    test('only admin can manage branches and users', () {
      expect(permissions.canManageBranches(UserRole.admin), isTrue);
      expect(permissions.canManageUsers(UserRole.admin), isTrue);

      for (final role in [
        UserRole.branchManager,
        UserRole.staff,
        UserRole.member,
      ]) {
        expect(permissions.canManageBranches(role), isFalse);
        expect(permissions.canManageUsers(role), isFalse);
      }
    });

    test('only admin and branch manager can manage resources', () {
      expect(permissions.canManageResources(UserRole.admin), isTrue);
      expect(permissions.canManageResources(UserRole.branchManager), isTrue);
      expect(permissions.canManageResources(UserRole.staff), isFalse);
      expect(permissions.canManageResources(UserRole.member), isFalse);
    });

    test('only non-members can view occupancy', () {
      expect(permissions.canViewOccupancy(UserRole.admin), isTrue);
      expect(permissions.canViewOccupancy(UserRole.branchManager), isTrue);
      expect(permissions.canViewOccupancy(UserRole.staff), isTrue);
      expect(permissions.canViewOccupancy(UserRole.member), isFalse);
    });

    test('admin, branch manager and staff can manage occupancy', () {
      expect(permissions.canManageOccupancy(UserRole.admin), isTrue);
      expect(permissions.canManageOccupancy(UserRole.branchManager), isTrue);
      expect(permissions.canManageOccupancy(UserRole.staff), isTrue);
      expect(permissions.canManageOccupancy(UserRole.member), isFalse);
    });

    test('only admin and branch manager can manage bookings', () {
      expect(permissions.canManageBookings(UserRole.admin), isTrue);
      expect(permissions.canManageBookings(UserRole.branchManager), isTrue);
      expect(permissions.canManageBookings(UserRole.staff), isFalse);
      expect(permissions.canManageBookings(UserRole.member), isFalse);
    });

    test('all defined roles can create bookings', () {
      for (final role in UserRole.values) {
        expect(permissions.canCreateBooking(role), isTrue);
      }
    });

    test('all defined roles can view their own profile', () {
      for (final role in UserRole.values) {
        expect(permissions.canViewOwnProfile(role), isTrue);
      }
    });

    test('only admin can assign roles', () {
      expect(permissions.canAssignRoles(UserRole.admin), isTrue);
      expect(permissions.canAssignRoles(UserRole.branchManager), isFalse);
      expect(permissions.canAssignRoles(UserRole.staff), isFalse);
      expect(permissions.canAssignRoles(UserRole.member), isFalse);
    });

    test('maps protected routes to existing role policies', () {
      for (final role in UserRole.values) {
        expect(permissions.canAccessRoute(AppRoutes.dashboard, role), isTrue);
        expect(permissions.canAccessRoute(AppRoutes.branches, role), isTrue);
        expect(permissions.canAccessRoute(AppRoutes.bookings, role), isTrue);
        expect(permissions.canAccessRoute(AppRoutes.profile, role), isTrue);
        expect(permissions.canAccessRoute(AppRoutes.myBookings, role), isTrue);
        expect(
          permissions.canAccessRoute(AppRoutes.occupancy, role),
          permissions.canViewOccupancy(role),
        );
        expect(
          permissions.canAccessRoute(AppRoutes.desks, role),
          permissions.canManageResources(role),
        );
        expect(
          permissions.canAccessRoute(AppRoutes.meetingRooms, role),
          permissions.canManageResources(role),
        );
      }

      expect(permissions.canAccessRoute(AppRoutes.dashboard, null), isFalse);
      expect(permissions.canAccessRoute('/unknown', UserRole.admin), isFalse);
    });
  });
}
