import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final performanceServiceProvider = Provider<PerformanceService>((ref) {
  return PerformanceService();
});

class PerformanceService {
  final FirebasePerformance _perf = FirebasePerformance.instance;
  final Map<String, Trace> _activeTraces = {};

  Future<void> startTrace(String name) async {
    try {
      if (_activeTraces.containsKey(name)) {
        debugPrint('PerformanceService: Trace "$name" is already running.');
        return;
      }
      final trace = _perf.newTrace(name);
      await trace.start();
      _activeTraces[name] = trace;
      debugPrint('PerformanceService: Trace "$name" started.');
    } catch (e) {
      debugPrint('PerformanceService: Failed to start trace "$name": $e');
    }
  }

  Future<void> stopTrace(
    String name, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    try {
      final trace = _activeTraces.remove(name);
      if (trace == null) {
        debugPrint('PerformanceService: Trace "$name" not found.');
        return;
      }
      
      if (attributes != null) {
        attributes.forEach((key, val) {
          try {
            trace.putAttribute(key, val);
          } catch (_) {}
        });
      }
      
      if (metrics != null) {
        metrics.forEach((key, val) {
          try {
            trace.setMetric(key, val);
          } catch (_) {}
        });
      }

      await trace.stop();
      debugPrint('PerformanceService: Trace "$name" stopped.');
    } catch (e) {
      debugPrint('PerformanceService: Failed to stop trace "$name": $e');
    }
  }

  Future<T> traceAsync<T>(
    String name,
    Future<T> Function() operation, {
    Map<String, String>? attributes,
  }) async {
    await startTrace(name);
    try {
      final result = await operation();
      await stopTrace(name, attributes: attributes, metrics: {'success': 1});
      return result;
    } catch (e) {
      await stopTrace(name, attributes: attributes, metrics: {'success': 0});
      rethrow;
    }
  }
}
