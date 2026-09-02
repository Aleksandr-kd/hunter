import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomoshchnik_okhotnika/providers/seasons_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> record(
    String regionId,
    String regionName, {
    String species = 'Кабан',
    String resource = 'Копытные животные',
    String season = 'Осень',
    String open = '01.06',
    String close = '28.02',
  }) =>
      {
        'region_id': regionId,
        'region_name': regionName,
        'resource': resource,
        'season': season,
        'species': species,
        'open_date': open,
        'close_date': close,
      };

  Future<SeasonsProvider> pumpProvider() async {
    final provider = SeasonsProvider();
    for (var i = 0; i < 50 && !provider.loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  group('SeasonsProvider.regions (динамический каталог)', () {
    test('строится из записей hunting_seasons (новый регион подхватывается)',
        () async {
      SharedPreferences.setMockInitialValues({
        'hunting_seasons_cache': jsonEncode([
          record('krasnodar', 'Краснодарский край'),
          record('tatarstan', 'Республика Татарстан'),
        ]),
      });

      final provider = await pumpProvider();

      final ids = provider.regionIds;
      expect(ids, contains('krasnodar'));
      expect(ids, contains('tatarstan'));
      expect(provider.regionName('tatarstan'), 'Республика Татарстан');
    });

    test('при пустом кэше используется резервный каталог', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await pumpProvider();

      expect(provider.regionIds, isNotEmpty);
      // Резервный каталог всё равно позволяет выбрать регион для уведомлений.
      expect(provider.regionIds, contains('krasnodar'));
    });
  });

  group('SeasonsProvider.myRegionId', () {
    test('по умолчанию «не выбран» (null)', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await pumpProvider();
      expect(provider.myRegionId, isNull);
    });

    test('setMyRegion сохраняет выбор и пишет в prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await pumpProvider();

      await provider.setMyRegion('krasnodar');
      expect(provider.myRegionId, 'krasnodar');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('seasons_my_region'), 'krasnodar');
    });

    test('setMyRegion(null) сбрасывает выбор (может быть «никакой»)', () async {
      SharedPreferences.setMockInitialValues({
        'seasons_my_region': 'krasnodar',
      });
      final provider = await pumpProvider();
      expect(provider.myRegionId, 'krasnodar');

      await provider.setMyRegion(null);
      expect(provider.myRegionId, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('seasons_my_region'), isNull);
    });

    test('setMyRegion с пустой строкой тоже сбрасывает', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = await pumpProvider();

      await provider.setMyRegion('');
      expect(provider.myRegionId, isNull);
    });
  });
}