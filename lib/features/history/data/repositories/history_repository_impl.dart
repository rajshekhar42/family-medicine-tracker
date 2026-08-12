import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/adherence_report.dart';
import '../../domain/repositories/history_repository.dart';
import '../datasources/history_local_datasource.dart';
import '../../../medications/data/datasources/medication_local_datasource.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryLocalDataSource historyLocalDataSource;
  final MedicationLocalDataSource medicationLocalDataSource;

  HistoryRepositoryImpl({
    required this.historyLocalDataSource,
    required this.medicationLocalDataSource,
  });

  @override
  Future<Either<Failure, List<MedicineAdherence>>> getAdherenceReports({
    required String profileId,
  }) async {
    try {
      // 1. Fetch all medicines for the profile
      final medicines = await medicationLocalDataSource.getAllMedications(profileId);

      // 2. Fetch all historical log records for the profile
      final rawLogs = await historyLocalDataSource.getHistoryLogs(profileId);

      // 3. Map logs to DoseLog entities grouped by medicineId
      final Map<String, List<DoseLog>> groupedLogs = {};
      for (final row in rawLogs) {
        final medId = row['medicine_id'] as String;
        final log = DoseLog(
          date: row['date'] as String,
          time: row['time'] as String,
          status: row['status'] as String,
          takenAt: row['taken_at'] as int?,
        );
        groupedLogs.putIfAbsent(medId, () => []).add(log);
      }

      // 4. Build reports for each medicine
      final List<MedicineAdherence> reports = [];
      for (final med in medicines) {
        final logs = groupedLogs[med.id] ?? [];
        
        double adherenceRate = 100.0;
        if (logs.isNotEmpty) {
          final total = logs.length;
          final taken = logs.where((l) => l.status == 'Taken').length;
          adherenceRate = (taken / total) * 100;
        }

        reports.add(
          MedicineAdherence(
            medicineId: med.id,
            medicineName: med.name,
            type: med.type,
            adherenceRate: adherenceRate,
            logs: logs,
          ),
        );
      }

      // Sort by medicine name
      reports.sort((a, b) => a.medicineName.compareTo(b.medicineName));

      return Right(reports);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to generate adherence reports: $e'));
    }
  }
}
