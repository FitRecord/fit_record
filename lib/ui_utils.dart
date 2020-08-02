import 'dart:collection';

import 'package:android/data_sensor.dart';
import 'package:android/data_storage_profiles.dart';
import 'package:android/icons_sport.dart';
import 'package:charts_flutter_cf/charts_flutter_cf.dart' as charts;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';

String formatDurationSeconds(int value, {bool withHour = false}) {
  int sec = value;
  int min = (sec / 60).floor();
  int hour = (min / 60).floor();
  final hours = hour > 0 || withHour ? '${hour.toString()}:' : '';
  return '${hours}${(min - hour * 60).toString().padLeft(2, '0')}:${(sec - min * 60).toString().padLeft(2, '0')}';
}

Widget dotsMenu(BuildContext ctx, Map<String, Function()> data,
    {IconData icon = Icons.more_vert}) {
  return PopupMenuButton(
      icon: Icon(icon),
      onSelected: (key) => data[key](),
      itemBuilder: (ctx) => data.keys
          .map((e) => PopupMenuItem<String>(
                child: Text(e),
                value: e,
              ))
          .toList());
}

IconData profileTypeIcon(String icon) {
  switch (icon) {
    case 'run':
      return SportIcons.run;
    case 'bike':
      return SportIcons.bicycle;
    case 'row':
      return SportIcons.row;
    case 'swim':
      return SportIcons.swim;
    case 'ski':
      return SportIcons.ski;
    case 'dumbbell':
      return SportIcons.dumbbell;
    case 'walk':
      return SportIcons.walk;
    case 'hike':
      return SportIcons.hike;
    case 'skate':
      return SportIcons.skate;
    case 'ski_nordic':
      return SportIcons.ski_nordic;
    case 'snowboard':
      return SportIcons.snowboard;
  }
  return Icons.warning;
}

Widget iconWithText(Icon icon, String text, [TextStyle style]) => Row(
      children: [
        Padding(
          padding: EdgeInsets.only(right: 12.0),
          child: icon,
        ),
        Text(
          text,
          style: style,
        )
      ],
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
    );

Widget profileInfo(Profile profile, TextStyle style) =>
    iconWithText(profileIcon(profile), profile.title, style);

Widget profileDropdown(List<Profile> profiles, Profile selected,
    TextStyle style, Function(Profile) onChanged) {
  return DropdownButton<Profile>(
      value: selected,
      items: profiles.map((profile) {
        return DropdownMenuItem<Profile>(
          value: profile,
          child: profileInfo(profile, style),
        );
      }).toList(),
      onChanged: (value) => onChanged(value));
}

Icon profileIcon(Profile profile) => Icon(
      profileTypeIcon(profile.icon),
      size: 24.0,
    );

Future<bool> yesNoDialog(BuildContext ctx, String title) async {
  var result = await showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
            title: Text(title),
            actions: <Widget>[
              FlatButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text('Yes')),
              FlatButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },
                  child: Text('No'))
            ],
          ));
  return result ?? false;
}

showMessage(BuildContext ctx, String message) {
  final ScaffoldState ss = ctx.findAncestorStateOfType();
  if (ss == null) {
    return showDialog(
        context: ctx,
        builder: (ctx) => AlertDialog(
              title: Text(message),
              actions: <Widget>[
                FlatButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: Text('OK'))
              ],
            ));
  }
  ss.showSnackBar(new SnackBar(
    content: new Text(message),
  ));
}

Widget renderSensors(BuildContext ctx, SensorIndicatorManager sensors,
    Map<String, double> data, List<List<Map<String, dynamic>>> page,
    [String title]) {
  final rows = <Widget>[];
  rows.addAll(page.map((row) {
    final children = row.map((e) {
      return Expanded(child: renderSensor(ctx, 30, sensors, data, e['id']));
    }).toList();
    return Row(
//        crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: children,
    );
  }));
  if (title != null) {
    rows.insert(
        0,
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            title,
            style: Theme.of(ctx).textTheme.headline5,
          ),
        ));
  }
  final column = Column(
    children: rows,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
  );
  return column;
}

