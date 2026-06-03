import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/screens/task_detail_screen.dart';

void main() {
  group('resolveResultsState', () {
    test('readyToGrade when allConfirmed and has submissions and no results', () {
      expect(
        resolveResultsState(allConfirmed: true, subCount: 2, hasGradingResults: false),
        ResultsSectionStatus.readyToGrade,
      );
    });

    test('waitingForSubmissions when allConfirmed but no submissions', () {
      expect(
        resolveResultsState(allConfirmed: true, subCount: 0, hasGradingResults: false),
        ResultsSectionStatus.waitingForSubmissions,
      );
    });

    test('waitingForStrategy when strategy not confirmed', () {
      expect(
        resolveResultsState(allConfirmed: false, subCount: 3, hasGradingResults: false),
        ResultsSectionStatus.waitingForStrategy,
      );
    });

    test('hasResults when grading results exist', () {
      expect(
        resolveResultsState(allConfirmed: true, subCount: 2, hasGradingResults: true),
        ResultsSectionStatus.hasResults,
      );
    });

    test('hasResults overrides all other conditions', () {
      expect(
        resolveResultsState(allConfirmed: false, subCount: 0, hasGradingResults: true),
        ResultsSectionStatus.hasResults,
      );
    });
  });
}
