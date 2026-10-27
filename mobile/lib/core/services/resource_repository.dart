import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';

class ResourceRepository {
  ResourceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _branches =>
      _firestore.collection('branches');

  Stream<List<Branch>> watchBranches() {
    return _branches
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Branch.fromFirestore).toList());
  }

  Future<Branch?> getBranch(String branchId) async {
    final document = await _branches.doc(branchId).get();

    if (!document.exists) {
      return null;
    }

    return Branch.fromFirestore(document);
  }

  Future<String> createBranch(Branch branch) async {
    final document = _branches.doc();

    final data = branch.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();

    await document.set(data);

    return document.id;
  }

  Future<void> updateBranch(Branch branch) async {
    if (branch.id.trim().isEmpty) {
      throw ArgumentError.value(
        branch.id,
        'branch.id',
        'A branch ID is required to update a branch.',
      );
    }

    // Preserve the original creation timestamp.
    final data = branch.toFirestore()..remove('createdAt');

    await _branches.doc(branch.id).update(data);
  }

  Future<void> updateBranchStatus(String branchId, BranchStatus status) async {
    if (branchId.trim().isEmpty) {
      throw ArgumentError.value(
        branchId,
        'branchId',
        'A branch ID is required to update branch status.',
      );
    }

    await _branches.doc(branchId).update({'status': status.name});
  }

  // ---------------------------
  // Desks
  // ---------------------------

  Stream<List<Desk>> watchDesks(String branchId) {
    return _branches
        .doc(branchId)
        .collection('desks')
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Desk.fromFirestore).toList());
  }

  Future<String> createDesk(String branchId, Desk desk) async {
    final document = _branches.doc(branchId).collection('desks').doc();

    final data = desk.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();

    await document.set(data);

    return document.id;
  }

  Future<Desk?> getDesk(String branchId, String deskId) async {
    final document = await _branches
        .doc(branchId)
        .collection('desks')
        .doc(deskId)
        .get();

    if (!document.exists) {
      return null;
    }

    return Desk.fromFirestore(document);
  }

  Future<void> updateDeskStatus(
    String branchId,
    String deskId,
    DeskStatus status,
  ) async {
    if (branchId.trim().isEmpty || deskId.trim().isEmpty) {
      throw ArgumentError('Branch ID and desk ID are required.');
    }

    if (status == DeskStatus.occupied) {
      throw ArgumentError(
        'Use the check-in workflow to mark a desk as occupied.',
      );
    }

    final deskRef = _branches.doc(branchId).collection('desks').doc(deskId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(deskRef);

      if (!snapshot.exists) {
        throw StateError('Desk not found.');
      }

      final data = snapshot.data()!;
      final currentStatus =
          data['status'] as String? ?? DeskStatus.inactive.name;
      final activeOccupancyId = data['activeOccupancyId'] as String?;

      if (currentStatus == DeskStatus.occupied.name ||
          (activeOccupancyId != null && activeOccupancyId.trim().isNotEmpty)) {
        throw StateError(
          'Cannot change the status of a desk with an active occupancy.',
        );
      }

      transaction.update(deskRef, {'status': status.name});
    });
  }

  // ---------------------------
  // Meeting rooms
  // ---------------------------

  Stream<List<MeetingRoom>> watchMeetingRooms(String branchId) {
    return _branches
        .doc(branchId)
        .collection('rooms')
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(MeetingRoom.fromFirestore).toList(),
        );
  }

  Future<String> createMeetingRoom(String branchId, MeetingRoom room) async {
    final document = _branches.doc(branchId).collection('rooms').doc();

    final data = room.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();

    await document.set(data);

    return document.id;
  }

  Future<MeetingRoom?> getMeetingRoom(String branchId, String roomId) async {
    final document = await _branches
        .doc(branchId)
        .collection('rooms')
        .doc(roomId)
        .get();

    if (!document.exists) {
      return null;
    }

    return MeetingRoom.fromFirestore(document);
  }

  Future<void> updateMeetingRoomStatus(
    String branchId,
    String roomId,
    MeetingRoomStatus status,
  ) async {
    if (branchId.trim().isEmpty || roomId.trim().isEmpty) {
      throw ArgumentError('Branch ID and room ID are required.');
    }

    if (status == MeetingRoomStatus.occupied) {
      throw ArgumentError(
        'Use the check-in workflow to mark a room as occupied.',
      );
    }

    final roomRef = _branches.doc(branchId).collection('rooms').doc(roomId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(roomRef);

      if (!snapshot.exists) {
        throw StateError('Meeting room not found.');
      }

      final data = snapshot.data()!;
      final currentStatus =
          data['status'] as String? ?? MeetingRoomStatus.inactive.name;
      final activeOccupancyId = data['activeOccupancyId'] as String?;

      if (currentStatus == MeetingRoomStatus.occupied.name ||
          (activeOccupancyId != null && activeOccupancyId.trim().isNotEmpty)) {
        throw StateError(
          'Cannot change the status of a room with an active occupancy.',
        );
      }

      transaction.update(roomRef, {'status': status.name});
    });
  }
}
