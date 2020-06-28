import 'dart:collection';
import 'dart:math';

import 'package:android/data_storage.dart';
import 'package:android/ui_utils.dart';

abstract class SensorHandler {
  Map<String, double> handleData(Map<String, double> data,
      List<Trackpoint> trackpoints, Map<String, double> cache);

  void handlePause(List<Trackpoint> trackpoints, Map<String, double> cache);
  void handleLap(List<Trackpoint> trackpoints, Map<String, double> cache);

  Trackpoint _last(Iterable<Trackpoint> list) =>
      list != null && list.isNotEmpty ? list.last : null;

  double _divide(double a, b) {
    if (a == null || b == null || b == 0) return 0;
    return a / b;
  }
}

class TimeSensorHandler extends SensorHandler {
  @override
  Map<String, double> handleData(Map<String, double> data,
      Iterable<Trackpoint> trackpoints, Map<String, double> cache) {
    final result = new Map<String, double>();
    final last = _last(trackpoints);
    double delta = 0;
    if (last != null) {
      delta = data['now'] - last.data['time']['now'];
    }
    if (cache != null) {
      cache['time_total'] = (cache['time_total'] ?? 0) + delta;
      cache['time_lap'] = (cache['time_lap'] ?? 0) + delta;
      result['time_total'] = cache['time_total'];
      result['time_lap'] = cache['time_lap'];
      result['time_lap_index'] = cache['time_lap_index'];
    }
    return result;
  }

  @override
  void handleLap(List<Trackpoint> trackpoints, Map<String, double> cache) {
    cache['time_lap'] = 0;
    cache['time_lap_index'] = (cache['time_lap_index'] ?? 0) + 1;
  }

  @override
  void handlePause(List<Trackpoint> trackpoints, Map<String, double> cache) {
    // TODO: implement handlePause
  }
}

class LocationSensorHandler extends SensorHandler {
  double _distance(Map data1, Map data2) {
    if (data1.containsKey('distance') && data2.containsKey('distance')) {
      return (data2['distance'] - data1['distance']).abs();
    }
    final lat1 = data1['latitude'];
    final lat2 = data2['latitude'];
    final lon1 = data1['longitude'];
    final lon2 = data2['longitude'];
    final deg2rad = (double deg) => deg * (pi / 180);
    const R = 6371000; // Radius of the earth in m
    final dLat = deg2rad(lat2 - lat1); // deg2rad below
    final dLon = deg2rad(lon2 - lon1);
    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    var d = R * c; // Distance in m
    return d;
  }

