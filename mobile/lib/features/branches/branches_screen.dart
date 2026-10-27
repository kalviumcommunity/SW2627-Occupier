import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_routes.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/resource_repository.dart';
import '../../core/services/user_repository.dart';
import '../../models/branch.dart';
import '../../models/user.dart';
import 'branch_form_dialog.dart';
import 'branch_resources_screen.dart';

String? _firebaseCurrentUserId() => FirebaseAuth.instance.currentUser?.uid;

class BranchesScreen extends StatefulWidget {
  BranchesScreen({
    super.key,
    ResourceRepository? repository,
    UserRepository? userRepository,
    String? Function()? currentUserId,
  }) : _repository = repository ?? ResourceRepository(),
       _userRepository = userRepository ?? UserRepository(),
       _currentUserId = currentUserId ?? _firebaseCurrentUserId;

  final ResourceRepository _repository;
  final UserRepository _userRepository;
  final String? Function() _currentUserId;

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  late final String? _uid;
  late final Future<OccupierUser?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _uid = widget._currentUserId();
    _profileFuture = _uid == null
        ? Future<OccupierUser?>.value(null)
        : widget._userRepository.getUser(_uid);
  }

  Future<void> _showBranchForm({Branch? branch}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          BranchFormDialog(repository: widget._repository, branch: branch),
    );

    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          branch == null
              ? 'Branch created successfully.'
              : 'Branch updated successfully.',
        ),
      ),
    );
  }

  Future<void> _toggleBranchStatus(Branch branch) async {
    final nextStatus = branch.status == BranchStatus.active
        ? BranchStatus.inactive
        : BranchStatus.active;
    final action = nextStatus == BranchStatus.inactive
        ? 'deactivate'
        : 'activate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${action == 'deactivate' ? 'Deactivate' : 'Activate'} branch?',
        ),
        content: Text('Are you sure you want to $action "${branch.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action == 'deactivate' ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget._repository.updateBranchStatus(branch.id, nextStatus);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == BranchStatus.active
                ? 'Branch activated successfully.'
                : 'Branch deactivated successfully.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update branch status. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OccupierUser?>(
      future: _profileFuture,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Branches')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (profileSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Branches')),
            body: const Center(
              child: Text('Unable to load your access profile.'),
            ),
          );
        }

        final profile = profileSnapshot.data;
        if (_uid == null || profile == null || profile.uid != _uid) {
          return Scaffold(
            appBar: AppBar(title: const Text('Branches')),
            body: const Center(
              child: Text('Sign in with a valid Occupier profile to continue.'),
            ),
          );
        }

        const permissions = PermissionService();
        final canManageBranches = permissions.canManageBranches(profile.role);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Branches'),
            actions: [
              if (canManageBranches)
                IconButton(
                  tooltip: 'Create branch',
                  icon: const Icon(Icons.add_business),
                  onPressed: _showBranchForm,
                ),
              IconButton(
                tooltip: 'Book a resource',
                icon: const Icon(Icons.add_task),
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.bookings);
                },
              ),
            ],
          ),
          body: StreamBuilder<List<Branch>>(
            stream: widget._repository.watchBranches(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Unable to load branches. Please try again.'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final branches = snapshot.data!;

              if (branches.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.apartment, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No branches yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        canManageBranches
                            ? 'Use Create branch to add the first branch.'
                            : 'Branches will appear here when added.',
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: branches.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final branch = branches[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: const CircleAvatar(child: Icon(Icons.apartment)),
                      title: Text(
                        branch.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${branch.address}, ${branch.city}\n'
                          '${branch.totalDeskCapacity} desks · '
                          '${branch.totalRoomCapacity} meeting rooms\n'
                          'Status: ${branch.status.name}',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canManageBranches)
                            PopupMenuButton<_BranchAction>(
                              tooltip: 'Manage ${branch.name}',
                              onSelected: (action) {
                                switch (action) {
                                  case _BranchAction.edit:
                                    _showBranchForm(branch: branch);
                                  case _BranchAction.toggleStatus:
                                    _toggleBranchStatus(branch);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: _BranchAction.edit,
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Edit branch',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _BranchAction.toggleStatus,
                                  child: Row(
                                    children: [
                                      Icon(
                                        branch.status == BranchStatus.active
                                            ? Icons.pause_circle_outline
                                            : Icons.play_circle_outline,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          branch.status == BranchStatus.active
                                              ? 'Deactivate branch'
                                              : 'Activate branch',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BranchResourcesScreen(
                              branch: branch,
                              repository: widget._repository,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

enum _BranchAction { edit, toggleStatus }
