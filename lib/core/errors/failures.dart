abstract class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

class LocalDatabaseFailure extends Failure {
  const LocalDatabaseFailure(super.message);
}

class RemoteSyncFailure extends Failure {
  const RemoteSyncFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
