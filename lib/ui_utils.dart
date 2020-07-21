import 'package:android/data_sensor.dart';
import 'package:android/data_storage.dart';
import 'package:charts_flutter_cf/charts_flutter_cf.dart' as charts;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatDurationSeconds(int value, {bool withHour = false}) {
  int sec = value;
  int min = (sec / 60).floor();
  int hour = (min / 60).floor();
  final hours = hour > 0 || withHour ? '${hour.toString()}:' : '';
  return '${hours}${(min - hour * 60).toString().padLeft(2, '0')}:${(sec - min * 60).toString().padLeft(2, '0')}';
}

Widget dotsMenu(BuildContext ctx, Map<String, Function()> data) {
  return PopupMenuButton(
      icon: Icon(Icons.more_vert),
      onSelected: (key) => data[key](),
      itemBuilder: (ctx) => data.keys
          .map((e) => PopupMenuItem<String>(
                child: Text(e),
                value: e,
              ))
          .toList());
}

Icon profileIcon(Profile profile) {
  switch (profile.icon) {
    case 'run':
      return Icon(Icons.directions_run);
  }
  return Icon(Icons.warning);
}

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
            style: Theme.of(ctx).primaryTextTheme.headline5,
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
            border: Border.all(color: theme.primaryTextTheme.caption.color)),
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
    result = _simplifyRadial(result, t);
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

ChartSeries chartsMake(BuildContext ctx, Map<int, double> data, String id,
    charts.Color color, IndicatorValue indicator,
    {String renderer,
    String axisID,
    int smooth = 10,
    double average,
    bool invert = false}) {
  if (data == null || data.length < 3) return null;

  final textColor = charts.ColorUtil.fromDartColor(
      Theme.of(ctx).primaryTextTheme.bodyText1.color);

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
    if (entries.isEmpty) return [0, 0, 0];
    return [_min, _max, _avg / entries.length];
  }

  final stat = minMaxAvg();
  var minus = stat[0];
  var mul = 1.0;
  if (stat[0] == stat[1]) {
    mul = stat[0] == 0 ? 0 : 80 / stat[0];
    minus = 0;
  } else {
    mul = 100 / (stat[1] - stat[0]);
  }
  entries = entries.map((e) {
    final v = e.value;
    final val = (v - minus) * mul;
    return MapEntry(e.key, invert ? 100 - val : val);
  }).toList();
  entries = _simplify(entries, 300);

  charts.RangeAnnotation averageAnn;
  if (average != null) {
    final val = (average - minus) * mul;
    averageAnn = charts.RangeAnnotation([
      charts.LineAnnotationSegment(
          invert ? 100 - val : val, charts.RangeAnnotationAxisType.measure,
          labelStyleSpec: charts.TextStyleSpec(color: textColor),
          strokeWidthPx: 1,
          endLabel: indicator.format(average, null),
          color: color)
    ]);
  }
  final series = charts.Series<MapEntry<int, double>, int>(
      id: id,
      colorFn: (entry, index) => color,
      domainFn: (entry, index) => entry.key,
      measureFn: (entry, index) => entry.value,
      data: entries);
  if (renderer != null) series.setAttribute(charts.rendererIdKey, renderer);
  if (axisID != null) series.setAttribute(charts.measureAxisIdKey, axisID);

  List<charts.TickSpec<num>> spec;
  if (stat[0] == stat[1]) {
    spec = [charts.TickSpec<num>(80, label: indicator.format(stat[0], null))];
  } else {
    spec = [0, 25, 50, 75, 100]
        .map((e) => charts.TickSpec<num>(e,
            label: indicator.format(
                (stat[1] - stat[0]) * (invert ? 100 - e : e) / 100 + stat[0],
                null)))
        .toList();
  }
  final axisSpec = charts.NumericAxisSpec(
      showAxisLine: false,
      renderSpec: charts.SmallTickRendererSpec(
          labelStyle: charts.TextStyleSpec(color: textColor)),
      tickProviderSpec: charts.StaticNumericTickProviderSpec(spec));
  return ChartSeries(series, axisSpec, [averageAnn]);
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

Widget chartsMakeChart(BuildContext ctx, ChartSeries primary,
    ChartSeries secondary, List<charts.TickSpec> ticks) {
  if (primary == null) return null;
  final axis = [primary, secondary]
      .where((element) => element != null)
      .map((e) => e.series)
      .toList();
  final annotations = [primary, secondary]
      .where((el) => el?.behavior != null)
      .fold(<charts.RangeAnnotation>[], (prev, el) {
    prev.addAll(el.behavior.where((el) => el != null));
    return prev;
  });
  final textColor = charts.ColorUtil.fromDartColor(
      Theme.of(ctx).primaryTextTheme.bodyText1.color);
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
    primaryMeasureAxis: primary.axisSpec,
    secondaryMeasureAxis: secondary?.axisSpec,
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
