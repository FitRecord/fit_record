import 'dart:collection';
import 'dart:convert';

import 'package:android/data_provider.dart';
import 'package:android/data_sensor.dart';
import 'package:android/data_sync_impl.dart';
import 'package:sqflite/sqflite.dart';

import 'data_db.dart';

class ActivityType {
  final String name;
  final String icon;
  final String group;

  ActivityType(this.name, this.icon, this.group);
}

final ActivityTypesNames = [
  'Running',
  'Cycling',
  'MountainBiking',
  'Walking',
  'Hiking',
  'DownhillSkiing',
  'CrossCountrySkiing',
  'Snowboarding',
  'Skating',
  'Swimming',
  'Wheelchair',
  'Rowing',
  'Elliptical',
  'Gym',
  'Climbing',
  'RollerSkiing',
  'StrengthTraining',
  'StandUpPaddling',
  'Other',
];

final ActivityTypes = LinkedHashMap.fromIterables(ActivityTypesNames, [
  ActivityType('Running', 'run', 'Running'),
  ActivityType('Cycling', 'bike', 'Cycling'),
  ActivityType('Mountain Biking', 'bike', 'Cycling'),
  ActivityType('Walking', 'walk', 'Running'),
  ActivityType('Hiking', 'hike', 'Running'),
  ActivityType('Downhill Skiing', 'ski', 'Skiing'),
  ActivityType('Cross-Country Skiing', 'ski_nordic', 'Skiing'),
  ActivityType('Snowboarding', 'snowboard', 'Skiing'),
  ActivityType('Skating', 'skate', 'Running'),
  ActivityType('Swimming', 'swim', 'Swimming'),
  ActivityType('Wheelchair', 'run', 'Running'),
  ActivityType('Rowing', 'row', 'Rowing'),
  ActivityType('Elliptical', 'run', 'Skiing'),
  ActivityType('Gym', 'dumbbell', 'Gym'),
  ActivityType('Climbing', 'hike', 'Running'),
  ActivityType('Roller Skiing', 'ski', 'Skiing'),
  ActivityType('Strength Training', 'dumbbell', 'Gym'),
  ActivityType('StandUpPaddling', 'row', 'Rowing'),
  ActivityType('Other', 'run', 'Running'),
]);

class Profile {
  int id;
  String title, icon;
  String type;
  int lastUsed;
  String screens, screensExt, zonesHrm, zonesPace, zonesPower, config;

  static List<String> icons = [
    'run',
    'bike',
    'row',
    'swim',
    'ski',
    'dumbbell',
    'walk',
    'hike',
    'skate',
    'ski_nordic',
    'snowboard',
  ];

  num get maxTrackpoints => 20;

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
      default:
        return 'speed_ms';
    }
  }

  String makeStatusText(
      SensorIndicatorManager sensors, Map<String, double> data) {
    final time = sensors.formatFor('time_total', data, withType: true);
    final distance =
        sensors.formatFor('loc_total_distance', data, withType: true);
    return 'Time: $time, distance: ${distance}';
  }
}

class SyncConfig {
  final int id;
  int direction, mode;
  final String service;
  String title, _config, _secrets;

  SyncProvider provider;

  SyncConfig(
    this.id,
    this.service,
    this.title,
    this.direction,
    this.mode,
    this._config,
    this._secrets,
  );

  get secretsJson => _secrets == null ? null : jsonDecode(_secrets);

  set secretsJson(dynamic value) =>
      _secrets = value == null ? null : jsonEncode(value);
}

class ProfileStorage extends DatabaseStorage {
  ProfileStorage([ChannelDbDelegate delegate]) : super(4, delegate);

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
            .query('"profiles" order by "last_used" desc, "id"')
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
      case 3:
        await db.execute('''
          CREATE TABLE "sync_configs" (
            "id" INTEGER PRIMARY KEY,
            "service" TEXT NOT NULL,
            "title" TEXT NOT NULL,
            "direction" INT NOT NULL DEFAULT 0,
            "mode" INT NOT NULL DEFAULT 0,
            "from" INT,
            "secrets" TEXT,
            "config" TEXT
          );
        ''');
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

  Future<int> update(Profile profile) async {
    final data = {
      'title': profile.title,
      'type': profile.type,
      'icon': profile.icon,
    };
    if (profile.id == null) {
      return openSession((t) => t.insert('"profiles"', data));
    } else {
      await openSession((t) => t.update('"profiles"', data,
          where: '"id"=?', whereArgs: [profile.id]));
      return profile.id;
    }
  }

  Future remove(Profile profile) async {
    return openSession((t) =>
        t.delete('"profiles"', where: '"id"=?', whereArgs: [profile.id]));
  }

  saveSyncConfig(SyncConfig config) async {
    print('saveSyncConfig: ${config.id}');
    return openSession((t) {
      if (config.id == null)
        return t.insert('"sync_configs"', {
          'service': config.service,
          'title': config.title,
          'direction': config.direction,
          'mode': config.mode,
          'secrets': config._secrets
        });
      else
        return t.update(
          '"sync_configs"',
          {
            'title': config.title,
            'direction': config.direction,
            'mode': config.mode,
            'secrets': config._secrets
          },
          where: '"id"=?',
          whereArgs: [config.id],
        );
    });
  }

  Future<Iterable<SyncConfig>> allSyncConfigs() async {
    return openSession((t) async {
      final list = await t.query('"sync_configs"', orderBy: '"id"');
      return list.map((e) => _toSyncConfig(e));
    });
  }

  SyncConfig _toSyncConfig(Map<String, dynamic> e) {
    final result = SyncConfig(e['id'], e['service'], e['title'], e['direction'],
        e['mode'], e['config'], e['secrets']);
    return result;
  }

  updateSyncSecrets(SyncConfig config) async {
    return openSession(
      (t) => t.update('"sync_configs"', {'secrets': config._secrets},
          where: '"id"=?', whereArgs: [config.id]),
    );
  }

  Future deleteSyncConfig(SyncConfig config) async {
    return openSession((t) => t.delete(
          '"sync_configs"',
          where: '"id"=?',
          whereArgs: [config.id],
        ));
  }
}
