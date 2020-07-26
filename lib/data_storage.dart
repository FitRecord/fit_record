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

  List<Map<String, double>> _zonesJson(String key, String value) {
    try {
      Map checks = configJson['zones'];
      if (checks != null && checks[key] == true) {
        List list = jsonDecode(value);
        if (list.length == 5) {
          return list.map((e) => (e as Map).cast<String, double>()).toList();
        }
      } else
        return null;
    } catch (e) {
//      print('JSON decode error: $e');
    }
    return List.generate(5, (index) => Map<String, double>());
  }

  get zonesHrmJson => _zonesJson('hrm', zonesHrm);
  get zonesPaceJson => _zonesJson('pace', zonesPace);
  get zonesPowerJson => _zonesJson('power', zonesPower);

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

  String makeStatusText(
      SensorIndicatorManager sensors, Map<String, double> data) {
    final time = sensors.formatFor('time_total', data);
    final distance = sensors.formatFor('loc_total_distance', data);
    return 'Time: $time, distance: ${distance} km';
  }
}

class Record {
  final int id, started, profileID, status;
  final String uid;
  String title, description, meta;
  List<Map<String, double>> trackpoints;
  List<int> laps;

  Record(
      this.id, this.uid, this.profileID, this.started, this.status, this.meta);

  Map<String, dynamic> get metaJson {
    try {
      if (meta != null) return jsonDecode(meta);
    } catch (e) {}
    return null;
  }

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

class SensorsDataResult {
  final Map<String, double> data;
  final String status;

  SensorsDataResult(this.data, this.status);
}

enum HistoryRange { Week, Month, Year }

class HistoryResult {
  final List<Record> records;
  final DateTime start, finish;
  final Map<String, double> stats;
  final LinkedHashMap<int, double> keyStats;

  HistoryResult(
      this.records, this.start, this.finish, this.stats, this.keyStats);
}

class RecordStorage extends DatabaseStorage {
  RecordStorage([ChannelDbDelegate delegate]) : super(2, delegate);

  Map<String, double> cache;
  List<Trackpoint> trackpoints;

