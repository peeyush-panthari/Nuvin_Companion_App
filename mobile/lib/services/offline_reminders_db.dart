import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalReminder {
  final String id;
  final String type;
  final String title;
  final String schedule;
  final bool isRecurring;
  final String status;
  final String? nextFireAt;

  LocalReminder({
    required this.id,
    required this.type,
    required this.title,
    required this.schedule,
    required this.isRecurring,
    this.status = 'active',
    this.nextFireAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'title': title,
    'schedule': schedule,
    'is_recurring': isRecurring ? 1 : 0,
    'status': status,
    'next_fire_at': nextFireAt,
  };

  factory LocalReminder.fromMap(Map<String, dynamic> map) => LocalReminder(
    id: map['id'],
    type: map['type'],
    title: map['title'],
    schedule: map['schedule'],
    isRecurring: map['is_recurring'] == 1,
    status: map['status'],
    nextFireAt: map['next_fire_at'],
  );
}

class OfflineRemindersDatabase {
  static final OfflineRemindersDatabase instance = OfflineRemindersDatabase._init();
  static Database? _database;

  OfflineRemindersDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('nuvin_offline_reminders.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_reminders (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            schedule TEXT NOT NULL,
            is_recurring INTEGER NOT NULL,
            status TEXT NOT NULL,
            next_fire_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE local_acknowledgements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reminder_id TEXT NOT NULL,
            action TEXT NOT NULL,
            acknowledged_at TEXT NOT NULL,
            synced_to_cloud INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<void> syncFromCloudManifest(List<dynamic> cloudReminders) async {
    final db = await database;
    final batch = db.batch();

    for (var r in cloudReminders) {
      batch.insert(
        'local_reminders',
        {
          'id': r['id'],
          'type': r['type'],
          'title': r['title'],
          'schedule': r['schedule'],
          'is_recurring': (r['is_recurring'] ?? true) ? 1 : 0,
          'status': r['status'] ?? 'active',
          'next_fire_at': r['next_fire_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<LocalReminder>> getActiveReminders() async {
    final db = await database;
    final result = await db.query(
      'local_reminders',
      where: 'status = ?',
      whereArgs: ['active'],
    );
    return result.map((r) => LocalReminder.fromMap(r)).toList();
  }

  Future<void> recordAction(String reminderId, String action) async {
    final db = await database;
    await db.insert('local_acknowledgements', {
      'reminder_id': reminderId,
      'action': action,
      'acknowledged_at': DateTime.now().toIso8601String(),
      'synced_to_cloud': 0,
    });
  }
}
