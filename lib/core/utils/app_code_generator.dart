import 'dart:math';

class AppCodeGenerator {
  AppCodeGenerator._();

  /// Generates a unique 8-character code: 1 letter (A-Z) followed by 7 digits
  static String generate() {
    final random = Random();
    
    // Random letter from A to Z
    final charCode = 65 + random.nextInt(26); // ASCII for A is 65
    final letter = String.fromCharCode(charCode);
    
    // Seven random digits
    final digits = List.generate(7, (_) => random.nextInt(10)).join();
    
    return '$letter$digits';
  }
}