TextStyle sensorTextStyle(BuildContext ctx, double textSize) =>
    Theme.of(ctx).textTheme.bodyText2.copyWith(
        fontSize: textSize,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold);

Widget renderSensor(BuildContext ctx, double textSize,
    SensorIndicatorManager manager, Map<String, dynamic> data, String id,
    {bool expand = true,
    bool caption = true,
    bool border = true,
    bool withType = false}) {
  final sensor = manager.indicators[id];
  final theme = Theme.of(ctx);
  final textTheme = sensorTextStyle(ctx, textSize);
  final mainText = Text(
    sensor?.format(data[id] ?? 0, data) ?? '?',
    softWrap: false,
    textAlign: TextAlign.center,
    style: textTheme,
    overflow: TextOverflow.ellipsis,
  );
  final rows = <Widget>[];
  final valueType = sensor?.valueType(data[id], data);
  if (withType && valueType != null) {
    rows.add(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mainText,
        Padding(
          padding: EdgeInsets.all(2.0),
          child: Text(
            valueType,
            softWrap: false,
            maxLines: 1,
            style: theme.textTheme.bodyText2,
          ),
        ),
      ],
      crossAxisAlignment: CrossAxisAlignment.end,
    ));
  } else
    rows.add(mainText);
  if (caption) {
    rows.insert(
        0,
        Text(
          sensor?.name() ?? 'Invalid',
          softWrap: false,
          maxLines: 1,
          style: theme.textTheme.bodyText2,
          textAlign: TextAlign.center,
        ));
  }
  final content = Padding(
    padding: EdgeInsets.symmetric(horizontal: 4.0),
    child: Column(
      crossAxisAlignment:
          expand ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    ),
  );
  if (border)
    return Padding(
      padding: EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(3)),
            border: Border.all(color: theme.textTheme.caption.color)),
        child: content,
      ),
    );
  return content;
}

DateFormat dateTimeFormat() => DateFormat.yMMMd().add_jm();

class ChartSeries {
  final charts.Series<MapEntry<int, double>, int> series;
  final charts.NumericAxisSpec axisSpec;
  final List<charts.RangeAnnotation> behavior;

  ChartSeries(this.series, this.axisSpec, this.behavior);
}

List<MapEntry<int, double>> _simplifyDouglasPeucker(
    List<MapEntry<int, double>> points, double t) {
  if (points.length <= 1) return points;
  final sqt = t * t;
  final result = [points.first];
  double _sqDist(MapEntry<int, double> p, MapEntry<int, double> p1,
      MapEntry<int, double> p2) {
    var x = p1.key.toDouble(),
        y = p1.value,
        dx = p2.key.toDouble() - x,
        dy = p2.value - y;
    if (dx != 0 || dy != 0) {
      final t = ((p.key.toDouble() - x) * dx + (p.value - y) * dy) /
          (dx * dx + dy * dy);
      if (t > 1) {
        x = p2.key.toDouble();
        y = p2.value;
      } else if (t > 0) {
        x += dx * t;
        y += dy * t;
      }
    }
    dx = p.key.toDouble() - x;
    dy = p.value - y;
    return dx * dx + dy * dy;
  }

  _step(int first, int last) {
    var max = sqt;
    int index;
    for (var i = first + 1; i < last; i++) {
      final sqd = _sqDist(points[i], points[first], points[last]);
      if (sqd > max) {
        index = i;
        max = sqd;
      }
    }
    if (max > sqt) {
      if (index - first > 1) _step(first, index);
      result.add(points[index]);
      if (last - index > 1) _step(index, last);
    }
  }

  _step(0, points.length - 1);

  result.add(points.last);
  return result;
}

List<MapEntry<int, double>> _simplifyRadial(
    List<MapEntry<int, double>> points, double t) {
  double _sqDist(MapEntry<int, double> p1, MapEntry<int, double> p2) {
    final dx = (p1.key - p2.key).toDouble();
    final dy = p1.value - p2.value;
    return dx * dx + dy * dy;
  }

  if (points.length <= 1) return points;
  final sqt = t * t;
  var prev = points.first;
  final result = [prev];
  MapEntry<int, double> point;
  for (var i = 1; i < points.length; i++) {
    point = points[i];
    if (_sqDist(point, prev) > sqt) {
      result.add(point);
      prev = point;
    }
  }
  if (prev != point) result.add(point);
  return result;
}

