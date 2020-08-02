import 'dart:convert';
import 'dart:io';

import 'package:android/data_provider.dart';
import 'package:android/data_storage_profiles.dart';
import 'package:android/data_storage_records.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

abstract class Exporter {
  Stream<String> export(
      Profile profile, Record record, Iterable<Trackpoint> trackpoints);

  String contentType();

  Future import(
      Stream<String> input,
      Future Function(String, DateTime) recordHandler,
      Future Function(int, DateTime, Map<String, Map<String, double>>)
          trackpointHandler);
}

enum _TCXLocation {
  Skip,
  Activity,
  Id,
  Lap,
  Time,
  Lat,
  Lon,
  Altitude,
  Distance,
  Hrm,
  Cadence,
  Power,
}

class TCXExport extends Exporter {
  static const String TCD_NS =
      "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2";
  static const String TCX_NS =
      "http://www.garmin.com/xmlschemas/ActivityExtension/v2";

  @override
  Stream<String> export(
      Profile profile, Record record, Iterable<Trackpoint> trackpoints) {
    String dt(int msec) =>
        DateTime.fromMillisecondsSinceEpoch(msec).toUtc().toIso8601String();
    streamNode(XmlNode node) => XmlNodeEncoder().convert(<XmlNode>[node]);
    xmlElement(String name, String value,
            {List<XmlElement> children, String ns}) =>
        XmlElement(XmlName(name, ns), const [], children ?? [XmlText(value)]);
    xmlAttr(String name, String value) =>
        XmlEventAttribute(name, value, XmlAttributeType.DOUBLE_QUOTE);
    startLap(int msec) => <XmlEvent>[
          XmlStartElementEvent("Lap",
              <XmlEventAttribute>[xmlAttr("StartTime", dt(msec))], false),
        ]
            .followedBy(streamNode(xmlElement("TotalTimeSeconds", "0")))
            .followedBy(streamNode(xmlElement("DistanceMeters", "0")))
            .followedBy(streamNode(xmlElement("Calories", "0")))
            .followedBy(streamNode(xmlElement("Intensity", "Active")))
            .followedBy(streamNode(xmlElement("TriggerMethod", "Manual")))
            .followedBy(
                [XmlStartElementEvent("Track", const [], false)]).toList();
    double dataValue(Map data, String sensor, String key) {
      if (sensor == null)
        return data.values
            .map((e) => e[key])
            .firstWhere((e) => e != null, orElse: () => null);
      final Map sub = data[sensor];
      if (sub != null) return sub[key];
      return null;
    }

    Stream<List<XmlEvent>> processTrackpoints() async* {
      final start = <XmlEvent>[
        XmlProcessingEvent('xml', 'version="1.0"'),
        XmlStartElementEvent('TrainingCenterDatabase',
            [xmlAttr("xmlns", TCD_NS), xmlAttr("xmlns:tcx", TCX_NS)], false),
        XmlStartElementEvent('Activities', const [], false),
        XmlStartElementEvent(
            'Activity', [xmlAttr('Sport', profile.type.toString())], false),
      ];
      // <XML><TCD><Acts><Act>
      yield start;
      yield streamNode(xmlElement("Id", dt(record.started)));
      // <Lap><Track>
      yield startLap(record.started);
      for (var tp in trackpoints) {
        switch (tp.status) {
          case 0:
            final items = <XmlElement>[xmlElement("Time", dt(tp.timestamp))];
            final ext = <XmlElement>[];
            final lat = dataValue(tp.data, 'location', 'latitude');
            final lon = dataValue(tp.data, 'location', 'longitude');
            if (lat != null && lon != null) {
              items.add(xmlElement("Position", "", children: [
                xmlElement("LatitudeDegrees", lat.toString()),
                xmlElement("LongitudeDegrees", lon.toString()),
              ]));
            }
            final alt = dataValue(tp.data, 'location', 'altitude');
            if (alt != null)
              items.add(xmlElement("AltitudeMeters", alt.toString()));
            final distance = dataValue(tp.data, 'location', 'distance');
            if (distance != null)
              items.add(xmlElement("DistanceMeters", distance.toString()));
            final hrm = dataValue(tp.data, null, 'hrm');
            if (hrm != null)
              items.add(xmlElement('HeartRateBpm', '',
                  children: [xmlElement('Value', hrm.toString())]));
            final cadence = dataValue(tp.data, null, 'cadence');
            if (cadence != null) {
              final value = (cadence / 2).round().toString();
              items.add(xmlElement('Cadence', value));
              ext.add(xmlElement('RunCadence', value, ns: "tcx"));
            }
            final power = dataValue(tp.data, null, 'power');
            if (power != null)
              ext.add(xmlElement('Watts', power.toString(), ns: "tcx"));
            final speed = dataValue(tp.data, null, 'speed_ms');
            if (speed != null)
              ext.add(xmlElement('Speed', speed.toString(), ns: "tcx"));
            if (ext.isNotEmpty)
              items.add(xmlElement('Extensions', '',
                  children: [xmlElement('TPX', '', children: ext, ns: "tcx")]));
            yield streamNode(xmlElement('Trackpoint', '', children: items));
            break;
          case 1: // Pause
            if (tp != trackpoints.last) {
              yield <XmlEvent>[
                XmlEndElementEvent("Track"),
                XmlStartElementEvent("Track", const [], false)
              ];
            }
            break;
          case 2: // Lap
            yield <XmlEvent>[
              XmlEndElementEvent("Track"),
              XmlEndElementEvent("Lap"),
            ];
            yield startLap(tp.timestamp);
            break;
        }
      }
      yield <XmlEvent>[
        XmlEndElementEvent("Track"),
        XmlEndElementEvent("Lap"),
        XmlEndElementEvent("Activity"),
        XmlEndElementEvent("Activities"),
        XmlEndElementEvent("TrainingCenterDatabase"),
      ];
    }

    return processTrackpoints().transform(XmlEventEncoder());
  }

