import 'dart:io';

import 'package:sqflite/sqflite.dart';

abstract class DatabaseStorage {
  final int version;

  DatabaseStorage(this.version);

  Database db;

  Future migrate(Database db, int migration);

  void enable(Database db) {
    this.db = db;
  }

  Future<void> close() {
    return db.close();
  }

  Future delete() async {
    await close();
    final file = File(db.path);
    return file.exists().then((exists) {
      if (exists) return file.delete();
      return null;
    });
  }

  Future<R> openSession<R>(Future<R> action(Transaction t),
      {bool exclusive}) async {
    return db.transaction((t) async {
      return action(t);
    }, exclusive: exclusive);
  }
}

Future<T> openStorage<T extends DatabaseStorage>(String dbPath, T storage,
    {bool cleanup = false}) async {
  if (cleanup) {
    await openDatabase(dbPath).then((db) async {
      await db.close();
      return File(db.path).delete();
    });
  }
  var db = await openDatabase(dbPath,
      singleInstance: false,
      version: storage.version, onUpgrade: (db, oldVersion, newVersion) async {
    print("Upgrading DB from $oldVersion to $newVersion");
    for (var i = oldVersion; i < newVersion; i++) {
      await storage.migrate(db, i);
    }
  });
  storage.enable(db);
  return storage;
}
