import 'dart:collection';
import 'dart:convert';

import 'package:android/data_provider.dart';
import 'package:android/data_sensor.dart';
import 'package:android/ui_utils.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'data_db.dart';

class Trackpoint {
  final int timestamp;
  final int status;
  Map data;

  Trackpoint(this.timestamp, this.status, this.data);
}

class Profile {
  int id;
  String title, type, icon;
  int lastUsed;
  String screens, screensExt, zonesHrm, zonesPace, zonesPower, config;

  Map<String, dynamic> get configJson {
    try {
      return jsonDecode(config);
    } catch (e) {
//      print('JSON decode error: $e');
    }
    return Map<String, dynamic>();
  }

  List<List<List<Map<String, dynamic>>>> get screensJson {
    try {
      return (jsonDecode(screens) as List<dynamic>)
          .map((e) => (e as List<dynamic>)
              .map((e) => (e as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>)
                  .toList())
              .toList())
          .toList();
    } catch (e) {}
    return [defaultScreen('total', false)];
  }

  List<List<Map<String, dynamic>>> defaultScreen(String scope, bool overview) {
    if (overview) {
      return [
        [
          {
            'id': 'time_$scope',
          }
        ],
        [
          {'id': 'loc_${scope}_distance'},
          {'id': 'loc_${scope}_${speedIndicator()}'},
        ],
      ];
    }
    return [
      [
        {
          'id': 'time_${scope}',
        }
      ],
      [
        {'id': speedIndicator()},
        {'id': 'loc_${scope}_distance'},
      ],
      [
        {'id': 'loc_${scope}_${speedIndicator()}'},
        {'id': 'loc_altitude'},
      ]
    ];
  }

  Profile(this.id, this.title, this.type, this.icon);

  String speedIndicator() {
    switch (type) {
      case 'Running':
        return 'pace_sm';
    }
    return 'speed_ms';
  }
}

class Record {
  final int id, started, profileID, status;
  final String uid;
  String title, description;
  List<Map<String, double>> trackpoints;
  List<int> laps;

  Record(this.id, this.uid, this.profileID, this.started, this.status);

  String smartTitle() {
    return title ??
        dateTimeFormat().format(DateTime.fromMillisecondsSinceEpoch(started));
  }

  Map<int, double> extractData(String key, int from, int to) {
    if (trackpoints?.isNotEmpty != true) return null;
    if (trackpoints.last[key] == null) return null;
    if (to == null) to = trackpoints.length - 1;
    if (from > to) return null;

    double start = trackpoints[from]['time_total'];
    return LinkedHashMap.fromEntries(
        trackpoints.getRange(from, to + 1).map((e) {
      return MapEntry<int, double>(
          ((e['time_total'] - start) / 1000).round(), e[key]);
    }));
  }
}

class RecordStorage extends DatabaseStorage {
  RecordStorage() : super(2);

  final cache = Map<String, double>();
  List<Trackpoint> trackpoints;

  Record _toRecord(Map<String, dynamic> row) {
    final r = Record(row['id'], row['uid'], row['profile_id'], row['started'],
        row['status']);
    r.title = row['title'];
    r.description = row['description'];
    return r;
  }

  Future<Record> active() async {
    final list = await openSession((t) => t
        .query('"records"', where: '"status"!=2')
        .then((list) => list.map((e) => _toRecord(e))));
    return list.isNotEmpty ? list.first : null;
  }

  Future start(int profileID) async {
    final r = await active();
    if (r == null) {
      // No active records - start new one
      return openSession((t) => t.insert('"records"', {
            'uid': Uuid().v4(),
            'profile_id': profileID,
            'started': DateTime.now().millisecondsSinceEpoch,
            'status': 0,
          }));
    } else {
      if (r.status == 1) {
        // Paused - resume
        return openSession((t) => t.update('"records"', {'status': 0},
            where: '"id"=?', whereArgs: [r.id]));
      }
    }
  }

  Future pause() async {
    final r = await active();
    if (r != null && r.status == 0) {
      final newTrackpoint = await _addTrackpoint(r, null, Map(), 1);
      trackpoints.add(newTrackpoint);
      return openSession((t) => t.update('"records"', {'status': 1},
          where: '"id"=?', whereArgs: [r.id]));
    }
  }

  Future<int> lap() async {
    final r = await active();
    if (r != null && r.status == 0) {
      final newTrackpoint = await _addTrackpoint(r, null, Map(), 2);
      trackpoints.add(newTrackpoint);
      return r.id;
    }
    return null;
  }

  Future<int> finish(bool save) async {
    print('Save: $save');
    final r = await active();
    if (r == null) return null;
    await openSession((t) async {
      if (save) {
        return t.update('"records"', {'status': 2},
            where: '"id"=?', whereArgs: [r.id]);
      } else {
        await t
            .delete('"trackpoints"', where: '"record_id"=?', whereArgs: [r.id]);
        return t.delete('"records"', where: '"id"=?', whereArgs: [r.id]);
      }
    });
    trackpoints = null;
    cache.clear();
    return save ? r.id : null;
  }