  @override
  String contentType() => 'application/vnd.garmin.tcx+xml';

  @override
  Future import(
      Stream<String> input,
      Function(String, DateTime) recordHandler,
      Function(int, DateTime, Map<String, Map<String, double>>)
          trackpointHandler) {
    double lat, lon, alt, hrm, power, speed, distance, cadence;
    DateTime ts;
    String id, type;
    _TCXLocation loc;
    return input
        .transform(const XmlEventDecoder())
        .transform(const XmlNormalizer())
        .expand((events) => events)
        .asyncMap<dynamic>((event) {
      switch (event.nodeType) {
        case XmlNodeType.ELEMENT:
          if (event is XmlStartElementEvent) {
            final evt = event;
            switch (evt.localName) {
              case "Activity":
                type = evt.attributes
                    .firstWhere((att) => att.localName == "Sport",
                        orElse: () => null)
                    ?.value;
                loc = _TCXLocation.Activity;
                break;
              case "Id":
                loc = _TCXLocation.Id;
                break;
              case "Lap":
                loc = _TCXLocation.Lap;
                return trackpointHandler(2, null, null);
              case "Track":
                if (loc != _TCXLocation.Lap) {
                  // Resume
                  return trackpointHandler(1, null, null);
                }
                break;
              case "Trackpoint":
                ts = null;
                lat = null;
                lon = null;
                alt = null;
                hrm = null;
                power = null;
                speed = null;
                cadence = null;
                break;
              case "Time":
                loc = _TCXLocation.Time;
                break;
              case "LatitudeDegrees":
                loc = _TCXLocation.Lat;
                break;
              case "LongitudeDegrees":
                loc = _TCXLocation.Lon;
                break;
              case "AltitudeMeters":
                loc = _TCXLocation.Altitude;
                break;
              case "DistanceMeters":
                loc = _TCXLocation.Distance;
                break;
              case "HeartRateBpm":
                loc = _TCXLocation.Hrm;
                break;
              case "Watts":
                loc = _TCXLocation.Power;
                break;
              case "RunCadence":
              case "Cadence":
                loc = _TCXLocation.Cadence;
                break;
            }
          }
          if (event is XmlEndElementEvent) {
            switch (event.localName) {
              case "Trackpoint":
                final data = {
                  'time': Map<String, double>(),
                  'location': Map<String, double>(),
                  'sensor': Map<String, double>()
                };
                data['time']['now'] = ts?.millisecondsSinceEpoch?.toDouble();
                data['location']['ts'] = ts?.millisecondsSinceEpoch?.toDouble();
                if (lat != null && lon != null) {
                  data['location']['latitude'] = lat;
                  data['location']['longitude'] = lon;
                }
                if (alt != null) data['location']['altitude'] = alt;
                if (distance != null) data['sensor']['distance_m'] = distance;
                if (hrm != null) data['sensor']['hrm'] = hrm;
                if (power != null) data['sensor']['power'] = power;
                if (cadence != null) data['sensor']['cadence'] = cadence * 2.0;
                return trackpointHandler(0, ts, data);
            }
          }
          break;
        case XmlNodeType.TEXT:
          final evt = event as XmlTextEvent;
          _parse(double value) {
            final v = double.tryParse(evt.text.trim());
            if (v == null) return value;
            return v;
          }
          switch (loc) {
            case _TCXLocation.Id:
              id = evt.text.trim();
              loc = _TCXLocation.Skip;
              return recordHandler(type, DateTime.tryParse(id));
            case _TCXLocation.Time:
              ts = DateTime.tryParse(evt.text.trim());
              loc = _TCXLocation.Skip;
              break;
            case _TCXLocation.Lat:
              lat = _parse(lat);
              break;
            case _TCXLocation.Lon:
              lon = _parse(lon);
              break;
            case _TCXLocation.Altitude:
              alt = _parse(alt);
              break;
            case _TCXLocation.Distance:
              distance = _parse(distance);
              break;
            case _TCXLocation.Hrm:
              hrm = _parse(hrm);
              break;
            case _TCXLocation.Power:
              power = _parse(power);
              break;
            case _TCXLocation.Cadence:
              cadence = _parse(cadence);
              break;
          }
          break;
      }
    }).drain();
  }
}

