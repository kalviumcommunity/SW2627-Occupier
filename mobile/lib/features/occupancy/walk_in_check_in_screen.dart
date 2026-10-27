import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_routes.dart';
import '../../core/services/occupancy_repository.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/resource_repository.dart';
import '../../core/services/user_repository.dart';
import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';
import '../../models/user.dart';

class WalkInCheckInScreen extends StatefulWidget {
  const WalkInCheckInScreen({
    super.key,
    this.resourceRepository,
    this.occupancyRepository,
    this.userRepository,
    this.currentUserId,
  });

  final ResourceRepository? resourceRepository;
  final OccupancyRepository? occupancyRepository;
  final UserRepository? userRepository;
  final String? Function()? currentUserId;

  @override
  State<WalkInCheckInScreen> createState() => _WalkInCheckInScreenState();
}

class _WalkInCheckInScreenState extends State<WalkInCheckInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  late final String? _userId;
  late final UserRepository _userRepository;
  late final ResourceRepository _resourceRepository;
  late final OccupancyRepository _occupancyRepository;
  late final Future<OccupierUser?> _profileFuture;
  late final Stream<List<Branch>> _branchesStream;

  String? _selectedBranchId;
  String? _selectedResourceKey;
  String? _message;
  bool _isSubmitting = false;
  bool _submissionSucceeded = false;

  @override
  void initState() {
    super.initState();
    _userId =
        widget.currentUserId?.call() ?? FirebaseAuth.instance.currentUser?.uid;
    _userRepository =
        widget.userRepository ?? UserRepository(currentUserId: () => _userId);
    _resourceRepository = widget.resourceRepository ?? ResourceRepository();
    _occupancyRepository = widget.occupancyRepository ?? OccupancyRepository();
    _profileFuture = _userId == null
        ? Future<OccupierUser?>.value(null)
        : _userRepository.getUser(_userId);
    _branchesStream = _resourceRepository.watchBranches();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OccupierUser?>(
      future: _profileFuture,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          return _messageScreen('Unable to load your access profile.');
        }
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = profileSnapshot.data;
        if (profile == null) {
          return _messageScreen('Your access profile is unavailable.');
        }
        if (!const PermissionService().canManageOccupancy(profile.role)) {
          return _messageScreen(
            'Walk-in check-in is available to authorized staff only.',
          );
        }

        return _buildBranchSelector(profile);
      },
    );
  }

  Widget _messageScreen(String message) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk-in check-in')),
      body: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }

  Widget _buildBranchSelector(OccupierUser profile) {
    return StreamBuilder<List<Branch>>(
      stream: _branchesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _messageScreen('Unable to load branches. Please try again.');
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text('Walk-in check-in')),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final branches = snapshot.data!
            .where((branch) => branch.status == BranchStatus.active)
            .where(
              (branch) =>
                  profile.role == UserRole.admin ||
                  branch.managerUid == _userId ||
                  branch.staffUids.contains(_userId),
            )
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Walk-in check-in'),
            leading: IconButton(
              tooltip: 'Back to dashboard',
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.dashboard),
            ),
          ),
          body: branches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No active branches are assigned to your account.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildAssignmentForm(branches),
        );
      },
    );
  }

  Widget _buildAssignmentForm(List<Branch> branches) {
    final branchIds = branches.map((branch) => branch.id).toSet();
    final selectedBranch = branches
        .where((branch) => branch.id == _selectedBranchId)
        .firstOrNull;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Register walk-in customer',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const ValueKey('walk-in-branch'),
            initialValue: branchIds.contains(_selectedBranchId)
                ? _selectedBranchId
                : null,
            decoration: const InputDecoration(labelText: 'Branch'),
            hint: const Text('Select a branch'),
            items: branches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
                )
                .toList(),
            onChanged: _isSubmitting
                ? null
                : (branchId) {
                    setState(() {
                      _selectedBranchId = branchId;
                      _selectedResourceKey = null;
                      _message = null;
                      _submissionSucceeded = false;
                    });
                  },
          ),
          const SizedBox(height: 16),
          if (selectedBranch == null)
            const Text('Select a branch to see available desks and rooms.')
          else
            _buildResources(selectedBranch),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('walk-in-customer-name'),
            controller: _customerNameController,
            decoration: const InputDecoration(labelText: 'Customer name'),
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            validator: (value) {
              final name = value?.trim() ?? '';
              if (name.isEmpty) {
                return 'Enter the customer name.';
              }
              if (name.length > 100) {
                return 'Name must be 100 characters or less.';
              }
              return null;
            },
            onChanged: (_) => _clearSubmissionState(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('walk-in-customer-phone'),
            controller: _customerPhoneController,
            decoration: const InputDecoration(labelText: 'Contact number'),
            keyboardType: TextInputType.phone,
            maxLength: 32,
            validator: (value) {
              final phone = value?.trim() ?? '';
              if (phone.length < 3 || phone.length > 32) {
                return 'Enter a contact number (3-32 characters).';
              }
              return null;
            },
            onChanged: (_) => _clearSubmissionState(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              key: const ValueKey('walk-in-result'),
              style: TextStyle(
                color: _submissionSucceeded
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('walk-in-submit'),
            onPressed:
                _isSubmitting ||
                    selectedBranch == null ||
                    _selectedResourceKey == null
                ? null
                : () => _submit(selectedBranch),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_isSubmitting ? 'Checking in...' : 'Check in walk-in'),
          ),
        ],
      ),
    );
  }

  Widget _buildResources(Branch branch) {
    return StreamBuilder<List<Desk>>(
      stream: _resourceRepository.watchDesks(branch.id),
      builder: (context, deskSnapshot) {
        if (deskSnapshot.hasError) {
          return const Text('Unable to load desks for this branch.');
        }
        if (!deskSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<List<MeetingRoom>>(
          stream: _resourceRepository.watchMeetingRooms(branch.id),
          builder: (context, roomSnapshot) {
            if (roomSnapshot.hasError) {
              return const Text(
                'Unable to load meeting rooms for this branch.',
              );
            }
            if (!roomSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final resources = <_AvailableResource>[
              for (final desk in deskSnapshot.data!)
                if (desk.status == DeskStatus.available)
                  _AvailableResource(
                    key: 'desk:${desk.id}',
                    id: desk.id,
                    type: 'desk',
                    name: desk.name,
                    details: 'Desk · Floor ${desk.floor}',
                  ),
              for (final room in roomSnapshot.data!)
                if (room.status == MeetingRoomStatus.available)
                  _AvailableResource(
                    key: 'room:${room.id}',
                    id: room.id,
                    type: 'room',
                    name: room.name,
                    details: 'Meeting room · Capacity ${room.capacity}',
                  ),
            ];

            if (resources.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No desks or meeting rooms are available.'),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available resources',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                RadioGroup<String>(
                  groupValue: _selectedResourceKey,
                  onChanged: (value) {
                    if (_isSubmitting) return;
                    setState(() {
                      _selectedResourceKey = value;
                      _message = null;
                      _submissionSucceeded = false;
                    });
                  },
                  child: Column(
                    children: [
                      for (final resource in resources)
                        RadioListTile<String>(
                          key: ValueKey('walk-in-resource-${resource.key}'),
                          value: resource.key,
                          title: Text(resource.name),
                          subtitle: Text(resource.details),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit(Branch branch) async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    final resourceKey = _selectedResourceKey;
    if (resourceKey == null) return;
    final separator = resourceKey.indexOf(':');
    if (separator <= 0 || separator == resourceKey.length - 1) return;
    final resourceType = resourceKey.substring(0, separator);
    if (resourceType != 'desk' && resourceType != 'room') return;
    final resourceId = resourceKey.substring(separator + 1);

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      await _occupancyRepository.createWalkInOccupancy(
        branchId: branch.id,
        resourceId: resourceId,
        resourceType: resourceType,
        customerName: _customerNameController.text,
        customerPhone: _customerPhoneController.text,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submissionSucceeded = true;
        _message = 'Walk-in checked in successfully.';
        _selectedResourceKey = null;
      });
      _customerNameController.clear();
      _customerPhoneController.clear();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submissionSucceeded = false;
        _message = _failureMessage(error);
      });
    }
  }

  void _clearSubmissionState() {
    if (_message != null || _submissionSucceeded) {
      setState(() {
        _message = null;
        _submissionSucceeded = false;
      });
    }
  }

  String _failureMessage(Object error) {
    if (error is StateError) return error.message.toString();
    return 'Unable to check in walk-in: $error';
  }
}

class _AvailableResource {
  const _AvailableResource({
    required this.key,
    required this.id,
    required this.type,
    required this.name,
    required this.details,
  });

  final String key;
  final String id;
  final String type;
  final String name;
  final String details;
}
