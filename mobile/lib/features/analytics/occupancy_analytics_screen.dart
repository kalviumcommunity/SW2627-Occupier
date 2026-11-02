import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/occupancy_repository.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/resource_repository.dart';
import '../../core/services/user_repository.dart';
import '../../models/branch.dart';
import '../../models/occupancy_analytics.dart';
import '../../models/user.dart';
import '../../services/occupancy_analytics_service.dart';

String? _analyticsCurrentUserId() => FirebaseAuth.instance.currentUser?.uid;

class OccupancyAnalyticsScreen extends StatefulWidget {
  const OccupancyAnalyticsScreen({
    super.key,
    this.currentUserId,
    this.userRepository,
    this.resourceRepository,
    this.occupancyRepository,
    this.clock,
  });

  final String? Function()? currentUserId;
  final UserRepository? userRepository;
  final ResourceRepository? resourceRepository;
  final OccupancyRepository? occupancyRepository;
  final DateTime Function()? clock;

  @override
  State<OccupancyAnalyticsScreen> createState() =>
      _OccupancyAnalyticsScreenState();
}

class _OccupancyAnalyticsScreenState extends State<OccupancyAnalyticsScreen> {
  late final String? _uid;
  late final UserRepository _userRepository;
  late final ResourceRepository _resourceRepository;
  late final OccupancyRepository _occupancyRepository;
  late final OccupancyAnalyticsService _analyticsService;
  late final Stream<OccupierUser?>? _profileStream;
  late Stream<List<Branch>> _branchesStream;
  OccupancyReportingPeriod _period = OccupancyReportingPeriod.daily;
  late DateTime _anchor;
  String? _selectedBranchId;
  Future<OccupancyAnalyticsReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _uid = (widget.currentUserId ?? _analyticsCurrentUserId)();
    _userRepository = widget.userRepository ?? UserRepository();
    _resourceRepository = widget.resourceRepository ?? ResourceRepository();
    _occupancyRepository = widget.occupancyRepository ?? OccupancyRepository();
    _analyticsService = OccupancyAnalyticsService(clock: widget.clock);
    _anchor = (widget.clock ?? DateTime.now)();
    final uid = _uid;
    _profileStream = uid == null || uid.isEmpty
        ? null
        : _userRepository.watchUser(uid);
    _branchesStream = _resourceRepository.watchBranches();
  }

  void _reload() {
    setState(() {
      _branchesStream = _resourceRepository.watchBranches();
      _reportFuture = null;
    });
  }

  Future<OccupancyAnalyticsReport> _loadReport(
    OccupancyDateRange range,
    List<Branch> branches,
    bool isAdmin,
  ) async {
    final selectedBranchId = _selectedBranchId;
    final branchScope = selectedBranchId != null
        ? [selectedBranchId]
        : isAdmin
        ? null
        : branches.map((branch) => branch.id).toList();

    final occupancies = branchScope == null
        ? await _occupancyRepository.fetchHistoricalOccupancies(
            start: range.start,
            end: range.end,
          )
        : (await Future.wait(
            branchScope.map(
              (branchId) => _occupancyRepository.fetchHistoricalOccupancies(
                start: range.start,
                end: range.end,
                branchId: branchId,
              ),
            ),
          )).expand((records) => records).toList();
    return _analyticsService.calculate(range: range, occupancies: occupancies);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null || uid.isEmpty || _profileStream == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view analytics.')),
      );
    }

    return StreamBuilder<OccupierUser?>(
      stream: _profileStream,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to load your access profile.')),
          );
        }
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = profileSnapshot.data;
        if (profile == null || profile.uid != uid) {
          return const Scaffold(
            body: Center(child: Text('Your profile is unavailable.')),
          );
        }
        if (!const PermissionService().canViewOccupancyAnalytics(
          profile.role,
        )) {
          return const Scaffold(
            body: Center(
              child: Text('Historical occupancy analytics are for staff only.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Occupancy Analytics')),
          body: StreamBuilder<List<Branch>>(
            stream: _branchesStream,
            builder: (context, branchSnapshot) {
              if (branchSnapshot.hasError) {
                return _AnalyticsMessage(
                  message: 'Unable to load branches.',
                  actionLabel: 'Try again',
                  onAction: _reload,
                );
              }
              if (!branchSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final isAdmin = const PermissionService().canViewNetworkOccupancy(
                profile.role,
              );
              final authorizedBranches = branchSnapshot.data!
                  .where(
                    (branch) =>
                        isAdmin ||
                        branch.managerUid == uid ||
                        branch.staffUids.contains(uid),
                  )
                  .toList();

              if (authorizedBranches.isEmpty) {
                return _AnalyticsMessage(
                  message: 'No branches are assigned to your account.',
                );
              }
              if (_selectedBranchId != null &&
                  !authorizedBranches.any(
                    (branch) => branch.id == _selectedBranchId,
                  )) {
                _selectedBranchId = null;
                _reportFuture = null;
              }

              final range = OccupancyDateRange.forPeriod(_period, _anchor);
              _reportFuture ??= _loadReport(range, authorizedBranches, isAdmin);
              return _buildAnalytics(
                authorizedBranches,
                isAdmin,
                range,
                _reportFuture!,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAnalytics(
    List<Branch> branches,
    bool isAdmin,
    OccupancyDateRange range,
    Future<OccupancyAnalyticsReport> report,
  ) {
    final localizations = MaterialLocalizations.of(context);
    final rangeText =
        '${localizations.formatMediumDate(range.start)} – '
        '${localizations.formatMediumDate(range.end.subtract(const Duration(days: 1)))}';
    final branchById = {for (final branch in branches) branch.id: branch};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<OccupancyReportingPeriod>(
          segments: const [
            ButtonSegment(
              value: OccupancyReportingPeriod.daily,
              label: Text('Day'),
            ),
            ButtonSegment(
              value: OccupancyReportingPeriod.weekly,
              label: Text('Week'),
            ),
            ButtonSegment(
              value: OccupancyReportingPeriod.monthly,
              label: Text('Month'),
            ),
          ],
          selected: {_period},
          onSelectionChanged: (selection) => setState(() {
            _period = selection.first;
            _reportFuture = null;
          }),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous period',
              onPressed: () => setState(() {
                _anchor = range.shift(_period, -1).start;
                _reportFuture = null;
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(child: Center(child: Text(rangeText))),
            IconButton(
              tooltip: 'Next period',
              onPressed: () => setState(() {
                _anchor = range.shift(_period, 1).start;
                _reportFuture = null;
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (isAdmin || branches.length > 1) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _selectedBranchId,
            decoration: const InputDecoration(labelText: 'Branch'),
            items: [
              if (isAdmin)
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All branches (network)'),
                ),
              for (final branch in branches)
                DropdownMenuItem<String?>(
                  value: branch.id,
                  child: Text(branch.name),
                ),
            ],
            onChanged: (value) => setState(() {
              _selectedBranchId = value;
              _reportFuture = null;
            }),
          ),
        ],
        const SizedBox(height: 16),
        FutureBuilder<OccupancyAnalyticsReport>(
          future: report,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _AnalyticsMessage(
                message: 'Unable to load historical occupancy data.',
                actionLabel: 'Try again',
                onAction: () => setState(() {
                  _reportFuture = null;
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final result = snapshot.data!;
            if (result.metrics.totalSessions == 0) {
              return const _AnalyticsMessage(
                message: 'No occupancy sessions in this reporting period.',
              );
            }
            return _ReportContent(
              report: result,
              branchesById: branchById,
              trendLabel: _period == OccupancyReportingPeriod.daily
                  ? 'Sessions by hour'
                  : 'Sessions by day',
            );
          },
        ),
      ],
    );
  }
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({
    required this.report,
    required this.branchesById,
    required this.trendLabel,
  });

  final OccupancyAnalyticsReport report;
  final Map<String, Branch> branchesById;
  final String trendLabel;

  @override
  Widget build(BuildContext context) {
    final metrics = report.metrics;
    final cards = [
      ('Total sessions', '${metrics.totalSessions}', Icons.event_available),
      ('Active sessions', '${metrics.activeSessions}', Icons.login),
      ('Completed sessions', '${metrics.completedSessions}', Icons.task_alt),
      (
        'Occupied resource-hours',
        metrics.occupiedResourceHours.toStringAsFixed(1),
        Icons.schedule,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: width,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(card.$3),
                            const SizedBox(height: 8),
                            Text(
                              card.$2,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(card.$1),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Desks: ${metrics.deskSessions} sessions · '
          '${metrics.deskResourceHours.toStringAsFixed(1)} resource-hours',
        ),
        Text(
          'Rooms: ${metrics.roomSessions} sessions · '
          '${metrics.roomResourceHours.toStringAsFixed(1)} room resource-hours '
          '(not seat-hours)',
        ),
        const SizedBox(height: 20),
        Text(trendLabel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Semantics(
          label: '$trendLabel chart',
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(
                report.trend
                    .map((bucket) => bucket.metrics.totalSessions)
                    .toList(),
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Resource-hours measure desk or room occupancy time. Room resource-hours '
          'are not occupied seat-hours. Historical capacity snapshots are not '
          'available, so utilization percentages cannot be calculated.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (report.branches.length > 1) ...[
          const SizedBox(height: 20),
          Text('Branch totals', style: Theme.of(context).textTheme.titleMedium),
          for (final branch in report.branches)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                branchesById[branch.branchId]?.name ?? branch.branchId,
              ),
              subtitle: Text(
                '${branch.metrics.totalSessions} sessions · '
                '${branch.metrics.occupiedResourceHours.toStringAsFixed(1)} '
                'resource-hours',
              ),
            ),
        ],
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.values, this.barColor, this.axisColor);

  final List<int> values;
  final Color barColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final bars = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;
    final baseline = size.height - 4;
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), axis);
    if (values.isEmpty) return;

    final maximum = values.fold<int>(0, (current, value) {
      return value > current ? value : current;
    });
    final slotWidth = size.width / values.length;
    final barWidth = slotWidth * 0.62;
    for (var index = 0; index < values.length; index++) {
      final height = maximum == 0
          ? 0.0
          : (baseline - 8) * values[index] / maximum;
      final left = index * slotWidth + (slotWidth - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, baseline - height, barWidth, height),
          const Radius.circular(3),
        ),
        bars,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      values != oldDelegate.values ||
      barColor != oldDelegate.barColor ||
      axisColor != oldDelegate.axisColor;
}

class _AnalyticsMessage extends StatelessWidget {
  const _AnalyticsMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