class ExportManager {
  Exporter exporter(String type) {
    switch (type) {
      case 'tcx':
        return TCXExport();
    }
    return null;
  }

  Future<Stream<String>> export(
      Exporter exporter, DataProvider provider, Record record) async {
    final profile = await provider.profiles.one(record.profileID);
    if (profile == null) throw ArgumentError('Invalid profile');
    final trackpoints = await provider.records.loadTrackpoints(record);
    return exporter.export(profile, record, trackpoints);
  }

  Future<int> importFile(
      Exporter exporter, DataProvider provider, String file) async {
    print('importFile: $file $exporter');
    final stream = File(file).openRead().transform(utf8.decoder);
    int id;
    await provider.records.openSession((t) async {
      DateTime last; // Last timestamp
      await exporter.import(stream, (type, created) async {
        print('recordCallback: $type, $created');
        final profile = await provider.profiles.findByType(type);
        if (profile == null) throw ArgumentError.notNull('profile');
        if (created == null) throw ArgumentError.notNull('created');
        id = await t.insert('"records"', {
          'uid': Uuid().v4(),
          'profile_id': profile.id,
          'started': created.millisecondsSinceEpoch,
          'status': 2,
        });
        return id;
      }, (type, ts, data) async {
//        print('trackpointCallback: $type, $ts, $data');
        if (id == null) throw ArgumentError.notNull('id');
        switch (type) {
          case 1:
          case 2:
            if (last != null)
              return t.insert('"trackpoints"', {
                'record_id': id,
                'added': last.millisecondsSinceEpoch,
                'status': type,
                'data': jsonEncode(Map()),
              });
            break;
          case 0:
            if (ts == null) throw ArgumentError.notNull('timestamp');
            if (data == null) throw ArgumentError.notNull('data');
            last = ts;
            return t.insert('"trackpoints"', {
              'record_id': id,
              'added': last.millisecondsSinceEpoch,
              'status': 0,
              'data': jsonEncode(data),
            });
        }
      });
    });
    await provider.records.loadOne(provider.indicators, provider.profiles, id);
    return id;
  }
}
