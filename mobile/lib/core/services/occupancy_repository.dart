import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/occupancy.dart';

class OccupancyRepository {
  OccupancyRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _occupancies =>
      _firestore.collection('occupancies');

  DocumentReference<Map<String, dynamic>> _resourceDocument({
    required String branchId,
    required String resourceId,
    required String resourceType,
  }) {
    final collectionName = switch (resourceType) {
      'desk' => 'desks',
      'room' => 'rooms',
      _ => throw ArgumentError('resourceType must be "desk" or "room".'),
    };

    return _firestore
        .collection('branches')
        .doc(branchId)
        .collection(collectionName)
        .doc(resourceId);
  }

  // Check in a user and mark the resource occupied atomically.
  Future<String> createWalkInOccupancy({
    required String branchId,
    required String resourceId,
    required String resourceType,
    required String customerName,
    required String customerPhone,
  }) {
    final occupancyRef = _occupancies.doc();
    final name = customerName.trim();
    final phone = customerPhone.trim();

    if (name.isEmpty || name.length > 100) {
      throw ArgumentError.value(
        customerName,
        'customerName',
        'Must be 1-100 characters.',
      );
    }
    if (phone.length < 3 || phone.length > 32) {
      throw ArgumentError.value(
        customerPhone,
        'customerPhone',
        'Must be 3-32 characters.',
      );
    }

    return _createOccupancy(
      Occupancy(
        occupancyId: occupancyRef.id,
        branchId: branchId,
        resourceId: resourceId,
        resourceType: resourceType,
        userId: 'walk-in-${occupancyRef.id}',
        status: OccupancyStatus.active,
        checkInTime: DateTime.now(),
        source: OccupancySource.walkIn,
        createdAt: DateTime.now(),
        customerName: name,
        customerPhone: phone,
      ),
      occupancyRef,
    );
  }

  Future<String> createOccupancy(Occupancy occupancy) {
    return _createOccupancy(occupancy, _occupancies.doc());
  }

  Future<String> _createOccupancy(
    Occupancy occupancy,
    DocumentReference<Map<String, dynamic>> occupancyRef,
  ) async {
    if (occupancy.branchId.isEmpty ||
        occupancy.resourceId.isEmpty ||
        occupancy.userId.isEmpty) {
      throw ArgumentError('Branch, resource, and user IDs are required.');
    }
    if (occupancy.source == OccupancySource.walkIn &&
        (occupancy.customerName == null ||
            occupancy.customerPhone == null ||
            occupancy.customerName!.trim().isEmpty ||
            occupancy.customerName!.trim().length > 100 ||
            occupancy.customerPhone!.trim().length < 3 ||
            occupancy.customerPhone!.trim().length > 32)) {
      throw ArgumentError('Walk-ins require a valid name and contact number.');
    }

    final resourceRef = _resourceDocument(
      branchId: occupancy.branchId,
      resourceId: occupancy.resourceId,
      resourceType: occupancy.resourceType,
    );

    await _firestore.runTransaction((transaction) async {
      // Read before writing.
      final resourceSnapshot = await transaction.get(resourceRef);

      if (!resourceSnapshot.exists) {
        throw StateError('Resource not found.');
      }

      final resourceData = resourceSnapshot.data()!;
      final status = resourceData['status'];

      if (status != 'available') {
        throw StateError('This resource is not available for check-in.');
      }

      transaction.update(resourceRef, {
        'status': 'occupied',
        'activeOccupancyId': occupancyRef.id,
      });

      final occupancyData = <String, dynamic>{
        'occupancyId': occupancyRef.id,
        'branchId': occupancy.branchId,
        'resourceId': occupancy.resourceId,
        'resourceType': occupancy.resourceType,
        'userId': occupancy.userId,
        'bookingId': occupancy.bookingId,
        'status': OccupancyStatus.active.name,
        'checkInTime': FieldValue.serverTimestamp(),
        'checkOutTime': null,
        'source': occupancy.source.name,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (occupancy.source == OccupancySource.walkIn) {
        occupancyData['customerName'] = occupancy.customerName!.trim();
        occupancyData['customerPhone'] = occupancy.customerPhone!.trim();
      }
      transaction.set(occupancyRef, occupancyData);
    });

    return occupancyRef.id;
  }

  // Filter active occupancy records by branch or owner when needed.
  Stream<List<Occupancy>> watchActiveOccupancies({
    String? branchId,
    String? userId,
  }) {
    Query<Map<String, dynamic>> query = _occupancies.where(
      'status',
      isEqualTo: OccupancyStatus.active.name,
    );

    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }
    if (branchId != null) {
      query = query.where('branchId', isEqualTo: branchId);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs.map(_fromFirestore).toList(),
    );
  }

  Future<List<Occupancy>> fetchHistoricalOccupancies({
    required DateTime start,
    required DateTime end,
    String? branchId,
    int pageSize = 200,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('The analytics end must be after its start.');
    }
    if (pageSize < 1 || pageSize > 500) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be 1-500.');
    }

