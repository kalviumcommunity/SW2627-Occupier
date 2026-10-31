import '../../models/user.dart';
import '../constants/app_routes.dart';

/// Defines the actions available to each Occupier user role.
///
/// These are application-level checks. Firestore security rules must
/// independently enforce access to database operations.
class PermissionService {
  const PermissionService();

  bool isAuthenticated(String? uid) => uid != null && uid.isNotEmpty;

  bool canAccessOwnProfile({
    required String? authenticatedUid,
    required String profileUid,
  }) {
    return isAuthenticated(authenticatedUid) && authenticatedUid == profileUid;
  }

  bool isOrdinaryUser(UserRole? role) => role == UserRole.member;

  bool isAdministrator(UserRole? role) => role == UserRole.admin;

  bool canManageBranches(UserRole? role) {
    return role == UserRole.admin;
  }

  bool canManageUsers(UserRole? role) {
    return role == UserRole.admin;
  }

  bool canManageResources(UserRole? role) {
    return role == UserRole.admin || role == UserRole.branchManager;
  }

  bool canViewOccupancy(UserRole? role) {
    return role != null && role != UserRole.member;
  }

  bool canViewNetworkOccupancy(UserRole? role) => isAdministrator(role);

  bool canManageOccupancy(UserRole? role) {
    return role == UserRole.admin ||
        role == UserRole.branchManager ||
        role == UserRole.staff;
  }

  bool canManageBookings(UserRole? role) {
    return role == UserRole.admin || role == UserRole.branchManager;
  }

  bool canCreateBooking(UserRole? role) {
    return role == UserRole.member ||
        role == UserRole.admin ||
        role == UserRole.branchManager ||
        role == UserRole.staff;
  }

  bool canViewOwnProfile(UserRole? role) {
    return role != null && UserRole.values.contains(role);
  }

  bool canAssignRoles(UserRole? role) {
    return role == UserRole.admin;
  }

  bool canAccessRoute(String routeName, UserRole? role) {
    if (role == null || !UserRole.values.contains(role)) return false;

    return switch (routeName) {
      AppRoutes.dashboard || AppRoutes.branches => true,
      AppRoutes.bookings => canCreateBooking(role),
      AppRoutes.profile || AppRoutes.myBookings => canViewOwnProfile(role),
      AppRoutes.desks || AppRoutes.meetingRooms => canManageResources(role),
      AppRoutes.occupancy => canViewOccupancy(role),
      AppRoutes.walkInCheckIn => canManageOccupancy(role),
      AppRoutes.adminUserManagement => canManageUsers(role),
      _ => false,
    };
  }
}
