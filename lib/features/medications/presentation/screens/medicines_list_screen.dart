import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/medicine.dart';
import '../providers/medications_provider.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';

class MedicinesListScreen extends ConsumerWidget {
  const MedicinesListScreen({super.key});

  IconData _getIcon(String type) {
    switch (type.toLowerCase()) {
      case 'tablet':
        return Icons.circle_outlined;
      case 'capsule':
        return Icons.medical_services_outlined;
      case 'syrup':
        return Icons.wine_bar_outlined ?? Icons.local_activity_outlined;
      case 'powder':
        return Icons.grain_outlined;
      case 'cream':
        return Icons.color_lens_outlined;
      case 'injection':
        return Icons.vaccines_outlined;
      default:
        return Icons.medication_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final listState = ref.watch(medicinesListProvider);
    final activeProfile = ref.watch(activeProfileProvider);
    final isReadOnly = activeProfile != null && !activeProfile.isOwner;
    final canManageMedicines = activeProfile != null && (activeProfile.isOwner || activeProfile.appCode != null);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Medicines List'),
        backgroundColor: Colors.transparent,
        centerTitle: false,
        actions: [
          if (activeProfile != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      activeProfile.profileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: listState.when(
        data: (medicines) {
          final activeMeds = medicines.where((m) => m.active).toList();
          final inactiveMeds = medicines.where((m) => !m.active).toList();

          if (medicines.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.medication_outlined, size: 64, color: colorScheme.onSurface.withOpacity(0.5)),
                    SizedBox(height: 16),
                    Text('No medicines found', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'You haven\'t added any medicines yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                    ),
                    if (canManageMedicines) ...[
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.push(AppConstants.routeAddMedication),
                        child: const Text('Add Medicine'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              if (activeMeds.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Active Schedules', style: textTheme.titleSmall),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeMeds.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final med = activeMeds[index];
                    return _buildMedicineTile(context, med, !canManageMedicines);
                  },
                ),
                const SizedBox(height: 24),
              ],
              if (inactiveMeds.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Inactive / Paused', style: textTheme.titleSmall),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: inactiveMeds.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final med = inactiveMeds[index];
                    return _buildMedicineTile(context, med, !canManageMedicines);
                  },
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: !canManageMedicines
          ? null
          : FloatingActionButton(
              onPressed: () => context.push(AppConstants.routeAddMedication),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildMedicineTile(BuildContext context, Medicine med, bool isReadOnly) {
    final dosageVal = med.dosageValue;
    final dosageUnit = med.dosageUnit ?? '';
    final dosageStr = dosageVal != null ? '$dosageVal $dosageUnit'.trim() : '';

    final quantityVal = med.quantityValue;
    final quantityUnit = med.quantityUnit ?? '';
    final quantityStr = quantityVal != null ? '$quantityVal $quantityUnit'.trim() : '';

    return Card(
      child: ListTile(
        leading: Icon(
          _getIcon(med.type),
          color: med.active ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          size: 28,
        ),
        title: Text(
          med.name,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: med.active ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        subtitle: Text(
          '$dosageStr • $quantityStr • ${med.frequency}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: isReadOnly ? null : Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.secondary),
        onTap: isReadOnly
            ? null
            : () {
                // Navigate to Edit screen passing the object
                context.push(AppConstants.routeEditMedication, extra: med);
              },
      ),
    );
  }
}
