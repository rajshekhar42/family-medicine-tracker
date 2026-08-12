import 'dart:math';

class AppCodeGenerator {
  AppCodeGenerator._();

  /// Generates a unique 7-character code: 1 letter (A-Z) followed by 6 digits
  static String generate() {
    final random = Random();
    
    // Random letter from A to Z
    final charCode = 65 + random.nextInt(26); // ASCII for A is 65
    final letter = String.fromCharCode(charCode);
    
    // Six random digits
    final digits = List.generate(6, (_) => random.nextInt(10)).join();
    
    return '$letter$digits';
  }
}
