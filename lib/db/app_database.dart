import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/diary_entry.dart';

/// Локальная база данных (офлайн). Хранит записи дневника.
class AppDatabase {
  static const _dbName = 'hunter.db';
  static const _dbVersion = 7;

  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE diary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT,
            updated_at TEXT,
            date TEXT NOT NULL,
            location TEXT,
            weather TEXT,
            species TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            photo_path TEXT,
            notes TEXT,
            result TEXT DEFAULT '',
            weight REAL,
            count INTEGER,
            method TEXT
          )
        ''');
        await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_diary_uuid ON diary_entries(uuid) WHERE uuid IS NOT NULL');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE diary_entries ADD COLUMN uuid TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE diary_entries ADD COLUMN result TEXT DEFAULT ''");
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE diary_entries ADD COLUMN weight REAL');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN count INTEGER');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN method TEXT');
        }
        if (oldVersion < 5) {
          // Убираем возможные дубли по uuid (оставляем самый старый id),
          // затем ставим уникальный индекс — защита от дублей при синхронизации.
          await db.execute('''
            DELETE FROM diary_entries
            WHERE id NOT IN (
              SELECT MIN(id) FROM diary_entries
              WHERE uuid IS NOT NULL AND uuid <> '' GROUP BY uuid
            ) AND uuid IS NOT NULL AND uuid <> ''
          ''');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_diary_uuid ON diary_entries(uuid) WHERE uuid IS NOT NULL');
        }
        if (oldVersion < 6) {
          // Колонка для last-write-wins при синхронизации.
          await db.execute('ALTER TABLE diary_entries ADD COLUMN updated_at TEXT');
          await db.execute('''
            UPDATE diary_entries SET updated_at = date WHERE updated_at IS NULL
          ''');
        }
        if (oldVersion < 7) {
          // Индекс для ускорения синхронизации: поиск по uuid и user_id.
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_diary_entries_uuid ON diary_entries(uuid)');
        }
      },
    );
  }

  Future<List<DiaryEntry>> getDiaryEntries() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'diary_entries',
      orderBy: 'date DESC',
    );
    return rows.map(DiaryEntry.fromMap).toList();
  }

  Future<int> getDiaryCount() async {
    final db = await AppDatabase.instance;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM diary_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> insertDiaryEntry(DiaryEntry entry) async {
    final db = await AppDatabase.instance;
    final data = entry.toMap()..remove('id');
    data['updated_at'] = entry.updatedAt?.toIso8601String() ??
        DateTime.now().toIso8601String();
    return db.insert(
      'diary_entries',
      data,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> deleteDiaryEntry(int id) async {
    final db = await AppDatabase.instance;
    return db.delete('diary_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateDiaryEntry(DiaryEntry entry) async {
    final db = await AppDatabase.instance;
    final data = entry.toMap()..remove('id');
    data['updated_at'] = entry.updatedAt?.toIso8601String() ??
        DateTime.now().toIso8601String();
    return db.update('diary_entries', data,
        where: 'id = ?', whereArgs: [entry.id]);
  }
}