List<MapEntry<int, double>> _simplify(
    List<MapEntry<int, double>> points, maxPoints) {
  var result = points;
  double t = 1;
  while (result.length > maxPoints) {
    result = _simplifyDouglasPeucker(result, t);
    t += 2;
  }
  return result;
}

List<MapEntry<int, double>> _smooth(
    List<MapEntry<int, double>> points, int items) {
  return List.generate(points.length, (index) {
    if (items == 0) return points[index];
    final indexes = [
      for (var i = index - items; i <= index + items; i++)
        i >= 0 && i < points.length ? points[i].value : null
    ].where((v) => v != null);
    if (indexes.length < 2) return points[index];
    final sum = indexes.reduce((value, element) => value + element);
    return MapEntry(points[index].key, sum / indexes.length.toDouble());
  });
}

ChartSeries chartsMake(
  BuildContext ctx,
  Map<int, double> data,
  String id,
  MaterialColor color,
  IndicatorValue indicator, {
  String renderer,
  String axisID,
  int smooth = 5,
  double zoom,
  double average,
  List<Map<String, double>> zones,
}) {
  if (data == null || data.length < 3) return null;

  final textColor =
      charts.ColorUtil.fromDartColor(Theme.of(ctx).textTheme.bodyText1.color);

  var entries = _smooth(data.entries.toList(), smooth)
      .where((el) => el.value != null)
      .toList();

  List<double> minMaxAvg() {
    double _min, _max, _avg = 0;
    entries.forEach((val) {
      if (_min == null || _min > val.value) _min = val.value;
      if (_max == null || _max < val.value) _max = val.value;
      _avg += val.value;
    });
    if (zoom != null && _max - _min < zoom) _max = _min + zoom;
    if (_min == _max) return [_min - 50, _min + 50, _min, 0];
    if (zones != null && zones[0]['from'] != null && zones[4]['to'] != null) {
      return [zones[0]['from'], zones[4]['to'], _avg / entries.length, 1];
    }
    return [_min, _max, _avg / entries.length, 1];
  }

  final stat = minMaxAvg();
  var minus = stat[0];
  var mul = 100 / (stat[1] - stat[0]);
  double _valueNormalized(double v) {
    return (v - minus) * mul;
  }

  entries = entries.map((e) {
    return MapEntry(e.key, _valueNormalized(e.value));
  }).toList();
  entries = _simplify(entries, 300);

  charts.RangeAnnotation averageAnn;
  charts.RangeAnnotation zonesAnn;
  if (zones != null) {
    final list = <charts.RangeAnnotationSegment>[];
    for (var i = 0; i < zones.length; i++) {
      final z = zones[i];
      if (z['from'] != null && z['to'] != null)
        list.add(charts.RangeAnnotationSegment(_valueNormalized(z['from']),
            _valueNormalized(z['to']), charts.RangeAnnotationAxisType.measure,
            color: charts.ColorUtil.fromDartColor(
                zoneColor(i).shade900.withOpacity(0.4))));
    }
    zonesAnn = charts.RangeAnnotation(list);
  }
  if (average != null) {
    final val = (average - minus) * mul;
    averageAnn = charts.RangeAnnotation([
      charts.LineAnnotationSegment(val, charts.RangeAnnotationAxisType.measure,
          strokeWidthPx: 1,
          color: charts.ColorUtil.fromDartColor(color.shade300))
    ]);
  }
  double _entryValue(double value) {
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
  }

  final series = charts.Series<MapEntry<int, double>, int>(
      id: id,
      colorFn: (entry, index) => charts.ColorUtil.fromDartColor(color.shade400),
      strokeWidthPxFn: (entry, index) =>
          entry.value < 0 || entry.value > 100 ? 1 : 2,
      domainFn: (entry, index) => entry.key,
      measureFn: (entry, index) => _entryValue(entry.value),
      data: entries);
  if (renderer != null) series.setAttribute(charts.rendererIdKey, renderer);
  if (axisID != null) series.setAttribute(charts.measureAxisIdKey, axisID);

  List<charts.TickSpec<num>> spec;
  if (stat[3] == 0) {
    spec = [charts.TickSpec<num>(50, label: indicator.format(stat[2], null))];
  } else {
    spec = [0, 25, 50, 75, 100]
        .map((e) => charts.TickSpec<num>(e,
            label: indicator.format(
                (stat[1] - stat[0]) * e / 100 + stat[0], null)))
        .toList();
  }
  final axisSpec = charts.NumericAxisSpec(
      showAxisLine: false,
      renderSpec: charts.SmallTickRendererSpec(
          labelStyle: charts.TextStyleSpec(color: textColor)),
      tickProviderSpec: charts.StaticNumericTickProviderSpec(spec));
  return ChartSeries(series, axisSpec, [averageAnn, zonesAnn]);
}