  @override
  Map<String, double> handleData(Map<String, double> data,
      List<Trackpoint> trackpoints, Map<String, double> cache) {
    final result = new Map<String, double>();
    final _copyFromCache = (List<String> keys) =>
        keys.forEach((element) => result[element] = cache[element]);
    final _incCache =
        (String key, double value) => cache[key] = (cache[key] ?? 0) + value;
    result['loc_altitude'] = data['altitude'];
    if (cache == null) return result;
    final last = _last(trackpoints);
    double distance = 0,
        altitudeDelta = 0,
        time = 0,
        lastDistance = 0,
        lastTime = 0;
    if (last != null) {
      final lastData = last.data['location'];
      distance = _distance(data, lastData);
      altitudeDelta = (data['altitude'] ?? 0) - (lastData['altitude'] ?? 0);
      time = (data['ts'] ?? 0) - (lastData['ts'] ?? 0);
    }
    Map lastLoc = data;
    trackpoints?.reversed?.take(20)?.forEach((tp) {
      final loc = tp.data['location'];
      lastDistance += _distance(lastLoc, loc);
      lastTime += (lastLoc['ts'] - loc['ts']);
      lastLoc = loc;
    });
    result['last_distance'] = distance;
    _incCache('loc_total_time', time);
    _incCache('loc_lap_time', time);
    _incCache('loc_total_distance', distance);
    _incCache('loc_lap_distance', distance);
    _incCache('loc_total_altitude_delta', altitudeDelta);
    _incCache('loc_lap_altitude_delta', altitudeDelta);
    _incCache(
        altitudeDelta > 0 ? 'loc_total_altitude_inc' : 'loc_total_altitude_dec',
        altitudeDelta);
    _incCache(
        altitudeDelta > 0 ? 'loc_lap_altitude_inc' : 'loc_lap_altitude_dec',
        altitudeDelta);
    _copyFromCache([
      'loc_total_distance',
      'loc_lap_distance',
      'loc_total_altitude_delta',
      'loc_lap_altitude_delta',
      'loc_total_altitude_inc',
      'loc_total_altitude_dec',
      'loc_lap_altitude_inc',
      'loc_lap_altitude_dec',
    ]);
    result['loc_total_speed_ms'] =
        _divide(cache['loc_total_distance'], cache['loc_total_time'] / 1000);
    result['loc_lap_speed_ms'] =
        _divide(cache['loc_lap_distance'], cache['loc_lap_time'] / 1000);
    result['loc_total_pace_sm'] =
        _divide(cache['loc_total_time'] / 1000, cache['loc_total_distance']);
    result['loc_lap_pace_sm'] =
        _divide(cache['loc_lap_time'] / 1000, cache['loc_lap_distance']);

    result['loc_speed_ms'] = _divide(lastDistance, lastTime / 1000);
    result['loc_pace_sm'] = _divide(lastTime / 1000, lastDistance);
    result['speed_ms'] = result['loc_speed_ms'];
    result['pace_sm'] = result['loc_pace_sm'];

//    print('Location sensor: $data, $result');
    return result;
  }

  @override
  void handleLap(List<Trackpoint> trackpoints, Map<String, double> cache) {
    cache['loc_lap_time'] = 0;
    cache['loc_lap_distance'] = 0;
    cache['loc_lap_altitude_delta'] = 0;
  }

  @override
  void handlePause(List<Trackpoint> trackpoints, Map<String, double> cache) {
    // TODO: implement handlePause
  }
}

class ConnectedSensorHandler extends SensorHandler {
  @override
  Map<String, double> handleData(Map<String, double> data,
      List<Trackpoint> trackpoints, Map<String, double> cache) {
    final result = new Map<String, double>();
    final _incCache =
        (String key, double value) => cache[key] = (cache[key] ?? 0) + value;
    final _updateMinMax = (String key, double value, bool min) {
      final val = cache[key] ?? 0;
      if (val == 0 || (min ? value < val : value > val)) {
        cache[key] = value;
      }
      result['sensor_$key'] = cache[key];
    };
    final _calcStat = (String key, String scope) {
      _incCache('${key}_${scope}_times', 1);
      _incCache('${key}_${scope}_values', data[key]);
      _updateMinMax('${key}_${scope}_min', data[key], true);
      _updateMinMax('${key}_${scope}_max', data[key], false);
      result['sensor_${key}_${scope}_avg'] = _divide(
          cache['${key}_${scope}_values'], cache['${key}_${scope}_times']);
    };
    ['hrm', 'power', 'cadence', 'speed_ms', 'stride_len_m', 'distance_m']
        .forEach((element) {
      if (data.containsKey(element)) result['sensor_$element'] = data[element];
    });
    if (data.containsKey('speed_ms')) {
      result['speed_ms'] = data['speed_ms'];
      result['pace_ms'] = 1.0 / data['speed_ms'];
    }
    final last = _last(trackpoints);
    if (last == null) return result;
    if (data.containsKey('hrm')) {
      _calcStat('hrm', 'total');
      _calcStat('hrm', 'lap');
    }
    if (data.containsKey('power')) {
      _calcStat('power', 'total');
      _calcStat('power', 'lap');
    }
    if (data.containsKey('cadence')) {
      _calcStat('cadence', 'total');
      _calcStat('cadence', 'lap');
    }
    if (data.containsKey('stride_len_m')) {
      _calcStat('stride_len_m', 'total');
      _calcStat('stride_len_m', 'lap');
    }
    return result;
  }

