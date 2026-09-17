import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/widgets/sahlha_widgets.dart';

void main() {
  group('masteryLabel', () {
    test('maps backend states to calm student-facing labels', () {
      expect(masteryLabel('mastered'), 'Mastered');
      expect(masteryLabel('developing'), 'Developing');
      expect(masteryLabel('needs_practice'), 'Needs practice');
      expect(masteryLabel('not_started'), 'Not started');
      expect(masteryLabel('anything_else'), 'Not started');
    });
  });
}
