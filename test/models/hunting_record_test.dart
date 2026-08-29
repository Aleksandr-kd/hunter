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

  group('HuntingRecord.openDateForYear', () {
    test('правило 4-я суббота сентября: 2026 — 26.09, 2027 — 25.09', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Водоплавающая дичь',
        season: 'Осень',
        species: 'Лысуха, гуси, утки',
        openDate: '26.09',
        closeDate: '20.01',
        dateRule: '4-sat:09',
      );
      expect(r.openDateForYear(2026), DateTime(2026, 9, 26));
      expect(r.openDateForYear(2027), DateTime(2027, 9, 25));
    });

    test('правило 3-я суббота августа: 2026 — 15.08, 2027 — 21.08', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Степная и полевая дичь',
        season: 'Осень',
        species: 'Вальдшнеп',
        openDate: '15.08',
        closeDate: '31.12',
        dateRule: '3-sat:08',
      );
      expect(r.openDateForYear(2026), DateTime(2026, 8, 15));
      expect(r.openDateForYear(2027), DateTime(2027, 8, 21));
    });

    test('фиксированная дата без правила — та же дата в любой год', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Копытные животные',
        season: 'Осень',
        species: 'Кабан',
        openDate: '01.06',
        closeDate: '28.02',
      );
      expect(r.openDateForYear(2027), DateTime(2027, 6, 1));
    });

    test('closeDateForYear: закрытие через границу года', () {
      final r = HuntingRecord(
        regionId: 'krasnodar',
        regionName: 'Краснодарский край',
        resource: 'Водоплавающая дичь',
        season: 'Осень',
        species: 'Лысуха, гуси, утки',
        openDate: '26.09',
        closeDate: '20.01',
        dateRule: '4-sat:09',
      );
      final open2026 = r.openDateForYear(2026)!;
      expect(r.closeDateForYear(2026, open2026), DateTime(2027, 1, 20));
    });

    test('закрытие по правилу 4-е воскресенье ноября: 2026 — 22.11, 2027 — 28.11',
        () {
      final r = HuntingRecord(
        regionId: 'stavropol',
        regionName: 'Ставропольский край',
        resource: 'Степная и полевая дичь',
        season: 'Осень',
        species: 'Вяхирь, сизый голубь, кольчатая горлица, перепел',
        openDate: '15.08',
        closeDate: '22.11',
        dateRule: '3-sat:08',
        closeRule: '4-sun:11',
      );
      expect(r.openDateForYear(2026), DateTime(2026, 8, 15));
      expect(r.openDateForYear(2027), DateTime(2027, 8, 21));
      expect(r.closeDateInYear(2026), DateTime(2026, 11, 22));
      expect(r.closeDateInYear(2027), DateTime(2027, 11, 28));
    });

    test('закрытие на следующий год для переходящего периода с правилом', () {
      final r = HuntingRecord(
        regionId: 'stavropol',
        regionName: 'Ставропольский край',
        resource: 'Степная и полевая дичь',
        season: 'Осень',
        species: 'Вяхирь, сизый голубь, кольчатая горлица, перепел',
        openDate: '05.08',
        closeDate: '02.01',
        dateRule: '3-sat:08',
      );
      final open2026 = r.openDateForYear(2026)!;
      // 02.01 < открытия (август) — значит закрытие уже в следующем году.
      expect(r.closeDateForYear(2026, open2026), DateTime(2027, 1, 2));
    });

    test('close_rule вида +N: закрытие = открытие + N дней', () {
      final r = HuntingRecord(
        regionId: 'moscow',
        regionName: 'Московская область',
        resource: 'Водоплавающая дичь',
        season: 'Весна',
        species: 'Боровая и водоплавающая дичь',
        openDate: '04.04',
        closeDate: '13.04',
        dateRule: '1-sat:04',
        closeRule: '+9',
      );
      final open2026 = r.openDateForYear(2026)!;
      expect(open2026, DateTime(2026, 4, 4));
      expect(r.closeDateInYear(2026, open: open2026), DateTime(2026, 4, 13));
      // 2027: 1-я суббота апреля — 03.04, закрытие через 9 дней.
      final open2027 = r.openDateForYear(2027)!;
      expect(open2027, DateTime(2027, 4, 3));
      expect(r.closeDateInYear(2027, open: open2027), DateTime(2027, 4, 12));
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
        dateRule: '4-sat:09',
        closeRule: '4-sun:11',
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
      expect(restored.dateRule, '4-sat:09');
      expect(restored.closeRule, '4-sun:11');
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
      expect(json['date_rule'], isNull);
      expect(json['close_rule'], isNull);
      final restored = HuntingRecord.fromJson(json);
      expect(restored.openDate, isNull);
      expect(restored.restrictions, isNull);
      expect(restored.dateRule, isNull);
      expect(restored.closeRule, isNull);
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