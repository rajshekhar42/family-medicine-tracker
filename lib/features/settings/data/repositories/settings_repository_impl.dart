import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_datasource.dart';
import '../models/settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, AppSettings>> getSettings({required String profileId}) async {
    try {
      final model = await localDataSource.getSettings(profileId);
      if (model != null) {
        return Right(model.toEntity());
      }
      
      // If no settings exist yet, create and save default settings
      final defaultSettings = AppSettings(profileId: profileId);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final defaultModel = SettingsModel.fromAppSettings(defaultSettings, isDirty: 1, updatedAt: now);
      
      await localDataSource.saveSettings(defaultModel);
      return Right(defaultSettings);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to load settings: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveSettings({required AppSettings settings}) async {
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final model = SettingsModel.fromAppSettings(settings, isDirty: 1, updatedAt: now);
      await localDataSource.saveSettings(model);
      return const Right(null);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to save settings: $e'));
    }
  }
}
