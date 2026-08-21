import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/diary_entry.dart';

/// Локальная база данных (офлайн). Хранит записи дневника.
class AppDatabase {
  static const _dbName = 'hunter.db';
  static const _dbVersion = 1;

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
            date TEXT NOT NULL,
            location TEXT,
            weather TEXT,
            species TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            photo_path TEXT,
            notes TEXT
          )
        ''');
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
}