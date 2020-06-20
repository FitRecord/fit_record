import 'package:android/data_sensor.dart';
import 'package:android/data_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
