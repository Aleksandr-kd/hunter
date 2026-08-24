import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/hunting_record.dart';

void main() {
  group('HuntingRecord.datesLabel', () {
    test('полные даты — через дефис', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Пернатая дичь',
        season: 'Осень',
        species: 'Вальдшнеп',
        openDate: '15.08',
        closeDate: '16.01',
      );
      expect(r.datesLabel, '15.08-16.01');
    });

    test('только openDate (без close) — одна дата', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Пернатая дичь',
        season: 'Весна',
        species: 'Косуля',
        openDate: '20.05',
      );
      expect(r.datesLabel, '20.05');
    });

    test('без дат — тире', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Пернатая дичь',
        season: 'Осень',
        species: 'Вид без дат',
      );
      expect(r.datesLabel, '—');
    });
  });

  group('HuntingRecord.toJson/fromJson', () {
    test('круговое преобразование сохраняет данные', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Копытные животные',
        season: 'Осень',
        species: 'Кабан: все половозрастные группы',
        openDate: '01.06',
        closeDate: '28.02',
        restrictions: 'Ограничение',
        zone: 'Все',
      );
      final restored = HuntingRecord.fromJson(r.toJson());
      expect(restored.regionId, 'krasnodar');
      expect(restored.regionName, 'Краснодарский край');
      expect(restored.resource, 'Копытные животные');
      expect(restored.species, 'Кабан: все половозрастные группы');
      expect(restored.openDate, '01.06');
      expect(restored.closeDate, '28.02');
      expect(restored.restrictions, 'Ограничение');
      expect(restored.zone, 'Все');
    });

    test('null-поля сохраняются как null и переживают fromJson', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Пернатая дичь',
        season: 'Лето',
        species: 'Вальдшнеп',
      );
      final json = r.toJson();
      expect(json['open_date'], isNull);
      expect(json['restrictions'], isNull);
      final restored = HuntingRecord.fromJson(json);
      expect(restored.openDate, isNull);
      expect(restored.restrictions, isNull);
    });
  });

  group('HuntingRecord.searchKey', () {
    test('нижний регистр для поиска', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Медведи',
        season: 'Осень',
        species: 'Медведь бурый',
      );
      expect(r.searchKey, 'медведь бурый');
    });
  });
}