import 'package:flutter_test/flutter_test.dart';
import 'package:family_medicine_tracker/features/sync/data/datasources/compression_helper.dart';

void main() {
  group('CompressionHelper Unit Tests', () {
    test('JSON Compression, Encoding, and Decoding lifecycle works successfully', () {
      const originalJson = '{"med_id":"123","name":"Prednisolone","dosage":"5mg","logs":["Taken","Skipped","Taken"]}';

      // 1. Compute checksum
      final checksum = CompressionHelper.computeChecksum(originalJson);
      expect(checksum, isNotEmpty);

      // 2. Compress JSON string
      final compressedBytes = CompressionHelper.compress(originalJson);
      expect(compressedBytes, isNotEmpty);

      // 3. Base64 encode
      final base64String = CompressionHelper.toBase64(compressedBytes);
      expect(base64String, isNotEmpty);

      // 4. Base64 decode
      final decodedBytes = CompressionHelper.fromBase64(base64String);
      expect(decodedBytes, equals(compressedBytes));

      // 5. Decompress
      final decompressedJson = CompressionHelper.decompress(decodedBytes);
      expect(decompressedJson, equals(originalJson));

      // 6. Verify checksum matches
      final recomputedChecksum = CompressionHelper.computeChecksum(decompressedJson);
      expect(recomputedChecksum, equals(checksum));
    });

    test('Splitting a large Base64 string into chunks and reassembling works', () {
      // Build a string that is larger than 3.5 KB (3584 characters)
      final buffer = StringBuffer();
      for (int i = 0; i < 500; i++) {
        buffer.write('ABCDEFGH'); // 8 characters * 500 = 4000 characters
      }
      final longString = buffer.toString();
      expect(longString.length, equals(4000));

      // Split into chunks
      final chunks = CompressionHelper.splitIntoChunks(longString);
      
      // Since max chunk size is 3584:
      // Chunk 0: length 3584
      // Chunk 1: length 416 (4000 - 3584)
      expect(chunks.length, equals(2));
      expect(chunks[0].length, equals(3584));
      expect(chunks[1].length, equals(416));

      // Reassemble
      final reassembled = chunks.join('');
      expect(reassembled, equals(longString));
    });
  });
}