    final startTimestamp = Timestamp.fromDate(start);
    final endTimestamp = Timestamp.fromDate(end);
    Query<Map<String, dynamic>> activeQuery = _occupancies
        .where('status', isEqualTo: OccupancyStatus.active.name)
        .where('checkInTime', isLessThan: endTimestamp)
        .orderBy('checkInTime');
    Query<Map<String, dynamic>> completedQuery = _occupancies
        .where('status', isEqualTo: OccupancyStatus.completed.name)
        .where('checkOutTime', isGreaterThan: startTimestamp)
        .where('checkInTime', isLessThan: endTimestamp)
        .orderBy('checkOutTime')
        .orderBy('checkInTime');

    if (branchId != null) {
      if (branchId.trim().isEmpty) {
        throw ArgumentError.value(branchId, 'branchId', 'Must not be empty.');
      }
      activeQuery = activeQuery.where('branchId', isEqualTo: branchId);
      completedQuery = completedQuery.where('branchId', isEqualTo: branchId);
    }

    final pages = await Future.wait([
      _readAllPages(activeQuery, pageSize),
      _readAllPages(completedQuery, pageSize),
    ]);
    return pages
        .expand((page) => page)
        .map(_tryFromAnalyticsFirestore)
        .whereType<Occupancy>()
        .toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _readAllPages(
    Query<Map<String, dynamic>> query,
    int pageSize,
  ) async {
    final documents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument;

    while (true) {
      var pageQuery = query.limit(pageSize);
      if (lastDocument != null) {
        pageQuery = pageQuery.startAfterDocument(lastDocument);
      }
      final page = await pageQuery.get();
      documents.addAll(page.docs);
      if (page.docs.length < pageSize) return documents;
      lastDocument = page.docs.last;
    }
  }

  Occupancy? _tryFromAnalyticsFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final branchId = data['branchId'];
    final resourceId = data['resourceId'];
    final resourceType = data['resourceType'];
    final userId = data['userId'];
    final statusName = data['status'];
    final sourceName = data['source'];
    final checkInTime = _analyticsDate(data['checkInTime']);
    final checkOutValue = data['checkOutTime'];
    final checkOutTime = checkOutValue == null
        ? null
        : _analyticsDate(checkOutValue);

    if (branchId is! String ||
        branchId.isEmpty ||
        resourceId is! String ||
        resourceId.isEmpty ||
        resourceType is! String ||
        (resourceType != 'desk' && resourceType != 'room') ||
        userId is! String ||
        userId.isEmpty ||
        checkInTime == null ||
        (checkOutValue != null && checkOutTime == null)) {
      return null;
    }

    final status = OccupancyStatus.values.where(
      (value) => value.name == statusName,
    );
    final source = OccupancySource.values.where(
      (value) => value.name == sourceName,
    );
    if (status.isEmpty || source.isEmpty) return null;

    return Occupancy(
      occupancyId: document.id,
      branchId: branchId,
      resourceId: resourceId,
      resourceType: resourceType,
      userId: userId,
      bookingId: data['bookingId'] is String
          ? data['bookingId'] as String
          : null,
      status: status.first,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      source: source.first,
      createdAt: _analyticsDate(data['createdAt']) ?? checkInTime,
    );
  }

  DateTime? _analyticsDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  // Check out a user and release the resource atomically.
  Future<void> checkOut(String occupancyId) async {
    final occupancyRef = _occupancies.doc(occupancyId);

    await _firestore.runTransaction((transaction) async {
      // Read the occupancy before writing.
      final occupancySnapshot = await transaction.get(occupancyRef);

      if (!occupancySnapshot.exists) {
        throw StateError('Occupancy record not found.');
      }

      final data = occupancySnapshot.data()!;

      if (data['status'] != OccupancyStatus.active.name) {
        throw StateError('This occupancy is not active.');
      }

      final resourceRef = _resourceDocument(
        branchId: data['branchId'] as String,
        resourceId: data['resourceId'] as String,
        resourceType: data['resourceType'] as String,
      );

      // Read the resource before writing.
      final resourceSnapshot = await transaction.get(resourceRef);

      if (!resourceSnapshot.exists) {
        throw StateError('Resource not found.');
      }

      if (resourceSnapshot.data()?['status'] != 'occupied') {
        throw StateError(
          'Resource status is inconsistent. Please investigate.',
        );
      }
      if (resourceSnapshot.data()?['activeOccupancyId'] != occupancyId) {
        throw StateError(
          'Resource is not assigned to this occupancy. Please investigate.',
        );
      }

      transaction.update(occupancyRef, {
        'status': OccupancyStatus.completed.name,
        'checkOutTime': FieldValue.serverTimestamp(),
      });

      transaction.update(resourceRef, {
        'status': 'available',
        'activeOccupancyId': null,
      });
    });
  }

  Occupancy _fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    return Occupancy(
      occupancyId: document.id,
      branchId: data['branchId'] as String,
      resourceId: data['resourceId'] as String,
      resourceType: data['resourceType'] as String,
      userId: data['userId'] as String,
      bookingId: data['bookingId'] as String?,
      status: OccupancyStatus.values.firstWhere(
        (value) => value.name == data['status'],
      ),
      checkInTime: (data['checkInTime'] as Timestamp).toDate(),
      checkOutTime: (data['checkOutTime'] as Timestamp?)?.toDate(),
      source: OccupancySource.values.firstWhere(
        (value) => value.name == data['source'],
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      customerName: data['customerName'] as String?,
      customerPhone: data['customerPhone'] as String?,
    );
  }
}
