import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

class CompressionHelper {
  CompressionHelper._();

  static const int maxChunkSize = 3584; // 3.5 KB limit per message chunk

  /// Compresses a JSON string to a GZIP byte list
  static List<int> compress(String json) {
    final bytes = utf8.encode(json);
    return GZipEncoder().encode(bytes) ?? [];
  }

  /// Decompresses GZIP bytes to a JSON string
  static String decompress(List<int> gzippedBytes) {
    final decompressed = GZipDecoder().decodeBytes(gzippedBytes);
    return utf8.decode(decompressed);
  }

  /// Encodes a byte list into a Base64 string
  static String toBase64(List<int> bytes) {
    return base64.encode(bytes);
  }

  /// Decodes a Base64 string into a byte list
  static List<int> fromBase64(String encoded) {
    return base64.decode(encoded);
  }

  /// Computes the MD5 checksum of a JSON string
  static String computeChecksum(String json) {
    return md5.convert(utf8.encode(json)).toString();
  }

  /// Splits a Base64 string into chunks of max size
  static List<String> splitIntoChunks(String encodedString) {
    final List<String> chunks = [];
    int index = 0;
    while (index < encodedString.length) {
      final end = (index + maxChunkSize > encodedString.length)
          ? encodedString.length
          : index + maxChunkSize;
      chunks.add(encodedString.substring(index, end));
      index = end;
    }
    return chunks;
  }
}