charts.SeriesRendererConfig<num> chartsAltitudeRenderer() =>
    charts.LineRendererConfig(
      customRendererId: 'altitude',
      includeArea: true,
      stacked: false,
    );

chartsNoTicksAxis() => charts.NumericAxisSpec(
    tickProviderSpec: charts.StaticNumericTickProviderSpec([]));

chartsTimeAxis() => charts.NumericAxisSpec(
    showAxisLine: true,
    tickFormatterSpec: charts.BasicNumericTickFormatterSpec((val) {
      print('Format: $val');
      return val.toString();
    }),
    tickProviderSpec: charts.NumericEndPointsTickProviderSpec());

int secondsStep(int duration) {
  if (duration < 60) return 20;
  if (duration < 120) return 30;
  if (duration < 60 * 5) return 60;
  if (duration < 60 * 10) return 120;
  if (duration < 60 * 15) return 60 * 4;
  if (duration < 60 * 20) return 60 * 5;
  if (duration < 60 * 30) return 60 * 7;
  if (duration < 60 * 45) return 60 * 10;
  if (duration < 60 * 60) return 60 * 15;
  if (duration < 60 * 90) return 60 * 20;
  if (duration < 60 * 120) return 60 * 30;
  if (duration < 60 * 180) return 60 * 45;
  if (duration < 60 * 240) return 60 * 60;
  return (duration / 3).floor();
}

Widget chartsMakeChart(
    BuildContext ctx, List<ChartSeries> series, List<charts.TickSpec> ticks) {
  final axis =
      series.where((element) => element != null).map((e) => e.series).toList();
  if (axis.isEmpty || series.first == null) return null;
  final annotations = <charts.RangeAnnotation>[];
  series.forEach((element) {
    if (element?.behavior != null)
      annotations.addAll(element.behavior.where((element) => element != null));
  });
  final textColor =
      charts.ColorUtil.fromDartColor(Theme.of(ctx).textTheme.bodyText1.color);
  final chart = charts.LineChart(
    axis,
    animate: false,
    defaultInteractions: false,
    behaviors: annotations,
    domainAxis: charts.NumericAxisSpec(
        showAxisLine: false,
        renderSpec: charts.SmallTickRendererSpec(
            labelOffsetFromAxisPx: 10,
            labelStyle: charts.TextStyleSpec(color: textColor)),
        tickProviderSpec: charts.StaticNumericTickProviderSpec(ticks)),
    customSeriesRenderers: [
      chartsAltitudeRenderer(),
    ],
    primaryMeasureAxis: series.first.axisSpec,
    secondaryMeasureAxis: series.last?.axisSpec,
  );
  return SizedBox(
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(4.0),
        child: chart,
      ),
    ),
    height: 200,
  );
}

Column columnMaybe(List<Widget> children) => Column(
      children: children.where((el) => el != null).toList(),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
    );

String textFromCtrl(TextEditingController ctrl) {
  final result = ctrl.text?.trim();
  if (result.isEmpty) return null;
  return result;
}

int parseDuration(String value) {
  final parts = value.split(':').map((s) => int.tryParse(s, radix: 10));
  if (parts.contains(null)) {
    return null;
  }
  return parts.reduce((value, element) => value * 60 + element);
}

