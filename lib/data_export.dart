import 'dart:io';

import 'package:android/data_storage.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

abstract class Exporter {
  Stream<String> export(
      Profile profile, Record record, Iterable<Trackpoint> trackpoints);

  String contentType();
}

class TCXExport extends Exporter {
  @override
  Stream<String> export(
      Profile profile, Record record, Iterable<Trackpoint> trackpoints) {
    String dt(int msec) =>
        DateTime.fromMillisecondsSinceEpoch(msec).toUtc().toIso8601String();
    streamNode(XmlNode node) => XmlNodeEncoder().convert(<XmlNode>[node]);
    xmlElement(String name, String value, [List<XmlElement> children]) =>
        XmlElement(
            XmlName.fromString(name), const [], children ?? [XmlText(value)]);
    startLap(int msec) => <XmlEvent>[
          XmlStartElementEvent(
              "Lap",
              <XmlEventAttribute>[
                XmlEventAttribute(
                    "StartTime", dt(msec), XmlAttributeType.DOUBLE_QUOTE)
              ],
              false),
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
        XmlStartElementEvent('TrainingCenterDatabase', const [], false),
        XmlStartElementEvent('Activities', const [], false),
        XmlStartElementEvent(
            'Activity',
            [
              XmlEventAttribute(
                  'Sport', profile.type, XmlAttributeType.DOUBLE_QUOTE)
            ],
            false),
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
              items.add(xmlElement("Position", "", [
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
              items.add(xmlElement(
                  'HeartRateBpm', '', [xmlElement('Value', hrm.toString())]));
            final cadence = dataValue(tp.data, null, 'cadence');
            if (cadence != null)
              items.add(xmlElement(
                  'Cadence', '', [xmlElement('Value', cadence.toString())]));
            final power = dataValue(tp.data, null, 'power');
            if (power != null) ext.add(xmlElement('Watts', power.toString()));
            if (ext.isNotEmpty)
              items.add(
                  xmlElement('Extensions', '', [xmlElement('TPX', '', ext)]));
            yield streamNode(xmlElement('Trackpoint', '', items));
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
//  String contentType() => 'text/plain';
}

class ExportManager {
  Exporter exporter(String type) {
    switch (type) {
      case 'tcx':
        return TCXExport();
    }
    return null;
  }

  Future exportToFile(Stream<String> export, String path) async {
    final str = await export.join('');
    return File(path).writeAsString(str, flush: true);
  }
}
