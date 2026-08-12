import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/adherence_report.dart';

abstract class HistoryRepository {
  Future<Either<Failure, List<MedicineAdherence>>> getAdherenceReports({required String profileId});
}
