import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/diary_entry.dart';

/// Экспорт дневника в PDF / CSV и резервная копия в файл.
class ExportService {
  static const _dash = '—';

  static pw.Font? _regular;
  static pw.Font? _bold;
  static Future<void>? _fontLoad;

  /// Лениво загружает кириллические шрифты (Roboto) для PDF.
  static Future<void> _ensureFonts() {
    return _fontLoad ??= () async {
      final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      _regular = pw.Font.ttf(regularData);
      _bold = pw.Font.ttf(boldData);
    }();
  }

  /// Экспорт записей в CSV-файл и его сохранение/совместное использование.
  static Future<File?> exportCsv(List<DiaryEntry> entries) async {
    final rows = <List<dynamic>>[
      ['Дата', 'Вид', 'Место', 'Погода', 'Результат', 'Вес (кг)', 'Кол-во', 'Способ', 'Заметки'],
      for (final e in entries)
        [
          _fmtDate(e.date),
          e.species,
          e.location ?? _dash,
          e.weather ?? _dash,
          e.result ?? _dash,
          e.weight?.toStringAsFixed(1) ?? _dash,
          e.count?.toString() ?? _dash,
          e.method ?? _dash,
          e.notes ?? _dash,
        ],
    ];
    final csv = const CsvEncoder().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/diary_export_${_stamp()}.csv');
    // UTF-8 BOM для корректного открытия в Excel.
    await file.writeAsBytes(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
        flush: true);
    return file;
  }

  /// Экспорт записей в PDF-файл (таблица с датой и видом).
  static Future<File?> exportPdf(List<DiaryEntry> entries) async {
    await _ensureFonts();
    final doc = pw.Document(theme: pw.ThemeData.withFont(
      base: _regular,
      bold: _bold,
    ));

    doc.addPage(
      pw.MultiPage(
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('Дневник охотника'),
          ),
          pw.Header(level: 1, child: pw.Text('Всего записей: ${entries.length}')),
          pw.TableHelper.fromTextArray(
            headers: ['Дата', 'Вид', 'Место', 'Погода', 'Результат', 'Вес', 'Кол-во', 'Способ', 'Заметки'],
            data: [
              for (final e in entries)
                [
                  _fmtDate(e.date),
                  e.species,
                  e.location ?? _dash,
                  e.weather ?? _dash,
                  e.result ?? _dash,
                  e.weight?.toStringAsFixed(1) != null ? '${e.weight!.toStringAsFixed(1)} кг' : _dash,
                  e.count?.toString() ?? _dash,
                  e.method ?? _dash,
                  e.notes ?? _dash,
                ],
            ],
            headerStyle:
                pw.TextStyle(font: _bold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FixedColumnWidth(45),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(0.7),
              4: const pw.FlexColumnWidth(0.8),
              5: const pw.FixedColumnWidth(35),
              6: const pw.FixedColumnWidth(30),
              7: const pw.FixedColumnWidth(50),
              8: const pw.FlexColumnWidth(1.2),
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            tableWidth: pw.TableWidth.max,
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Экспорт из приложения «Охотник»',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/diary_export_${_stamp()}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  /// Предоставляет файл через системный share-диалог.
  static Future<void> share(File file) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  /// Резервная копия: сохраняет дневник в JSON-файл по выбранному пути.
  static Future<File?> backupDiary(List<DiaryEntry> entries,
      {bool saveDialog = false}) async {
    final json = mapBackupToJson(entries);
    final fileName = 'hunter_backup_${_stamp()}.json';
    if (saveDialog) {
      final uri = await FilePickerPlatform.instance.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      if (uri == null || uri.scheme != 'file') return null;
      final file = File.fromUri(uri);
      await file.writeAsString(json, flush: true);
      return file;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(json, flush: true);
    return file;
  }

  /// Преобразует записи в JSON-строку (для резервной копии).
  /// Включает все поля: result, weight, count, method.
  static String mapBackupToJson(List<DiaryEntry> entries) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'entries': entries.map((e) => {
            'uuid': e.uuid,
            'date': e.date.toIso8601String(),
            'species': e.species,
            'location': e.location,
            'weather': e.weather,
            'notes': e.notes,
            'latitude': e.latitude,
            'longitude': e.longitude,
            'photo_path': e.photoPath,
            'result': e.result,
            'weight': e.weight,
            'count': e.count,
            'method': e.method,
            'updated_at': e.updatedAt?.toIso8601String(),
          }).toList(),
    });
  }

  /// Открывает диалог выбора файла и возвращает содержимое JSON-копии,
  /// либо null, если пользователь отменил выбор или файл не файловый.
  static Future<String?> readBackupFile() async {
    final file = await FilePickerPlatform.instance.pickFile(
      dialogTitle: 'Выберите файл резервной копии',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    final path = file.path;
    if (path != null) return File(path).readAsString();
    // Если платформа вернула только поток — читаем через XFile.
    return file.xFile.readAsString();
  }

  /// Разбирает JSON резервной копии в список записей дневника.
  /// Возвращает null, если формат некорректен.
  /// Поддерживает поля result, weight, count, method (v1.1+).
  static List<DiaryEntry>? parseBackup(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final rawEntries = map['entries'] as List<dynamic>? ?? const [];
      return rawEntries.map((e) {
        final raw = e as Map<String, dynamic>;
        return DiaryEntry(
          uuid: raw['uuid'] as String?,
          date: DateTime.tryParse(raw['date'] as String? ?? '') ?? DateTime.now(),
          species: raw['species'] as String? ?? '',
          location: raw['location'] as String?,
          weather: raw['weather'] as String?,
          notes: raw['notes'] as String?,
          latitude: (raw['latitude'] as num?)?.toDouble(),
          longitude: (raw['longitude'] as num?)?.toDouble(),
          photoPath: raw['photo_path'] as String?,
          result: raw['result'] as String? ?? '',
          weight: (raw['weight'] as num?)?.toDouble(),
          count: (raw['count'] as num?)?.toInt(),
          method: raw['method'] as String?,
          updatedAt: raw['updated_at'] != null
              ? DateTime.tryParse(raw['updated_at'] as String)
              : null,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  static String _fmtDate(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();
}