import 'package:flutter/material.dart';

import '../../core/services/resource_repository.dart';
import '../../models/branch.dart';
import 'branch_resources_screen.dart';

class BranchesScreen extends StatelessWidget {
  BranchesScreen({super.key, ResourceRepository? repository})
    : _repository = repository ?? ResourceRepository();

  final ResourceRepository _repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      body: StreamBuilder<List<Branch>>(
        stream: _repository.watchBranches(),
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
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.apartment, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No branches yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text('Branches will appear here when added.'),
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BranchResourcesScreen(
                          branch: branch,
                          repository: _repository,
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
  }
}
