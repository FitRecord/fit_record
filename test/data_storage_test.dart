import 'package:android/data_storage_records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordStorage', () {
    final underTest = RecordStorage();
    test('nextFrom gives correct weekstart date for Sunday', () {
      final dt = underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Week);
      expect(dt.year, 2020);
      expect(dt.month, 7);
      expect(dt.day, 13);
    });
    test('nextFrom gives correct weekstart date for Monday', () {
      final dt = underTest.nextFrom(DateTime(2020, 7, 20), HistoryRange.Week);
      expect(dt.year, 2020);
      expect(dt.month, 7);
      expect(dt.day, 20);
    });
    test('nextFrom gives correct next weekstart date', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Week, 1);
      expect(dt.year, 2020);
      expect(dt.month, 7);
      expect(dt.day, 20);
    });
    test('nextFrom gives correct previous weekstart date', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Week, -1);
      expect(dt.year, 2020);
      expect(dt.month, 7);
      expect(dt.day, 6);
    });
    test('nextFrom gives correct month', () {
      final dt = underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Month);
      expect(dt.year, 2020);
      expect(dt.month, 7);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct next month', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Month, 1);
      expect(dt.year, 2020);
      expect(dt.month, 8);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct previous month', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Month, -1);
      expect(dt.year, 2020);
      expect(dt.month, 6);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct next month in December', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 12, 19), HistoryRange.Month, 1);
      expect(dt.year, 2021);
      expect(dt.month, 1);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct previous month in January', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 1, 19), HistoryRange.Month, -1);
      expect(dt.year, 2019);
      expect(dt.month, 12);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct month in next year', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Month, 11);
      expect(dt.year, 2021);
      expect(dt.month, 6);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct in previous year', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Month, -11);
      expect(dt.year, 2019);
      expect(dt.month, 8);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct year', () {
      final dt = underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Year);
      expect(dt.year, 2020);
      expect(dt.month, 1);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct next year', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Year, 1);
      expect(dt.year, 2021);
      expect(dt.month, 1);
      expect(dt.day, 1);
    });
    test('nextFrom gives correct previous year', () {
      final dt =
          underTest.nextFrom(DateTime(2020, 7, 19), HistoryRange.Year, -1);
      expect(dt.year, 2019);
      expect(dt.month, 1);
      expect(dt.day, 1);
    });
  });
}