MaterialColor zoneColor(int zone) {
  switch (zone) {
    case 0:
      return Colors.grey;
    case 1:
      return Colors.blue;
    case 2:
      return Colors.green;
    case 3:
      return Colors.yellow;
    case 4:
      return Colors.red;
  }
}

TileLayerOptions _osmTiles() => TileLayerOptions(
    urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    subdomains: ['a', 'b', 'c']);

Widget mapRenderInteractive(BuildContext ctx, MapController mapCtrl,
    List<Polyline> polylines, LatLngBounds bounds,
    {bool zoom = true,
    bool fit = true,
    bool fullscreen = true,
    bool square = true}) {
  final boundOpts = FitBoundsOptions(padding: EdgeInsets.all(16.0));
  final map = FlutterMap(
    mapController: mapCtrl,
    options: MapOptions(
      bounds: bounds,
      boundsOptions: boundOpts,
    ),
    layers: [
      _osmTiles(),
      PolylineLayerOptions(
          polylines: polylines.where((element) => element != null).toList(),
          polylineCulling: true),
    ],
  );
  final zoomLayer = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      fullscreen
          ? IconButton(
              onPressed: () => _FullscreenMap.open(ctx, polylines, bounds),
              icon: Icon(Icons.fullscreen),
            )
          : null,
      fit
          ? IconButton(
              onPressed: () => mapCtrl.fitBounds(bounds, options: boundOpts),
              icon: Icon(Icons.location_searching),
            )
          : null,
      zoom
          ? IconButton(
              onPressed: () => mapCtrl.move(mapCtrl.center, mapCtrl.zoom + 1),
              icon: Icon(Icons.zoom_in),
            )
          : null,
      zoom
          ? IconButton(
              onPressed: () => mapCtrl.move(mapCtrl.center, mapCtrl.zoom - 1),
              icon: Icon(Icons.zoom_out),
            )
          : null,
    ]
        .where((e) => e != null)
        .map((e) => Container(
              color: Colors.grey.withOpacity(0.5),
              child: e,
            ))
        .toList(),
  );
  final stack = Stack(
    children: [
      map,
      Padding(
        padding: EdgeInsets.all(8.0),
        child: zoomLayer,
      ),
    ],
    alignment: AlignmentDirectional.bottomEnd,
  );
  if (square)
    return AspectRatio(
      aspectRatio: 1.0,
      child: Padding(
        padding: EdgeInsets.all(4.0),
        child: stack,
      ),
    );
  return stack;
}

class _FullscreenMap extends StatelessWidget {
  final List<Polyline> _polylines;
  final LatLngBounds _bounds;
  final _mapCtrl = MapController();

  _FullscreenMap(this._polylines, this._bounds);

  static Future open(
      BuildContext ctx, List<Polyline> _polylines, LatLngBounds _bounds) async {
    return Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (ctx) => _FullscreenMap(_polylines, _bounds),
          fullscreenDialog: true,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: mapRenderInteractive(context, _mapCtrl, _polylines, _bounds,
          fullscreen: false, square: false),
    );
  }
}

Widget formWithItems(BuildContext ctx, List<Widget> items) {
  return Form(
    child: LayoutBuilder(
      builder: (ctx, box) => ListView(
        padding: EdgeInsets.only(bottom: 80.0),
        children: items
            .map((e) => Padding(
                  padding: EdgeInsets.all(8.0),
                  child: e,
                ))
            .toList(),
      ),
    ),
  );
}

Widget dropdownFormItem<T>(String title, List<T> keys, List<String> values,
        T value, Function(T) onChanged) =>
    DropdownButtonFormField<T>(
        decoration: InputDecoration(labelText: title),
        value: value,
        items: LinkedHashMap.fromIterables(keys, values)
            .entries
            .map((e) => DropdownMenuItem<T>(
                  child: Text(e.value),
                  value: e.key,
                ))
            .toList(),
        onChanged: onChanged);

bool textIsNotEmpty(String s) => s?.trim()?.isNotEmpty == true;
