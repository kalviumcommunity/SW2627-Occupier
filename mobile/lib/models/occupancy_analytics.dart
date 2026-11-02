enum OccupancyReportingPeriod { daily, weekly, monthly }

class OccupancyDateRange {
  const OccupancyDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  factory OccupancyDateRange.forPeriod(
    OccupancyReportingPeriod period,
    DateTime anchor,
  ) {
    final date = DateTime(anchor.year, anchor.month, anchor.day);
    final start = switch (period) {
      OccupancyReportingPeriod.daily => date,
      OccupancyReportingPeriod.weekly => DateTime(
        date.year,
        date.month,
        date.day - date.weekday + DateTime.monday,
      ),
      OccupancyReportingPeriod.monthly => DateTime(date.year, date.month),
    };
    final end = switch (period) {
      OccupancyReportingPeriod.daily => DateTime(
        start.year,
        start.month,
        start.day + 1,
      ),
      OccupancyReportingPeriod.weekly => DateTime(
        start.year,
        start.month,
        start.day + 7,
      ),
      OccupancyReportingPeriod.monthly => DateTime(start.year, start.month + 1),
    };
    return OccupancyDateRange(start: start, end: end);
  }

  OccupancyDateRange shift(OccupancyReportingPeriod period, int amount) {
    final shiftedStart = switch (period) {
      OccupancyReportingPeriod.daily => DateTime(
        start.year,
        start.month,
        start.day + amount,
      ),
      OccupancyReportingPeriod.weekly => DateTime(
        start.year,
        start.month,
        start.day + amount * 7,
      ),
      OccupancyReportingPeriod.monthly => DateTime(
        start.year,
        start.month + amount,
      ),
    };
    return OccupancyDateRange.forPeriod(period, shiftedStart);
  }
}

class OccupancyAnalyticsMetrics {
  const OccupancyAnalyticsMetrics({
    required this.totalSessions,
    required this.activeSessions,
    required this.completedSessions,
    required this.deskSessions,
    required this.roomSessions,
    required this.occupiedResourceHours,
    required this.deskResourceHours,
    required this.roomResourceHours,
  });

  const OccupancyAnalyticsMetrics.empty()
    : totalSessions = 0,
      activeSessions = 0,
      completedSessions = 0,
      deskSessions = 0,
      roomSessions = 0,
      occupiedResourceHours = 0,
      deskResourceHours = 0,
      roomResourceHours = 0;

  final int totalSessions;
  final int activeSessions;
  final int completedSessions;
  final int deskSessions;
  final int roomSessions;
  final double occupiedResourceHours;
  final double deskResourceHours;
  final double roomResourceHours;
}

class OccupancyAnalyticsBucket {
  const OccupancyAnalyticsBucket({required this.range, required this.metrics});

  final OccupancyDateRange range;
  final OccupancyAnalyticsMetrics metrics;
}

class OccupancyBranchAnalytics {
  const OccupancyBranchAnalytics({
    required this.branchId,
    required this.metrics,
  });

  final String branchId;
  final OccupancyAnalyticsMetrics metrics;
}

class OccupancyAnalyticsReport {
  const OccupancyAnalyticsReport({
    required this.range,
    required this.metrics,
    required this.branches,
    required this.trend,
  });

  final OccupancyDateRange range;
  final OccupancyAnalyticsMetrics metrics;
  final List<OccupancyBranchAnalytics> branches;
  final List<OccupancyAnalyticsBucket> trend;
}
