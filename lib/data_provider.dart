import 'dart:ui';

import 'package:android/data_db.dart';
import 'package:android/data_sensor.dart';
import 'package:android/data_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
}

class DataProvider {
  final ProfileStorage profiles;
  final RecordStorage records;
  final SensorIndicatorManager indicators;
  final RecordingController recording;

  DataProvider(this.profiles, this.records, this.indicators, this.recording);

  static backgroundCallback() async {
    WidgetsFlutterBinding.ensureInitialized();
    final provider = await _openProvider();
    _backgroundChannel.setMethodCallHandler((call) async {
      print('Incoming background call: ${call.method}');
      switch (call.method) {
        case 'profileInfo':
          return provider.profiles.profileInfo(call.arguments as int);
        case 'start':
          final args = call.arguments as Map;
          return provider.records.start(args['profile_id']);
        case 'pause':
          return provider.records.pause();
        case 'lap':
          return provider.records.lap();
        case 'finish':
          final args = call.arguments as Map;
          return provider.records.finish(args['save']);
        case 'sensorsData':
          final args = call.arguments as Map;
          return () async {
            final data =
                await provider.records.sensorsData(args, provider.indicators);
            final sensors =
                await provider.records.sensorStatus(args, provider.indicators);
            return {'data': data, 'status': sensors};
          }();
      }
    });
    final active = await provider.records.active();
    if (active != null) {
      await _backgroundChannel.invokeMethod(
          'activate', <String, dynamic>{'profile_id': active.profileID});
    }
  }

  static final _backgroundChannel =
      OptionalMethodChannel('org.fitrecord/background');

  static Future<DataProvider> _openProvider() async {
    final profiles = await openStorage('profiles.db', new ProfileStorage());
    final records = await openStorage('records.db', new RecordStorage());
    return new DataProvider(profiles, records, new SensorIndicatorManager(),
        new RecordingController());
  }

  static Future<DataProvider> openProvider(Function() callback) async {
    WidgetsFlutterBinding.ensureInitialized();
    final provider = await _openProvider();
    _backgroundChannel.invokeMethod('initialize',
        PluginUtilities.getCallbackHandle(callback).toRawHandle());
    return provider;
  }
}
