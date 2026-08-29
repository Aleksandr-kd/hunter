import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/document.dart';

void main() {
  group('Document.copyWith', () {
    test('keeps expiryDate when not passed', () {
      final doc = Document(
        title: 'Охотничий билет',
        expiryDate: DateTime(2026, 5, 1),
      );
      final copy = doc.copyWith(supabaseId: 'abc');
      expect(copy.expiryDate, doc.expiryDate);
    });

    test('clears expiryDate when null is passed explicitly', () {
      final doc = Document(
        title: 'Охотничий билет',
        expiryDate: DateTime(2026, 5, 1),
      );
      final copy = doc.copyWith(expiryDate: null);
      expect(copy.expiryDate, isNull);
    });

    test('sets expiryDate to a new value', () {
      final doc = Document(title: 'Охотничий билет');
      final copy = doc.copyWith(expiryDate: DateTime(2026, 5, 1));
      expect(copy.expiryDate, DateTime(2026, 5, 1));
    });
  });
}
