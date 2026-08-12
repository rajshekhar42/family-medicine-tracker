import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/app_settings.dart';

abstract class SettingsRepository {
  Future<Either<Failure, AppSettings>> getSettings({required String profileId});
  Future<Either<Failure, void>> saveSettings({required AppSettings settings});
}