  Future<List<Map<String, int>>> sensorStatus(
      Map args, SensorIndicatorManager sensors) async {
    return args
        .map((key, value) =>
            MapEntry(key, (value as Map).cast<String, double>()))
        .entries
        .where((el) => el.value.containsKey('connected'))
        .map((data) => <String, int>{
              'type': data.value['type']?.toInt(),
              'battery': data.value['battery']?.toInt(),
              'connected': data.value['connected'].toInt(),
            })
        .toList();
  }

  Future<Map<String, double>> sensorsData(
      Map args, SensorIndicatorManager sensors) async {
    final record = await active();
    final data = Map<String, double>();
    if (record != null) data['status'] = record.status.toDouble();
    if (trackpoints == null && record != null) {
      final list = await _loadTrackpoints(record);
      cache.clear();
      trackpoints = <Trackpoint>[];
      list.forEach((element) {
        if (element.status == 0) {
          element.data.forEach((key, value) {
            final sensorData = (value as Map)
                .map((key, value) => MapEntry<String, double>(key, value));
            sensors.handler(key).handleData(sensorData, trackpoints, cache);
          });
        }
        trackpoints.add(element);
      });
    }
    print('New sensor data: $args');
    int ts = args.values
        .map((e) => e['ts']?.toInt())
        .firstWhere((el) => el != null, orElse: () => null);
    if (ts != null &&
        trackpoints != null &&
        trackpoints.isNotEmpty &&
        trackpoints.last.timestamp >= ts) {
      // Skip saving - timestamp is the same as before
      return null;
    }
    args.forEach((key, value) {
      final sensorData = (value as Map)
          .map((key, value) => MapEntry<String, double>(key, value));
      final handlerData =
          sensors.handler(key).handleData(sensorData, trackpoints, cache);
      data.addAll(handlerData);
    });
    if (record != null && record.status == 0) {
      // recording is active
      final newTrackpoint = await _addTrackpoint(record, ts, args, 0);
      trackpoints.add(newTrackpoint);
    }
    return data;
  }

  @override
  Future migrate(Database db, int migration) async {
    switch (migration) {
      case 1:
        await db.execute('''
          CREATE TABLE "records" (
            "id" INTEGER PRIMARY KEY,
            "uid" TEXT NOT NULL,
            "started" INT NOT NULL,
            "status" INT NOT NULL,
            "profile_id" INT NOT NULL,
            "title" TEXT,
            "description" TEXT,
            "meta" TEXT,
            "sync" TEXT,
            UNIQUE ("uid")
          );
        ''');

        await db.execute('''
          CREATE TABLE "trackpoints" (
            "id" INTEGER PRIMARY KEY,
            "added" INT NOT NULL,
            "status" INT NOT NULL,
            "record_id" INT NOT NULL,
            "data" TEXT
          );
        ''');

        await db.execute('''
          CREATE INDEX "trackpoints_record_id" ON "trackpoints" ("record_id");
        ''');
        break;
    }
  }

  Future<List<Trackpoint>> _loadTrackpoints(Record record) async {
    return openSession((t) async {
      final list = await t.query('"trackpoints"',
          where: '"record_id"=?', whereArgs: [record.id]);
      return list.map((item) {
        final data = jsonDecode(item['data']) as Map;
        return Trackpoint(item['added'], item['status'], data);
      }).toList();
    });
  }

  Future<Trackpoint> _addTrackpoint(
      Record record, int ts, Map data, int status) async {
    final timestamp = ts != null ? ts : DateTime.now().millisecondsSinceEpoch;
    final trackpoint = Trackpoint(timestamp, status, data);
    await openSession((t) => t.insert('"trackpoints"', {
          'record_id': record.id,
          'added': timestamp,
          'status': status,
          'data': jsonEncode(data),
        }));
    return trackpoint;
  }

  Future<List<Record>> history() async {
    return openSession((t) async {
      final list = await t.query('"records"',
          where: '"status"=?',
          whereArgs: [2],
          orderBy: '"started" desc',
          limit: 25);
      return list.map((row) => _toRecord(row)).toList();
    });
  }

  Future deleteOne(Record record) async {
    return openSession((t) async {
      await t.delete('"trackpoints"',
          where: '"record_id"=?', whereArgs: [record.id]);
      return t.delete('"records"', where: '"id"=?', whereArgs: [record.id]);
    });
  }

  Future<Record> loadOne(SensorIndicatorManager sensors, int id) async {
    final list = await openSession((t) => t.query('"records"',
        where: '"id"=?',
        whereArgs: [id]).then((list) => list.map((e) => _toRecord(e))));
    final item = list.isNotEmpty ? list.first : null;
    if (item == null || item.status != 2) return null;
    item.trackpoints = <Map<String, double>>[];
    item.laps = <int>[];
    final tps = await _loadTrackpoints(item);
    final cache = Map<String, double>();
    final trackpoints = <Trackpoint>[];
    tps.forEach((element) {
      if (element.status == 2) {
        item.laps.add(item.trackpoints.length - 1);
      }
      if (element.status == 0) {
        final data = Map<String, double>();
        element.data.forEach((key, value) {
          final sensorData = (value as Map)
              .map((key, value) => MapEntry<String, double>(key, value));
          final handlerData =
              sensors.handler(key).handleData(sensorData, trackpoints, cache);
          data.addAll(handlerData);
        });
        item.trackpoints.add(data);
      }
      trackpoints.add(element);
    });
    return item;
  }

