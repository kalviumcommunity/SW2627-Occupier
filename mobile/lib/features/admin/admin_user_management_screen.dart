import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/admin_user_repository.dart';
import '../../models/user.dart';

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key, this.repository});

  final AdminUserRepository? repository;

  @override
  State<AdminUserManagementScreen> createState() =>
      _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  late final AdminUserRepository _repository;
  late Stream<List<OccupierUser>> _users;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AdminUserRepository();
    _users = _repository.watchUsers();
  }

  void _retry() {
    setState(() {
      _users = _repository.watchUsers();
    });
  }

  Future<void> _changeRole(OccupierUser user) async {
    final selectedRole = await showDialog<UserRole>(
      context: context,
      builder: (context) {
        var role = user.role;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm role change'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change ${user.name} from ${_roleName(user.role)} to '
                  '${_roleName(role)}?',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'New role'),
                  items: UserRole.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_roleName(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => role = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: role == user.role
                    ? null
                    : () => Navigator.pop(context, role),
                child: const Text('Save role'),
              ),
            ],
          ),
        );
      },
    );

    if (selectedRole == null || !mounted) return;

    try {
      await _repository.updateUserRole(userId: user.uid, role: selectedRole);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${user.name} is now assigned the ${_roleName(selectedRole)} role.',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } on FirebaseException catch (error) {
      if (!mounted) return;
      final message = error.code == 'permission-denied'
          ? 'Permission denied. Your administrator access may have changed.'
          : 'Unable to save the role. Check your connection and try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save the role. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User management')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search users',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.trim().toLowerCase());
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<OccupierUser>>(
              stream: _users,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unable to load registered users.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data ?? const <OccupierUser>[];
                if (users.isEmpty) {
                  return const Center(
                    child: Text('No registered users found.'),
                  );
                }

                final filteredUsers = users.where((user) {
                  return user.name.toLowerCase().contains(_searchQuery) ||
                      user.email.toLowerCase().contains(_searchQuery);
                }).toList();

                if (filteredUsers.isEmpty) {
                  return const Center(
                    child: Text('No users match your search.'),
                  );
                }

                return ListView.builder(
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(user.name),
                        subtitle: Text(
                          '${user.email}\nRole: ${_roleName(user.role)}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Change role',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _changeRole(user),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _roleName(UserRole role) => switch (role) {
  UserRole.admin => 'Admin',
  UserRole.branchManager => 'Branch Manager',
  UserRole.staff => 'Staff',
  UserRole.member => 'Member',
};
