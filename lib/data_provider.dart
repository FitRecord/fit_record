import 'dart:ui';

import 'package:android/data_db.dart';
import 'package:android/data_export.dart';
import 'package:android/data_sensor.dart';
import 'package:android/data_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class Sensor {
  final String id, name;
  final bool system;

  Sensor(this.id, this.name, this.system);

  @override
  String toString() => "Sensor id=$id,name=$name";
}

class RecordingController {
  final _recordingChannel = MethodChannel('org.fitrecord/recording');
  final newSensorFound = ValueNotifier<Sensor>(null);
  final statusNotifier = ChangeNotifier();
  final historyNotifier = ChangeNotifier();
  final sensorDataUpdated = ValueNotifier<Map>(null);
  final sensorStatusUpdated = ValueNotifier<List<Map<String, int>>>(null);

  RecordingController() {
    _recordingChannel.setMethodCallHandler((call) async {
      print('org.fitrecord/recording call: ${call.method}, ${call.arguments}');
      switch (call.method) {
        case 'sensorDiscovered':
          try {
            final args = call.arguments as Map;
            final sensor =
                Sensor(args['id'], args['name'] ?? args['id'], false);
            newSensorFound.value = sensor;
          } catch (e) {
            print('Error: $e');
          }
          return;
        case 'statusChanged':
          statusNotifier.notifyListeners();
          return;
        case 'sensorDataUpdated':
          sensorDataUpdated.value = call.arguments;
          return;
        case 'sensorStatusUpdated':
          final list = (call.arguments as List)
              .cast<Map>()
              .map((e) => e.cast<String, int>())
              .toList();
          sensorStatusUpdated.value = list;
          return;
        case 'historyUpdated':
          historyNotifier.notifyListeners();
          return;
      }
    });
  }

  Future activate(Profile profile) {
    return _recordingChannel.invokeMethod('activate', {
      'profile_id': profile.id,
    });
  }

  Future deactivate() {
    return _recordingChannel.invokeMethod('deactivate');
  }

  startSensorScan() async {
    return _recordingChannel.invokeMethod('startSensorScan');
  }

  stopSensorScan() async {
    return _recordingChannel.invokeMethod('stopSensorScan');
  }

  start() async {
    return _recordingChannel.invokeMethod('start');
  }

  pause() async {
    return _recordingChannel.invokeMethod('pause');
  }

  lap() async {
    return _recordingChannel.invokeMethod('lap');
  }

  finish(bool save) async {
    return _recordingChannel.invokeMethod('finish', {'save': save});
  }

  Future<bool> activated() async {
    return _recordingChannel.invokeMethod('activated');
  }

  Future<String> export(int id, String type) async {
    return _recordingChannel.invokeMethod('export', {'id': id, 'type': type});
  }

  Future startImport() {
    return _recordingChannel.invokeMethod('import');
  }
}

class DataProvider {
  final ProfileStorage profiles;
  final RecordStorage records;
  final SensorIndicatorManager indicators;
  final RecordingController recording;
  final SharedPreferences preferences;
  final ExportManager export = ExportManager();

  final DbWrapperChannel profilesWrapper;
  final DbWrapperChannel recordsWrapper;

  DataProvider(this.profiles, this.records, this.indicators, this.recording,
      [this.profilesWrapper, this.recordsWrapper, this.preferences]);

  static backgroundCallback() async {
    WidgetsFlutterBinding.ensureInitialized();
    final provider = await _openBackgroundProvider();
    _backgroundChannel.setMethodCallHandler((call) async {
      print('Incoming background call: ${call.method}');
      switch (call.method) {
        case 'profileInfo':
          return provider.profiles.profileInfo(call.arguments as int);
        case 'start':
          final args = call.arguments as Map;
          return provider.records.start(args['profile_id']);
        case 'pause':
          return provider.records.pause(provider.indicators);
        case 'lap':
          return provider.records.lap(provider.indicators);
        case 'finish':
          final args = call.arguments as Map;
          return provider.records.finish(provider, args['save']);
        case 'sensorsData':
          final args = call.arguments as Map;
          return () async {
            final sensorsData = await provider.records
                .sensorsData(args, provider.indicators, provider.profiles);
            final sensors =
                await provider.records.sensorStatus(args, provider.indicators);
            return {
              'data': sensorsData.data,
              'status': sensors,
              'status_text': sensorsData.status
            };
          }();
        case 'export':
          final args = call.arguments as Map;
          return provider.exportOne(args['id'], args['type'], args['dir']);
        case 'import':
          final args = call.arguments as Map;
          return provider.importOne('tcx', args['file']);
      }
    });
    await _backgroundChannel.invokeMethod('initialized');
    final active = await provider.records.active();
    if (active != null) {
      await _backgroundChannel
          .invokeMethod('activate', {'profile_id': active.profileID});
    }
  }

  static final _backgroundChannel =
      OptionalMethodChannel('org.fitrecord/background');

  static Future<DataProvider> _openBackgroundProvider() async {
    final profiles = await openStorage('profiles.db', new ProfileStorage());
    final records = await openStorage('records.db', new RecordStorage());
    final profilesWrapper =
        DbWrapperChannel('org.fitrecord/proxy/profiles', profiles);
    final recordsWrapper =
        DbWrapperChannel('org.fitrecord/proxy/records', records);
    return new DataProvider(profiles, records, new SensorIndicatorManager(),
        new RecordingController(), profilesWrapper, recordsWrapper);
  }

  static Future<DataProvider> _openUiProvider() async {
    final profilesWrapper = ChannelDbDelegate('org.fitrecord/proxy/profiles');
    final recordsWrapper = ChannelDbDelegate('org.fitrecord/proxy/records');
    final profiles = new ProfileStorage(profilesWrapper);
    final records = new RecordStorage(recordsWrapper);
    final preferences = await SharedPreferences.getInstance();
    return new DataProvider(profiles, records, new SensorIndicatorManager(),
        new RecordingController(), null, null, preferences);
  }

  static Future<DataProvider> openProvider(Function() callback) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _backgroundChannel.invokeMethod('initialize',
        PluginUtilities.getCallbackHandle(callback).toRawHandle());
    final provider = await _openUiProvider();
    return provider;
  }

  Future<Map<String, String>> exportOne(int id, String type, String dir) async {
    final record = await records.one(id);
    if (record == null) throw ArgumentError('Invalid record');
    final profile = await profiles.one(record.profileID);
    if (profile == null) throw ArgumentError('Invalid profile');
    final trackpoints = await records.loadTrackpoints(record);
    final exporter = export.exporter(type);
    if (exporter == null) throw ArgumentError('Invalid export type');
    final path = p.join(
        dir, '${record.uid}-${DateTime.now().millisecondsSinceEpoch}.$type');
    await export.exportToFile(
        exporter.export(profile, record, trackpoints), path);
    return {'file': path, 'content_type': exporter.contentType()};
  }

  Future<int> importOne(String type, String file) async {
    final exporter = export.exporter(type);
    if (exporter == null) throw ArgumentError('Invalid import type');
    return export.importFile(exporter, this, file);
  }
}
