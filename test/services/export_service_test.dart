import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/diary_entry.dart';
import 'package:pomoshchnik_okhotnika/services/export_service.dart';
import 'package:pomoshchnik_okhotnika/services/tier_manager.dart';

DiaryEntry entry(String species, {String? location, DateTime? date}) {
  return DiaryEntry(
    date: date ?? DateTime(2026, 8, 1),
    species: species,
    location: location,
    weather: 'солнечно',
    notes: 'заметка',
  );
}

void main() {
  group('ExportService.mapBackupToJson', () {
    test('генерирует корректный JSON со списком записей', () {
      final json = jsonDecode(ExportService.mapBackupToJson([
        entry('Лось', location: 'Лес'),
        entry('Утка'),
      ])) as Map<String, dynamic>;

      expect(json['version'], 1);
      final entries = json['entries'] as List;
      expect(entries.length, 2);
      final first = entries.first as Map<String, dynamic>;
      expect(first['species'], 'Лось');
      expect(first['location'], 'Лес');
      expect(first['weather'], 'солнечно');
      expect(first['notes'], 'заметка');
      // Дата сохраняется в ISO-формате для возможности восстановления.
      expect(first['date'], isA<String>());
    });

    test('пустой список даёт пустой массив entries', () {
      final json = jsonDecode(ExportService.mapBackupToJson([]))
          as Map<String, dynamic>;
      expect((json['entries'] as List), isEmpty);
    });
  });

  group('ExportService.parseBackup', () {
    test('корректно разбирает валидный JSON', () {
      final entries = ExportService.parseBackup(
        ExportService.mapBackupToJson([
          entry('Лось', location: 'Лес'),
          entry('Утка'),
        ]),
      )!;
      expect(entries.length, 2);
      expect(entries[0].species, 'Лось');
      expect(entries[0].location, 'Лес');
      expect(entries[1].species, 'Утка');
    });

    test('некод JSON возвращает null', () {
      expect(ExportService.parseBackup('not json'), isNull);
    });

    test('JSON без поля entries возвращает пустой список', () {
      final entries = ExportService.parseBackup('{"version":1}')!;
      expect(entries, isEmpty);
    });
  });

  group('TierManager.gating', () {
    void reset(String tier) => TierManager.tier = tier;

    test('none — не unlimited, не premium, не max', () {
      reset('none');
      expect(TierManager.isUnlimited, isFalse);
      expect(TierManager.isPremium, isFalse);
      expect(TierManager.isMax, isFalse);
    });

    test('premium — limited (не max), но premium', () {
      reset('premium');
      expect(TierManager.isUnlimited, isTrue);
      expect(TierManager.isPremium, isTrue);
      expect(TierManager.isMax, isFalse);
    });

    test('max — и premium, и max, и unlimited', () {
      reset('max');
      expect(TierManager.isUnlimited, isTrue);
      expect(TierManager.isPremium, isTrue);
      expect(TierManager.isMax, isTrue);
    });
  });
}