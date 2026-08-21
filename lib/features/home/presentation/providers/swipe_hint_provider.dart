import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/db_helper.dart';

/// Persistent state for the swipe-gesture tutorial hint.
///
/// Rules:
/// - **Total Limit**: Displays at most **4 times ever**.
/// - **Daily Frequency**: Displays at most **twice per distinct calendar day**
///   (first and second dose logged on day 1, and first and second dose logged on day 2 or later).
class SwipeHintState {
  final int totalShownCount;
  final String? lastShownDate;
  final int lastShownDateCount;

  const SwipeHintState({
    this.totalShownCount = 0,
    this.lastShownDate,
    this.lastShownDateCount = 0,
  });

  SwipeHintState copyWith({
    int? totalShownCount,
    String? lastShownDate,
    int? lastShownDateCount,
  }) {
    return SwipeHintState(
      totalShownCount: totalShownCount ?? this.totalShownCount,
      lastShownDate: lastShownDate ?? this.lastShownDate,
      lastShownDateCount: lastShownDateCount ?? this.lastShownDateCount,
    );
  }
}

class SwipeHintNotifier extends StateNotifier<SwipeHintState> {
  SwipeHintNotifier() : super(const SwipeHintState()) {
    _initFuture = _loadFromDb();
  }

  static const _keyShownCount = 'swipe_hint_shown_count';
  static const _keyLastShownDate = 'swipe_hint_last_shown_date';
  static const _keyLastShownDateCount = 'swipe_hint_last_shown_date_count';

  late final Future<void> _initFuture;

  /// Returns `true` if the tutorial should be shown right now.
  ///
  /// Awaits DB initialization to complete before checking, so this
  /// never returns a false negative due to a race condition.
  ///
  /// Conditions:
  /// - Total shown count < 4
  /// - Shown count for today < 2
  Future<bool> shouldShowHint() async {
    await _initFuture;

    // 1. Total limit check (at most 4 times ever)
    if (state.totalShownCount >= 4) return false;

    // 2. Daily limit check (at most twice per calendar day)
    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (state.lastShownDate == todayDate && state.lastShownDateCount >= 2) {
      return false;
    }

    return true;
  }

  /// Records that the tutorial was shown. Increments counts, updates today's
  /// date, and persists to SQLite.
  Future<void> recordHintShown() async {
    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final newTotal = state.totalShownCount + 1;
    final newDateCount =
        (state.lastShownDate == todayDate) ? state.lastShownDateCount + 1 : 1;

    state = state.copyWith(
      totalShownCount: newTotal,
      lastShownDate: todayDate,
      lastShownDateCount: newDateCount,
    );

    await _persistToDb();
  }

  Future<void> _loadFromDb() async {
    try {
      if (kIsWeb) return;

      final db = await DbHelper.instance.database;
      final rows = await db.query(
        AppConstants.tableAppPreferences,
        where: 'key IN (?, ?, ?)',
        whereArgs: [_keyShownCount, _keyLastShownDate, _keyLastShownDateCount],
      );

      int totalCount = 0;
      String? lastDate;
      int dateCount = 0;

      for (final row in rows) {
        final key = row['key'] as String;
        final value = row['value'] as String;
        if (key == _keyShownCount) {
          totalCount = int.tryParse(value) ?? 0;
        } else if (key == _keyLastShownDate) {
          lastDate = value;
        } else if (key == _keyLastShownDateCount) {
          dateCount = int.tryParse(value) ?? 0;
        }
      }

      state = SwipeHintState(
        totalShownCount: totalCount,
        lastShownDate: lastDate,
        lastShownDateCount: dateCount,
      );
    } catch (e) {
      debugPrint('SwipeHintNotifier: Failed to load from DB: $e');
    }
  }

  Future<void> _persistToDb() async {
    try {
      if (kIsWeb) return;

      final db = await DbHelper.instance.database;
      await db.insert(
        AppConstants.tableAppPreferences,
        {'key': _keyShownCount, 'value': state.totalShownCount.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        AppConstants.tableAppPreferences,
        {'key': _keyLastShownDate, 'value': state.lastShownDate ?? ''},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        AppConstants.tableAppPreferences,
        {
          'key': _keyLastShownDateCount,
          'value': state.lastShownDateCount.toString()
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('SwipeHintNotifier: Failed to persist to DB: $e');
    }
  }
}

/// Global provider for the swipe tutorial hint state.
///
/// Accessed by [MedicationCard] to decide whether to show the tutorial overlay.
final swipeHintProvider =
    StateNotifierProvider<SwipeHintNotifier, SwipeHintState>((ref) {
  return SwipeHintNotifier();
});
