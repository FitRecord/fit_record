import 'dart:math';

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

Widget renderSensor(BuildContext ctx, double textSize,
    SensorIndicatorManager manager, Map<String, double> data, String id) {
  final sensor = manager.indicators[id];
  final theme = Theme.of(ctx);
  final textTheme = theme.textTheme.caption.copyWith(
      fontSize: textSize, fontFamily: 'monospace', fontWeight: FontWeight.bold);
  final rows = [
    Text(
      sensor?.format(data[id] ?? 0, data) ?? '?',
      softWrap: false,
      textAlign: TextAlign.center,
      style: textTheme,
      overflow: TextOverflow.ellipsis,
    )
  ];
  rows.insert(
      0,
      Text(
        sensor?.name() ?? 'Invalid',
        softWrap: false,
        textAlign: TextAlign.center,
      ));
  return Padding(
    padding: EdgeInsets.all(3),
    child: Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(5)),
          border: Border.all(color: theme.primaryTextTheme.caption.color)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    ),
  );
}

DateFormat dateTimeFormat() => DateFormat.yMMMd().add_jm();

class ChartSeries {
  final charts.Series<MapEntry<int, double>, int> series;
  final charts.NumericAxisSpec axisSpec;
  final List<charts.RangeAnnotation> behavior;

  ChartSeries(this.series, this.axisSpec, this.behavior);
}

ChartSeries chartsMake(BuildContext ctx, Map<int, double> data, String id,
    charts.Color color, IndicatorValue indicator,
    {String renderer,
    String axisID,
    int smoothFactor = 300,
    double average,
    bool invert = false}) {
  if (data == null || data.length < 3) return null;
  final textColor = charts.ColorUtil.fromDartColor(
      Theme.of(ctx).primaryTextTheme.bodyText1.color);

  final entries = data.entries.toList();

  final smooth = entries.length > smoothFactor
      ? (entries.length / smoothFactor).ceil()
      : 0;

  final smoothValue = (int index) {
    if (smooth == 0) return entries[index].value;

    int start = index - smooth;
    int end = index + smooth;
    if (start < 0) {
      start = 0;
      end = 2 * smooth;
    }
    if (end > entries.length) {
      end = entries.length;
      start = end - 2 * smooth;
    }
    final indexes = [for (var i = max(0, start); i < end; i++) entries[i].value]
        .where((v) => v != null);
    if (indexes.length < 2) return entries[index].value;
    final sum = indexes.reduce((value, element) => value + element);
    return sum / indexes.length;
  };

  List<double> minMaxAvg() {
    double _min, _max, _avg = 0;
    final list = List.generate(entries.length, (index) => smoothValue(index))
        .where((v) => v != null);
    list.forEach((val) {
      if (_min == null || _min > val) _min = val;
      if (_max == null || _max < val) _max = val;
      _avg += val;
    });
    if (list.isEmpty) return [0, 0, 0];
    return [_min, _max, _avg / list.length];
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
      measureFn: (entry, index) {
        final v = smoothValue(index);
        if (v == null) return null;
        final val = (v - minus) * mul;
        return invert ? 100 - val : val;
      },
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

int _secondsStep(int duration) {
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
    BuildContext ctx, List<ChartSeries> data, charts.AxisSpec primary) {
  final axis =
      data.where((element) => element != null).map((e) => e.series).toList();
  if (axis.isEmpty || axis.last == data.first?.series) {
    return null;
  }
  final annotations = data
      .where((el) => el?.behavior != null)
      .fold(<charts.RangeAnnotation>[], (prev, el) {
    prev.addAll(el.behavior.where((el) => el != null));
    return prev;
  });
  final totalTime = axis.first.data.last.key;
  final timeStep = _secondsStep(totalTime);
  final timeTicks = [
    for (var i = 0; i < totalTime - timeStep; i += timeStep)
      charts.TickSpec(i, label: formatDurationSeconds(i))
  ];
  timeTicks
      .add(charts.TickSpec(totalTime, label: formatDurationSeconds(totalTime)));
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
        tickProviderSpec: charts.StaticNumericTickProviderSpec(timeTicks)),
    customSeriesRenderers: [
      chartsAltitudeRenderer(),
    ],
    primaryMeasureAxis: primary,
    secondaryMeasureAxis: data.first?.axisSpec,
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
