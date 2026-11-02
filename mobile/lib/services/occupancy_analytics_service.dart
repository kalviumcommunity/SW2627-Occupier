import '../models/occupancy.dart';
import '../models/occupancy_analytics.dart';

class OccupancyAnalyticsService {
  OccupancyAnalyticsService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  OccupancyAnalyticsReport calculate({
    required OccupancyDateRange range,
    required List<Occupancy> occupancies,
  }) {
    final now = _clock();
    final seenIds = <String>{};
    final total = _MutableMetrics();
    final branches = <String, _MutableMetrics>{};
    final buckets = _createBuckets(range);

    for (final occupancy in occupancies) {
      if (occupancy.occupancyId.isEmpty ||
          occupancy.branchId.isEmpty ||
          seenIds.contains(occupancy.occupancyId)) {
        continue;
      }

      final sessionEnd = _sessionEnd(occupancy, now);
      if (sessionEnd == null) continue;

      final clippedStart = _later(occupancy.checkInTime, range.start);
      final clippedEnd = _earlier(sessionEnd, range.end);
      if (!clippedEnd.isAfter(clippedStart)) continue;

      seenIds.add(occupancy.occupancyId);
      total.add(occupancy, clippedEnd.difference(clippedStart));
      branches
          .putIfAbsent(occupancy.branchId, _MutableMetrics.new)
          .add(occupancy, clippedEnd.difference(clippedStart));

      for (final bucket in buckets) {
        final bucketStart = _later(clippedStart, bucket.range.start);
        final bucketEnd = _earlier(clippedEnd, bucket.range.end);
        if (bucketEnd.isAfter(bucketStart)) {
          bucket.metrics.add(occupancy, bucketEnd.difference(bucketStart));
        }
      }
    }

    final branchReports =
        branches.entries
            .map(
              (entry) => OccupancyBranchAnalytics(
                branchId: entry.key,
                metrics: entry.value.freeze(),
              ),
            )
            .toList()
          ..sort((left, right) => left.branchId.compareTo(right.branchId));

    return OccupancyAnalyticsReport(
      range: range,
      metrics: total.freeze(),
      branches: branchReports,
      trend: buckets
          .map(
            (bucket) => OccupancyAnalyticsBucket(
              range: bucket.range,
              metrics: bucket.metrics.freeze(),
            ),
          )
          .toList(),
    );
  }

  DateTime? _sessionEnd(Occupancy occupancy, DateTime now) {
    final checkOut = occupancy.checkOutTime;
    if (occupancy.status == OccupancyStatus.active && checkOut != null) {
      return null;
    }
    if (occupancy.status == OccupancyStatus.completed && checkOut == null) {
      return null;
    }
    if (checkOut != null && !checkOut.isAfter(occupancy.checkInTime)) {
      return null;
    }

    final end = checkOut ?? now;
    return _earlier(end, now);
  }

  List<_MutableBucket> _createBuckets(OccupancyDateRange range) {
    final buckets = <_MutableBucket>[];
    var start = range.start;
    final isDailyRange = range.end.difference(range.start).inDays <= 1;
    while (start.isBefore(range.end)) {
      final next = isDailyRange
          ? DateTime(start.year, start.month, start.day, start.hour + 1)
          : DateTime(start.year, start.month, start.day + 1);
      final end = _earlier(next, range.end);
      buckets.add(
        _MutableBucket(
          range: OccupancyDateRange(start: start, end: end),
        ),
      );
      start = end;
    }
    return buckets;
  }

  DateTime _later(DateTime left, DateTime right) =>
      left.isAfter(right) ? left : right;

  DateTime _earlier(DateTime left, DateTime right) =>
      left.isBefore(right) ? left : right;
}

class _MutableBucket {
  _MutableBucket({required this.range});

  final OccupancyDateRange range;
  final _MutableMetrics metrics = _MutableMetrics();
}

class _MutableMetrics {
  int totalSessions = 0;
  int activeSessions = 0;
  int completedSessions = 0;
  int deskSessions = 0;
  int roomSessions = 0;
  double occupiedResourceHours = 0;
  double deskResourceHours = 0;
  double roomResourceHours = 0;

  void add(Occupancy occupancy, Duration duration) {
    final hours = duration.inMicroseconds / Duration.microsecondsPerHour;
    totalSessions++;
    occupiedResourceHours += hours;
    if (occupancy.status == OccupancyStatus.active) {
      activeSessions++;
    } else {
      completedSessions++;
    }

    if (occupancy.resourceType == 'desk') {
      deskSessions++;
      deskResourceHours += hours;
    } else if (occupancy.resourceType == 'room') {
      roomSessions++;
      roomResourceHours += hours;
    }
  }

  OccupancyAnalyticsMetrics freeze() => OccupancyAnalyticsMetrics(
    totalSessions: totalSessions,
    activeSessions: activeSessions,
    completedSessions: completedSessions,
    deskSessions: deskSessions,
    roomSessions: roomSessions,
    occupiedResourceHours: occupiedResourceHours,
    deskResourceHours: deskResourceHours,
    roomResourceHours: roomResourceHours,
  );
}
