import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('p2p_chat.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // ignore: unused_local_variable
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    // ignore: unused_local_variable
    const textType = 'TEXT NOT NULL';
    // ignore: unused_local_variable
    const boolType = 'BOOLEAN NOT NULL';

    await db.execute('''
CREATE TABLE contacts (
  id \$idType,
  username \$textType,
  identity_key \$textType
)
''');

    await db.execute('''
CREATE TABLE messages (
  id \$idType,
  peer_username \$textType,
  is_me \$boolType,
  content \$textType,
  timestamp \$textType
)
''');
  }

  Future<void> saveMessage(String peerUsername, bool isMe, String content) async {
    final db = await instance.database;
    await db.insert('messages', {
      'peer_username': peerUsername,
      'is_me': isMe ? 1 : 0,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getMessages(String peerUsername) async {
    final db = await instance.database;
    return await db.query(
      'messages',
      where: 'peer_username = ?',
      whereArgs: [peerUsername],
      orderBy: 'timestamp ASC',
    );
  }
}
