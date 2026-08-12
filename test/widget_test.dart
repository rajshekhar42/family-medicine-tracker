import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:family_medicine_tracker/app.dart';
import 'package:family_medicine_tracker/features/sync/presentation/providers/auth_provider.dart';

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-firebase-uid';
}

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier(AuthState initialState) : super(null) {
    state = initialState;
  }
}

void main() {
  testWidgets('App starts and redirects to Onboarding Screen displaying Profile Setup directly', (WidgetTester tester) async {
    final fakeAuthNotifier = FakeAuthNotifier(const AuthState(
      firebaseUser: null,
      googleAccount: null,
      authHeaders: null,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => fakeAuthNotifier),
        ],
        child: const MyApp(),
      ),
    );

    // Let the GoRouter route initialization complete
    await tester.pumpAndSettle();

    // Verify Onboarding Screen is displayed directly with Profile Form
    expect(find.text('FamilyMediCare'), findsOneWidget);
    expect(find.text('Set Up Your Profile'), findsOneWidget);
    expect(find.text('Profile Name'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Create Profile & Start'), findsOneWidget);
  });
}
