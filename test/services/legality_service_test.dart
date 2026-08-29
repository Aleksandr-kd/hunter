import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/hunting_record.dart';
import 'package:pomoshchnik_okhotnika/services/legality_service.dart';

HuntingRecord _rec({
  required String species,
  String resource = 'Пернатая дичь',
  String season = 'Осень',
  String? openDate,
  String? closeDate,
  String? restrictions,
  String? dateRule,
  String? closeRule,
}) {
  return HuntingRecord(
    regionId: 'krasnodar',
    regionName: 'Краснодарский край',
    resource: resource,
    season: season,
    species: species,
    openDate: openDate,
    closeDate: closeDate,
    restrictions: restrictions,
    zone: 'Все',
    dateRule: dateRule,
    closeRule: closeRule,
  );
}

void main() {
  group('LegalityService.check', () {
    final records = [
      _rec(
        species: 'Кабан: все половозрастные группы',
        resource: 'Копытные животные',
        openDate: '01.06',
        closeDate: '28.02',
      ),
      _rec(
        species: 'Лысуха, гуси, утки',
        openDate: '26.09',
        closeDate: '20.01',
      ),
      _rec(
        species: 'Пернатая дичь (все виды)',
        season: 'Весна',
        openDate: '01.03',
        closeDate: '16.06',
        restrictions: 'Запрет на проведение охоты в весенний период',
      ),
      _rec(
        species: 'Вальдшнеп',
        openDate: '15.08',
        closeDate: '16.01',
        restrictions: 'Только с охотничьими собаками',
      ),
    ];

    test('кабан в январе — допустимо (период через новый год)', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'кабан',
        date: DateTime(2026, 1, 15),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isTrue);
      expect(v.forbidden, isNull);
    });

    test('кабан в апреле — не предусмотрено', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'кабан',
        date: DateTime(2026, 4, 15),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isFalse);
    });

    test('утка в мае — не предусмотрено (вне периода осенне-зимнего сезона)',
        () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'утка',
        date: DateTime(2026, 5, 10),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isFalse);
      expect(v.forbidden, isNull);
    });

    test('пернатая дичь в мае — запрещено весенним запретом', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'пернатая',
        date: DateTime(2026, 5, 10),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isFalse);
      expect(v.forbidden, isNotNull);
    });

    test('утка в октябре — допустимо', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'утки',
        date: DateTime(2026, 10, 10),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isTrue);
    });

    test('вальдшнеп в периоде — допустимо при соблюдении ограничений', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'вальдшнеп',
        date: DateTime(2026, 8, 20),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isTrue);
      expect(
        v.active.any((r) =>
            r.restrictions != null &&
            r.restrictions!.contains('собаками')),
        isTrue,
      );
    });

    test('неизвестный вид — не найден', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: 'единорог',
        date: DateTime(2026, 10, 10),
      );
      expect(v.speciesFound, isFalse);
      expect(v.allowed, isFalse);
      expect(v.forbidden, isNull);
    });

    test('пустой запрос — не найден', () {
      final v = LegalityService.check(
        regionRecords: records,
        query: '   ',
        date: DateTime(2026, 10, 10),
      );
      expect(v.speciesFound, isFalse);
    });
  });

  group('LegalityService.check с плавающей датой (date_rule)', () {
    final duckRule = _rec(
      species: 'Лысуха, гуси, утки',
      openDate: '26.09',
      closeDate: '20.01',
      dateRule: '4-sat:09',
    );
    final woodcockRule = _rec(
      species: 'Вальдшнеп',
      openDate: '15.08',
      closeDate: '31.12',
      dateRule: '3-sat:08',
    );

    test('утка: за день до 4-й субботы сентября 2026 — закрыто', () {
      final v = LegalityService.check(
        regionRecords: [duckRule],
        query: 'утка',
        date: DateTime(2026, 9, 25),
      );
      expect(v.speciesFound, isTrue);
      expect(v.allowed, isFalse);
    });

    test('утка: сама 4-я суббота сентября 2026 (26.09) — открыто', () {
      final v = LegalityService.check(
        regionRecords: [duckRule],
        query: 'утка',
        date: DateTime(2026, 9, 26),
      );
      expect(v.allowed, isTrue);
    });

    test('утка: январь 2027 — сезон 2026/27 ещё открыт (переход через год)', () {
      final v = LegalityService.check(
        regionRecords: [duckRule],
        query: 'утка',
        date: DateTime(2027, 1, 10),
      );
      expect(v.allowed, isTrue);
    });

    test('утка: открытие в 2027 году сместилось на 25.09', () {
      expect(
        LegalityService.check(
          regionRecords: [duckRule],
          query: 'утка',
          date: DateTime(2027, 9, 24),
        ).allowed,
        isFalse,
      );
      expect(
        LegalityService.check(
          regionRecords: [duckRule],
          query: 'утка',
          date: DateTime(2027, 9, 25),
        ).allowed,
        isTrue,
      );
    });

    test('вальдшнеп: открытие 3-я суббота августа сдвигается по годам', () {
      // 2026 — 15.08 открыто; 2027 — 3-я суббота приходится на 21.08.
      expect(
        LegalityService.check(
          regionRecords: [woodcockRule],
          query: 'вальдшнеп',
          date: DateTime(2026, 8, 14),
        ).allowed,
        isFalse,
      );
      expect(
        LegalityService.check(
          regionRecords: [woodcockRule],
          query: 'вальдшнеп',
          date: DateTime(2026, 8, 15),
        ).allowed,
        isTrue,
      );
      expect(
        LegalityService.check(
          regionRecords: [woodcockRule],
          query: 'вальдшнеп',
          date: DateTime(2027, 8, 20),
        ).allowed,
        isFalse,
      );
      expect(
        LegalityService.check(
          regionRecords: [woodcockRule],
          query: 'вальдшнеп',
          date: DateTime(2027, 8, 21),
        ).allowed,
        isTrue,
      );
    });
  });

  group('LegalityService.check со сдвигом открытия и закрытия (close_rule)', () {
    final stepRule = _rec(
      species: 'Вяхирь, сизый голубь, кольчатая горлица, перепел',
      openDate: '15.08',
      closeDate: '22.11',
      dateRule: '3-sat:08',
      closeRule: '4-sun:11',
    );

    test('2026: открытие 15.08, закрытие 22.11 (4-е воскресенье ноября)', () {
      bool allowedOn(int m, int d) => LegalityService.check(
            regionRecords: [stepRule],
            query: 'вяхирь',
            date: DateTime(2026, m, d),
          ).allowed;
      expect(allowedOn(8, 14), isFalse);
      expect(allowedOn(8, 15), isTrue);
      expect(allowedOn(11, 22), isTrue);
      expect(allowedOn(11, 23), isFalse);
    });

    test('2027: открытие сместилось на 21.08, закрытие на 28.11', () {
      bool allowedOn(int m, int d) => LegalityService.check(
            regionRecords: [stepRule],
            query: 'вяхирь',
            date: DateTime(2027, m, d),
          ).allowed;
      expect(allowedOn(8, 20), isFalse);
      expect(allowedOn(8, 21), isTrue);
      expect(allowedOn(11, 28), isTrue);
      expect(allowedOn(11, 29), isFalse);
    });
  });

  group('LegalityService.check с продолжительностью (close_rule +N)', () {
    final spring = _rec(
      species: 'Боровая и водоплавающая дичь',
      season: 'Весна',
      openDate: '04.04',
      closeDate: '13.04',
      dateRule: '1-sat:04',
      closeRule: '+9',
    );

    test('2026: 1-я суббота апреля 04.04, закрытие 13.04 (10 дней охоты)', () {
      bool allowedOn(int m, int d) => LegalityService.check(
            regionRecords: [spring],
            query: 'дичь',
            date: DateTime(2026, m, d),
          ).allowed;
      expect(allowedOn(4, 3), isFalse);
      expect(allowedOn(4, 4), isTrue);
      expect(allowedOn(4, 13), isTrue);
      expect(allowedOn(4, 14), isFalse);
    });

    test('2027: открытие 03.04, закрытие 12.04', () {
      bool allowedOn(int m, int d) => LegalityService.check(
            regionRecords: [spring],
            query: 'дичь',
            date: DateTime(2027, m, d),
          ).allowed;
      expect(allowedOn(4, 2), isFalse);
      expect(allowedOn(4, 3), isTrue);
      expect(allowedOn(4, 12), isTrue);
      expect(allowedOn(4, 13), isFalse);
    });
  });

  group('LegalityService.suggestions', () {
    test('ищет по словоформам и составляет список подсказок', () {
      final records = [
        _rec(species: 'Лысуха, гуси, утки'),
        _rec(species: 'Серая ворона'),
        _rec(species: 'Кабан: все половозрастные группы'),
      ];
      final res = LegalityService.suggestions(records, 'утки');
      expect(res, ['Лысуха, гуси, утки']);
    });

    test('пустой запрос возвращает пустой список', () {
      final records = [_rec(species: 'Лысуха, гуси, утки')];
      expect(LegalityService.suggestions(records, ''), isEmpty);
    });
  });
}