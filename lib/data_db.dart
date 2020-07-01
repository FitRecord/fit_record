import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

class ChannelDbDelegate extends DatabaseExecutor {
  final String _channelName;
  MethodChannel _channel;

  ChannelDbDelegate(this._channelName) {
    _channel = OptionalMethodChannel(_channelName);
  }

  @override
  Future<int> delete(String table, {String where, List whereArgs}) {
    return _channel.invokeMethod(
        'delete', {'table': table, 'where': where, 'whereArgs': whereArgs});
  }

  @override
  Future<void> execute(String sql, [List arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<int> insert(String table, Map values,
      {String nullColumnHack, ConflictAlgorithm conflictAlgorithm}) {
    return _channel.invokeMethod('insert',
        {'table': table, 'values': values, 'nullColumnHack': nullColumnHack});
  }

  @override
  Future<int> update(String table, Map values,
      {String where, List whereArgs, ConflictAlgorithm conflictAlgorithm}) {
    return _channel.invokeMethod('update', {
      'table': table,
      'values': values,
      'where': where,
      'whereArgs': whereArgs
    });
  }

  @override
  Future<List<Map<String, dynamic>>> query(String table,
      {bool distinct,
      List<String> columns,
      String where,
      List whereArgs,
      String groupBy,
      String having,
      String orderBy,
      int limit,
      int offset}) {
    return _channel.invokeMethod<List>('query', {
      'table': table,
      'distinct': distinct,
      'columns': columns,
      'where': where,
      'whereArgs': whereArgs,
      'groupBy': groupBy,
      'having': having,
      'orderBy': orderBy,
      'limit': limit,
      'offset': offset,
    }).then((value) =>
        value.cast<Map>().map((e) => e.cast<String, dynamic>()).toList());
  }

  @override
  Batch batch() {
    throw UnimplementedError();
  }

  @override
  Future<int> rawDelete(String sql, [List arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<int> rawInsert(String sql, [List arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<int> rawUpdate(String sql, [List arguments]) {
    throw UnimplementedError();
  }
}

class DbWrapperChannel {
  final String _channelName;
  final DatabaseStorage _db;
  MethodChannel _channel;

  DbWrapperChannel(this._channelName, this._db) {
    _channel = OptionalMethodChannel(_channelName);
    _channel.setMethodCallHandler((call) => _callHandler(call));
  }

  Future _callHandler(MethodCall call) async {
    final args = call.arguments as Map;
    switch (call.method) {
      case 'delete':
        return _db.openSession((t) => t.delete(args['table'],
            where: args['where'], whereArgs: args['whereArgs']));
      case 'insert':
        return _db.openSession((t) => t.insert(args['table'], args['values'],
            nullColumnHack: args['nullColumnHack']));
      case 'update':
        return _db.openSession((t) => t.update(args['table'], args['values'],
            where: args['where'], whereArgs: args['whereArgs']));
      case 'query':
        return _db.openSession((t) => t.query(
              args['table'],
              distinct: args['distinct'],
              columns: args['columns'],
              where: args['where'],
              whereArgs: args['whereArgs'],
              groupBy: args['groupBy'],
              having: args['having'],
              orderBy: args['orderBy'],
              limit: args['limit'],
              offset: args['offset'],
            ));
    }
    throw UnimplementedError(
        "Call ${call.method} not yet implemented in DbWrapperChannel");
  }
}

abstract class DatabaseStorage {
  final int version;
  DatabaseExecutor dbDelegate;

  DatabaseStorage(this.version, [this.dbDelegate]);

  Database db;

  Future migrate(Database db, int migration);

  void enable(Database db) {
    this.db = db;
  }

  Future<void> close() {
    if (dbDelegate != null) return Future.value();
    return db.close();
  }

  Future delete() async {
    if (dbDelegate != null) return Future.value();
    await close();
    final file = File(db.path);
    return file.exists().then((exists) {
      if (exists) return file.delete();
      return null;
    });
  }

  Future<R> openSession<R>(Future<R> action(DatabaseExecutor t),
      {bool exclusive}) async {
    if (dbDelegate != null) return action(dbDelegate);
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
  var db = await openDatabase(dbPath, version: storage.version,
      onUpgrade: (db, oldVersion, newVersion) async {
    print("Upgrading DB from $oldVersion to $newVersion");
    for (var i = oldVersion; i < newVersion; i++) {
      await storage.migrate(db, i);
    }
  });
  storage.enable(db);
  return storage;
}