  @override
  void handleLap(List<Trackpoint> trackpoints, Map<String, double> cache) {
    final _clearLapCache = (String key) {
      [
        '${key}_lap_times',
        '${key}_lap_values',
        '${key}_lap_min',
        '${key}_lap_max',
      ].forEach((key) {
        cache[key] = 0;
      });
    };
    _clearLapCache('hrm');
    _clearLapCache('power');
    _clearLapCache('cadence');
    _clearLapCache('stride_len_m');
  }

  @override
  void handlePause(List<Trackpoint> trackpoints, Map<String, double> cache) {
    // TODO: implement handlePause
  }
}

abstract class IndicatorValue {
  String sensor();
  String group();
  String name();
  String format(double value, Map<String, double> data);

  String _pad(int value) => value.toString().padLeft(2, '0');
  String _int(double value) => "${value != null ? value.round() : '?'}";
  String _floor(double value, int part) {
    if (value == null) return '?';
    for (int i = 0; i < part; i++) {
      value *= 10;
    }
    String result = "${value.round().abs()}".padLeft(part + 1, '0');
    return '${value < 0 ? '-' : ''}${result.substring(0, result.length - part)}.${result.substring(result.length - part)}';
  }
}

abstract class TimeIndicator extends IndicatorValue {
  @override
  String sensor() => 'time';
}

abstract class LocationIndicator extends IndicatorValue {
  @override
  String sensor() => 'location';
}

abstract class HRMIndicator extends IndicatorValue {
  @override
  String sensor() => 'hrm';
}

abstract class PowerIndicator extends IndicatorValue {
  @override
  String sensor() => 'power';
}

class DurationIndicator extends TimeIndicator {
  final String _group, _name;

  DurationIndicator(this._group, this._name);

  @override
  String group() => this._group;

  @override
  String name() => this._name;

  @override
  String format(double value, Map<String, double> data) {
    return formatDurationSeconds((value / 1000).round(), withHour: true);
  }
}

class IntIndicator extends LocationIndicator {
  IntIndicator(this._group, this._name);

  final String _group, _name;

  @override
  String group() => this._group;

  @override
  String name() => this._name;

  @override
  String format(double value, Map<String, double> data) {
    return _int(value);
  }
}

class LapIndicator extends LocationIndicator {
  @override
  String format(double value, Map<String, double> data) {
    return _int(value + 1);
  }

  @override
  String group() => 'lap';

  @override
  String name() => 'Current lap';
}

class DistanceIndicator extends LocationIndicator {
  DistanceIndicator(this._group, this._name);

  final String _group, _name;
  @override
  String group() => this._group;

  @override
  String name() => this._name;

  @override
  String format(double value, Map<String, double> data) {
    return _floor(value / 1000, 1);
  }
}

class SpeedIndicator extends LocationIndicator {
  SpeedIndicator(this._group, this._name);

  final String _group, _name;

  @override
  String group() => this._group;

  @override
  String name() => this._name;

  @override
  String format(double value, Map<String, double> data) {
    return _floor(value * 3.6, 1);
  }
}

class PaceIndicator extends LocationIndicator {
  PaceIndicator(this._group, this._name);

  final String _group, _name;

  @override
  String group() => this._group;

  @override
  String name() => this._name;

  @override
  String format(double value, Map<String, double> data) {
    final sec = (value * 1000).round();
    final min = (sec / 60).floor();
    return '$min:${_pad(sec - 60 * min)}';
  }
}

