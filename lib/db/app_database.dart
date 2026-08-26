import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/diary_entry.dart';

/// Локальная база данных (офлайн). Хранит записи дневника.
class AppDatabase {
  static const _dbName = 'hunter.db';
  static const _dbVersion = 3;

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
            date TEXT NOT NULL,
            location TEXT,
            weather TEXT,
            species TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            photo_path TEXT,
            notes TEXT,
            result TEXT DEFAULT ''
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE diary_entries ADD COLUMN uuid TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE diary_entries ADD COLUMN result TEXT DEFAULT ''");
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
    return db.insert('diary_entries', entry.toMap()..remove('id'));
  }

  Future<int> deleteDiaryEntry(int id) async {
    final db = await AppDatabase.instance;
    return db.delete('diary_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateDiaryEntry(DiaryEntry entry) async {
    final db = await AppDatabase.instance;
    return db.update('diary_entries', entry.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [entry.id]);
  }
}