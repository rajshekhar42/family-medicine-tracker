import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/app_settings.dart';
import '../repositories/settings_repository.dart';

class SaveSettings {
  final SettingsRepository repository;

  SaveSettings(this.repository);

  Future<Either<Failure, void>> call({required AppSettings settings}) {
    return repository.saveSettings(settings: settings);
  }
}