  Record _toRecord(Map<String, dynamic> row) {
    final r = Record(row['id'], row['uid'], row['profile_id'], row['started'],
        row['status'], row['meta']);
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

  void _clear() {
    cache = null;
    trackpoints = null;
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

  Future pause(SensorIndicatorManager sensors) async {
    final r = await active();
    if (r != null && r.status == 0) {
      await _addTrackpoint(r, null, Map(), 1);
      sensors
          .all()
          .forEach((element) => element.handlePause(trackpoints, cache));
      trackpoints.clear();
      return openSession((t) => t.update('"records"', {'status': 1},
          where: '"id"=?', whereArgs: [r.id]));
    }
  }

  Future<int> lap(SensorIndicatorManager sensors) async {
    final r = await active();
    if (r != null && r.status == 0) {
      await _addTrackpoint(r, null, Map(), 2);
      sensors.all().forEach((element) => element.handleLap(trackpoints, cache));
      return r.id;
    }
    return null;
  }

  Future<int> finish(DataProvider provider, bool save) async {
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
    _clear();
    if (save) {
      await loadOne(provider.indicators, provider.profiles, r.id);
      return r.id;
    }
    return null;
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

  Future<SensorsDataResult> sensorsData(
      Map args, SensorIndicatorManager sensors, ProfileStorage profiles) async {
    final record = await active();
    final profile = await profiles.one(record?.profileID);
    final data = Map<String, double>();
    if (record != null) data['status'] = record.status.toDouble();
    if (trackpoints == null && record != null) {
      cache = Map<String, double>();
      trackpoints = <Trackpoint>[];
      final list = await loadTrackpoints(record);
      _processTrackpoints(
          profile, sensors, list, cache, trackpoints, null, null);
    }
//    print('New sensor data: $args');
    final ts = args.values
        .map((e) => e['ts']?.toInt())
        .firstWhere((el) => el != null, orElse: () => null);
    final dataUpdated = (ts == null ||
            trackpoints?.isEmpty != false ||
            trackpoints.last.timestamp < ts) &&
        record?.status == 0;
    args.forEach((key, value) {
      final sensorData = (value as Map)
          .map((key, value) => MapEntry<String, double>(key, value));
      final handlerData = sensors.handler(key).handleData(
          profile, sensorData, dataUpdated ? trackpoints : null, cache);
      data.addAll(handlerData);
    });
    if (dataUpdated) {
      // recording is active
      final newTrackpoint = await _addTrackpoint(record, ts, args, 0);
      trackpoints.add(newTrackpoint);
    }
    String statusText;
    if (record != null) {
      final profile = await profiles.one(record.profileID);
      if (profile != null) statusText = profile.makeStatusText(sensors, data);
    }
    return SensorsDataResult(data, statusText);
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

  Future<List<Trackpoint>> loadTrackpoints(Record record) async {
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

  DateTime nextFrom(DateTime from, HistoryRange range, [int mul = 0]) {
    switch (range) {
      case HistoryRange.Week:
        final dt = from.subtract(Duration(days: -7 * mul + from.weekday - 1));
        return DateTime(dt.year, dt.month, dt.day);
      case HistoryRange.Month:
        int month = from.month + mul;
        int year = from.year;
        while (month < 1) {
          month += 12;
          year -= 1;
        }
        while (month > 12) {
          month -= 12;
          year += 1;
        }
        return DateTime(year, month, 1);
      case HistoryRange.Year:
        return DateTime(from.year + mul, 1, 1);
    }
    return from;
  }

  void _calcHistoryStats(
      HistoryResult result, HistoryRange range, List<String> keys, String key) {
    switch (range) {
      case HistoryRange.Week:
        List.generate(7, (index) => index).forEach((val) {
          final dt = result.start.subtract(Duration(days: -val));
          result.keyStats[dt.weekday] = null;
        });
        break;
      case HistoryRange.Month:
        List.generate(result.finish.difference(result.start).inDays + 1,
            (index) => index).forEach((val) {
          final dt = result.start.subtract(Duration(days: -val));
          result.keyStats[dt.day] = null;
        });
        break;
      case HistoryRange.Year:
        List.generate(12, (index) => index + result.start.month).forEach(
            (val) => result.keyStats[val > 12 ? val % 12 : val] = null);
        break;
    }
    result.records.forEach((r) {
      final meta = r.metaJson;
      if (meta == null) return;
      _incStat(Map map, dynamic key, String att) {
        map[key] = (map[key] ?? 0.0) + (meta[att] ?? 0.0);
      }

      int group;
      final dt = DateTime.fromMillisecondsSinceEpoch(r.started);
      switch (range) {
        case HistoryRange.Week:
          group = dt.weekday;
          break;
        case HistoryRange.Month:
          group = dt.day;
          break;
        case HistoryRange.Year:
          group = dt.month;
          break;
      }
      keys.forEach((att) {
        _incStat(result.stats, att, att);
      });
      _incStat(result.keyStats, group, key);
    });
//    print('Stat: ${result.keyStats} - ${result.start} - ${result.finish}');
  }

  Future<HistoryResult> history(
      ProfileStorage profiles, HistoryRange range, DateTime from, int shift,
      {Profile profile, String type, String statKey}) async {
    final where = ['"status"=?'];
    final whereArgs = <dynamic>[2];
    final start = nextFrom(from, range, -shift);
    final end = nextFrom(start, range, 1);
    where.add('"started" >= ? and "started" < ?');
    whereArgs.add(start.millisecondsSinceEpoch);
    whereArgs.add(end.millisecondsSinceEpoch);
    if (profile != null) {
      where.add('"profile_id"=?');
      whereArgs.add(profile.id);
    }
    final profilesList = await profiles.all();
    final list = await openSession((t) async {
      final list = await t.query('"records"',
          where: where.join(' and '),
          whereArgs: whereArgs,
          orderBy: '"started" desc',
          limit: 50);
      return list.map((row) => _toRecord(row)).toList();
    });
    final result = HistoryResult(list, start, end.subtract(Duration(days: 1)),
        Map<String, double>(), LinkedHashMap<int, double>());
    final keys = [
      'time_total',
      'loc_total_distance',
    ];
    _calcHistoryStats(result, range, keys, statKey);
    return result;
  }

  Future deleteOne(int id) async {
    return openSession((t) async {
      await t.delete('"trackpoints"', where: '"record_id"=?', whereArgs: [id]);
      return t.delete('"records"', where: '"id"=?', whereArgs: [id]);
    });
  }

  _processTrackpoints(
      Profile profile,
      SensorIndicatorManager sensors,
      List<Trackpoint> list,
      Map<String, double> cache,
      List<Trackpoint> trackpoints,
      List<int> laps,
      List<Map<String, double>> results) {
    list.forEach((element) {
      if (element.status == 2) {
        laps?.add(results?.length - 1);
        sensors
            .all()
            .forEach((element) => element.handleLap(trackpoints, cache));
      }
      if (element.status == 1) {
        sensors
            .all()
            .forEach((element) => element.handlePause(trackpoints, cache));
        trackpoints.clear();
      }
      if (element.status == 0) {
        final data = Map<String, double>();
        element.data.forEach((key, value) {
          final sensorData = (value as Map)
              .map((key, value) => MapEntry<String, double>(key, value));
          final handlerData = sensors
              .handler(key)
              .handleData(profile, sensorData, trackpoints, cache);
          data.addAll(handlerData);
        });
        results?.add(data);
        trackpoints.add(element);
      }
    });
  }

  Future<Record> _updateMeta(Record item) async {
    if (item.trackpoints?.isNotEmpty != true) {
      return item; // Invalid data - no trackpoints
    }
    final last = item.trackpoints.last;
    final meta = Map<String, dynamic>();
    [
      'time_total',
      'time_lap_index',
      'loc_total_distance',
      'loc_total_speed_ms',
      'loc_total_pace_sm',
      'sensor_hrm_total_avg',
      'sensor_power_total_avg',
      'sensor_cadence_total_avg',
    ].forEach((element) {
      if (last.containsKey(element)) meta[element] = last[element];
    });
    item.meta = jsonEncode(meta);
    await openSession((t) => t.update('"records"', {'meta': item.meta},
        where: '"id"=?', whereArgs: [item.id]));
    return item;
  }

  Future<Record> loadOne(
      SensorIndicatorManager sensors, ProfileStorage profiles, int id) async {
    final item = await one(id);
    if (item == null || item.status != 2) return null;
    final profile = await profiles.one(item.profileID);
    item.trackpoints = <Map<String, double>>[];
    item.laps = <int>[];
    final tps = await loadTrackpoints(item);
    final cache = Map<String, double>();
    final trackpoints = <Trackpoint>[];
    _processTrackpoints(
        profile, sensors, tps, cache, trackpoints, item.laps, item.trackpoints);
    if (item.metaJson == null) {
      return _updateMeta(item);
    }
    return item;
  }

  Future updateFields(Record record) async {
    return openSession((t) => t.update(
        '"records"', {'title': record.title, 'description': record.description},
        where: '"id"=?', whereArgs: [record.id]));
  }

  Future<int> addManual(
      DataProvider provider, int id, DateTime dateTime, int duration,
      {String title, String description, double distance}) {
    final trackpoints =
        provider.indicators.makeManualTrackpoints(dateTime, duration, distance);
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
      await loadOne(provider.indicators, provider.profiles, added);
      return added;
    });
  }

  Future<Record> one(int id) async {
    final list = await openSession((t) => t.query('"records"',
        where: '"id"=?',
        whereArgs: [id]).then((list) => list.map((e) => _toRecord(e))));
    return list.isNotEmpty ? list.first : null;
  }
}

class ProfileStorage extends DatabaseStorage {
  ProfileStorage([ChannelDbDelegate delegate]) : super(3, delegate);

  Profile _toProfile(Map<String, dynamic> e) {
    final profile = Profile(e['id'], e['title'], e['type'], e['icon']);
    profile.screens = e['screens'];
    profile.config = e['config'];
    profile.zonesPace = e['zones_pace'];
    profile.zonesHrm = e['zones_hrm'];
    profile.zonesPower = e['zones_power'];
    return profile;
  }

  Future<Profile> one(int id) async {
    if (id == null) return null;
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

  Future<String> updateJsonField(
      Profile profile, String field, dynamic json) async {
    int id = await ensure(profile);
    final jsonStr = jsonEncode(json);
    await openSession((t) => t.update('"profiles"', {field: jsonStr},
        where: '"id"=?', whereArgs: [id]));
    return jsonStr;
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

  Future<Profile> findByType(String type) async {
    return all().then(
        (list) => list.firstWhere((p) => p.type == type, orElse: () => null));
  }
}