class SensorIndicatorManager {
  final Map<String, IndicatorValue> indicators =
      new LinkedHashMap.fromIterables([
    'time_total',
    'time_lap',
    'time_lap_index',
    'speed_ms',
    'pace_sm',
    'loc_altitude',
    'loc_total_distance',
    'loc_lap_distance',
    'loc_total_speed_ms',
    'loc_lap_speed_ms',
    'loc_total_pace_sm',
    'loc_lap_pace_sm',
    'sensor_hrm',
    'sensor_hrm_total_avg',
    'sensor_hrm_total_min',
    'sensor_hrm_total_max',
    'sensor_hrm_lap_avg',
    'sensor_hrm_lap_min',
    'sensor_hrm_lap_max',
    'sensor_power',
    'sensor_power_total_avg',
    'sensor_power_total_min',
    'sensor_power_total_max',
    'sensor_power_lap_avg',
    'sensor_power_lap_min',
    'sensor_power_lap_max',
    'sensor_cadence',
    'sensor_cadence_total_avg',
    'sensor_cadence_total_min',
    'sensor_cadence_total_max',
    'sensor_cadence_lap_avg',
    'sensor_cadence_lap_min',
    'sensor_cadence_lap_max',
    'sensor_speed_ms',
  ], [
    new DurationIndicator('total', 'Total time'),
    new DurationIndicator('lap', 'Lap time'),
    new LapIndicator(),
    new SpeedIndicator('current', 'Current speed'),
    new PaceIndicator('current', 'Current pace'),
    new IntIndicator('current', 'Current altitude'),
    new DistanceIndicator('total', 'Total distance'),
    new DistanceIndicator('lap', 'Lap distance'),
    new SpeedIndicator('total', 'Average speed'),
    new SpeedIndicator('lap', 'Lap speed'),
    new PaceIndicator('total', 'Average pace'),
    new PaceIndicator('lap', 'Lap pace'),
    new IntIndicator('current', 'Current hearth rate'),
    new IntIndicator('total', 'Average hearth rate'),
    new IntIndicator('total', 'Min hearth rate'),
    new IntIndicator('total', 'Max hearth rate'),
    new IntIndicator('lap', 'Lap hearth rate'),
    new IntIndicator('lap', 'Lap min hearth rate'),
    new IntIndicator('lap', 'Lap max hearth rate'),
    new IntIndicator('current', 'Current power'),
    new IntIndicator('total', 'Average power'),
    new IntIndicator('total', 'Min power'),
    new IntIndicator('total', 'Max power'),
    new IntIndicator('lap', 'Lap power'),
    new IntIndicator('lap', 'Lap min power'),
    new IntIndicator('lap', 'Lap max power'),
    new IntIndicator('current', 'Current cadence'),
    new IntIndicator('total', 'Average cadence'),
    new IntIndicator('total', 'Min cadence'),
    new IntIndicator('total', 'Max cadence'),
    new IntIndicator('lap', 'Lap cadence'),
    new IntIndicator('lap', 'Lap min cadence'),
    new IntIndicator('lap', 'Lap max cadence'),
    new SpeedIndicator('current', 'Current sensor speed'),
//        new IntIndicator('current', 'Current stride length'),
//        new IntIndicator('total', 'Average stride length'),
//        new IntIndicator('lap', 'Lap stride length'),
  ]);

  final Map<String, SensorHandler> _handlers = LinkedHashMap.fromIterables(
      ['location', 'time'], [LocationSensorHandler(), TimeSensorHandler()]);
  final _connectedHandler = ConnectedSensorHandler();

  SensorHandler handler(String id) => _handlers[id] ?? _connectedHandler;
  Iterable<SensorHandler> all() =>
      <SensorHandler>[_handlers['time'], _handlers['time'], _connectedHandler];

  List<Trackpoint> makeManualTrackpoints(
      DateTime started, int duration, double distance) {
    final startTime = started.millisecondsSinceEpoch;
    final finishTime = startTime + 1000 * duration;
    final start = Map<String, Map<String, double>>();
    final finish = Map<String, Map<String, double>>();
    start['time'] = Map.fromIterables(['now'], [startTime.toDouble()]);
    finish['time'] = Map.fromIterables(['now'], [finishTime.toDouble()]);
    if (distance > 0) {
      start['location'] =
          Map.fromIterables(['ts', 'distance'], [startTime.toDouble(), 0.0]);
      finish['location'] = Map.fromIterables(
          ['ts', 'distance'], [finishTime.toDouble(), distance]);
    }
    return [Trackpoint(startTime, 0, start), Trackpoint(finishTime, 0, finish)];
  }
}
