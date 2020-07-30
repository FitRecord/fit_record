import 'dart:collection';
import 'dart:convert';

import 'package:android/data_provider.dart';
import 'package:android/data_sensor.dart';
import 'package:android/data_storage_profiles.dart';
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
  Queue<Trackpoint> trackpoints;

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
    var statusText = 'FitRecord is ready';
    final record = await active();
    final profile = await profiles.one(record?.profileID);
    final data = Map<String, double>();
    if (record != null) data['status'] = record.status.toDouble();
    if (trackpoints == null && record != null) {
      cache = Map<String, double>();
      trackpoints = DoubleLinkedQueue<Trackpoint>();
      final list = await loadTrackpoints(record);
      _processTrackpoints(
          profile, sensors, list, cache, trackpoints, null, null);
    }
//    print('New sensor data: $args');
    final ts = args.values
        .map((e) => e['ts']?.toInt())
        .firstWhere((el) => el != null, orElse: () => null);
    final dataUpdated = ts == null ||
        trackpoints?.isEmpty != false ||
        trackpoints.last.timestamp < ts;
    if (!dataUpdated) return null;
    args.forEach((key, value) {
      final sensorData = (value as Map)
          .map((key, value) => MapEntry<String, double>(key, value));
      final handlerData = sensors
          .handler(key)
          .handleData(profile, sensorData, trackpoints, cache);
      data.addAll(handlerData);
    });
    if (record?.status == 0) {
      // recording is active
      final newTrackpoint = await _addTrackpoint(record, ts, args, 0);
      _appendTrackpoint(profile, trackpoints, newTrackpoint);
    }
    if (profile != null) statusText = profile.makeStatusText(sensors, data);
    return SensorsDataResult(data, statusText);
  }

  _appendTrackpoint(
      Profile profile, Queue<Trackpoint> trackpoints, Trackpoint trackpoint) {
    while (trackpoints.length >= profile.maxTrackpoints)
      trackpoints.removeFirst();
    trackpoints.add(trackpoint);
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
    DateTime start, end;
    if (range != null) {
      start = nextFrom(from, range, -shift);
      end = nextFrom(start, range, 1);
      where.add('"started" >= ? and "started" < ?');
      whereArgs.add(start.millisecondsSinceEpoch);
      whereArgs.add(end.millisecondsSinceEpoch);
    }
    if (profile != null) {
      where.add('"profile_id"=?');
      whereArgs.add(profile.id);
    }
    final profilesList = await profiles.all();
    final list = await openSession((t) async {
      final list = await t.query(
        '"records"',
        where: where.join(' and '),
        whereArgs: whereArgs,
        orderBy: '"started" desc',
      );
      return list.map((row) => _toRecord(row)).toList();
    });
    final result = HistoryResult(list, start, end?.subtract(Duration(days: 1)),
        Map<String, double>(), LinkedHashMap<int, double>());
    if (statKey != null) {
      final keys = [
        'time_total',
        'loc_total_distance',
      ];
      _calcHistoryStats(result, range, keys, statKey);
    }
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
      Queue<Trackpoint> trackpoints,
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
        _appendTrackpoint(profile, trackpoints, element);
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
    final trackpoints = DoubleLinkedQueue<Trackpoint>();
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