  Future updateFields(Record record) async {
    return openSession((t) => t.update(
        '"records"', {'title': record.title, 'description': record.description},
        where: '"id"=?', whereArgs: [record.id]));
  }

  Future<int> addManual(
      SensorIndicatorManager sensors, int id, DateTime dateTime, int duration,
      {String title, String description, double distance}) {
    final trackpoints =
        sensors.makeManualTrackpoints(dateTime, duration, distance);
    return openSession((t) async {
      final added = await t.insert('"records"', {
        'uid': Uuid().v4(),
        'profile_id': id,
        'started': dateTime.millisecondsSinceEpoch,
        'status': 2,
        'title': title,
        'description': description,
      });
      await Future.wait(trackpoints.map((e) {
        return t.insert('"trackpoints"', {
          'record_id': added,
          'added': e.timestamp,
          'status': e.status,
          'data': jsonEncode(e.data),
        });
      }));
      return added;
    });
  }
}

class ProfileStorage extends DatabaseStorage {
  ProfileStorage() : super(3);

  Profile _toProfile(Map<String, dynamic> e) {
    final profile = Profile(e['id'], e['title'], e['type'], e['icon']);
    profile.screens = e['screens'];
    profile.config = e['config'];
    return profile;
  }

  Future<Profile> one(int id) async {
    final result = (await openSession((t) => t.query('"profiles"',
        where: '"id"=?',
        whereArgs: [id]).then((list) => list.map((e) => _toProfile(e)))));
    if (result.isNotEmpty) return result.first;
    return null;
  }

  Future<List<Profile>> all() async {
    final result = (await openSession((t) => t
            .query('"profiles" order by "last_used" desc, "title"')
            .then((list) => list.map((e) => _toProfile(e)))))
        .toList();
    if (result.isEmpty) {
      final profile = Profile(null, "Running", "Running", "run");
      result.add(profile);
    }
    return result;
  }

  Future<Iterable<Sensor>> allSensors() async {
    final list = <Sensor>[Sensor("location", "Location", true)];
    final sensors = await openSession((t) => t
        .query('"sensors"', orderBy: '"added"')
        .then((list) =>
            list.map((row) => Sensor(row['address'], row['name'], false))));
    list.addAll(sensors);
    return list;
  }

  Future<bool> addSensor(Sensor sensor) async {
    return openSession((t) async {
      final data = await t.query('"sensors"',
          where: '"address"=?', whereArgs: [sensor.id.toUpperCase()]);
      if (data.isNotEmpty) return false;
      await t.insert('"sensors"', {
        'address': sensor.id.toUpperCase(),
        'name': sensor.name,
        'added': DateTime.now().millisecondsSinceEpoch
      });
      return true;
    });
  }

  Future removeSensor(Sensor sensor) async {
    return openSession((t) => t.delete('"sensors"',
        where: '"address"=?', whereArgs: [sensor.id.toUpperCase()]));
  }

  Future<int> ensure(Profile profile) async {
    if (profile.id != null) return profile.id;
    final id = await openSession((t) => t.insert('"profiles"', {
          'title': profile.title,
          'type': profile.type,
          'icon': profile.icon,
        }));
    profile.id = id;
    return id;
  }

  @override
  Future migrate(Database db, int migration) async {
    switch (migration) {
      case 1:
        await db.execute('''
          CREATE TABLE "profiles" (
            "id" INTEGER PRIMARY KEY,
            "title" TEXT NOT NULL,
            "type" TEXT NOT NULL,
            "icon" TEXT NOT NULL,
            "color" TEXT,
            "last_used" INTEGER,
            "screens" TEXT,
            "screens_ext" TEXT,
            "zones_hrm" TEXT,
            "zones_pace" TEXT,
            "zones_power" TEXT,
            "config" TEXT
          );
        ''');
        break;
      case 2:
        await db.execute('''
          CREATE TABLE "sensors" (
            "address" TEXT NOT NULL PRIMARY KEY,
            "name" TEXT NOT NULL,
            "added" INT,
            "config" TEXT
          );
        ''');
        break;
    }
  }

  updateJsonField(Profile profile, String field, dynamic json) async {
    int id = await ensure(profile);
    await openSession((t) => t.update('"profiles"', {field: jsonEncode(json)},
        where: '"id"=?', whereArgs: [id]));
  }

  Future<Map> profileInfo(int id) async {
    final result = {
      'sensors': [
        {'id': 'time'}
      ]
    };
    final profile = await one(id);
    final Map<String, dynamic> sensorsChecks =
        profile.configJson['sensors'] ?? Map<String, dynamic>();
    final sensors = await allSensors();
    sensors.forEach((sensor) {
      if (sensorsChecks[sensor.id] != false)
        result['sensors'].add({'id': sensor.id});
    });
    return result;
  }
}
