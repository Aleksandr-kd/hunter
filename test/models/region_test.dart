import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/region.dart';

void main() {
  group('SeasonPeriod.statusAt', () {
    test('сезон открыт в пределах дат', () {
      final p = SeasonPeriod(
        name: 'Кабан',
        openDate: DateTime(2026, 6, 1),
        closeDate: DateTime(2026, 12, 31),
      );
      expect(p.statusAt(DateTime(2026, 7, 15)), SeasonStatus.open);
    });

    test('сезон «скоро», если дата раньше открытия', () {
      final p = SeasonPeriod(
        name: 'Кабан',
        openDate: DateTime(2026, 6, 1),
        closeDate: DateTime(2026, 12, 31),
      );
      expect(p.statusAt(DateTime(2026, 3, 1)), SeasonStatus.coming);
    });

    test('сезон закрыт после даты окончания (через год)', () {
      // Заяц-русак: ноябрь – январь следующего года.
      final p = SeasonPeriod(
        name: 'Заяц',
        openDate: DateTime(2026, 11, 1),
        closeDate: DateTime(2027, 1, 31),
      );
      expect(p.statusAt(DateTime(2027, 3, 10)), SeasonStatus.closed);
    });

    test('без дат — статус unknown', () {
      final p = SeasonPeriod(name: 'Без сезона');
      expect(p.statusAt(DateTime(2026, 6, 1)), SeasonStatus.unknown);
    });
  });
}