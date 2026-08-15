import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/bootstrap/app_bootstrapper.dart';
import 'app.dart';

void main() async {
  // Ensure Flutter binding is initialized before any platform channel calls
  WidgetsFlutterBinding.ensureInitialized();

  // Delegate all startup initialization to AppBootstrapper (SRP)
  await AppBootstrapper.initialize();

  // Run the app wrapped in ProviderScope for Riverpod state management
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
