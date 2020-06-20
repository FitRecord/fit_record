import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/ui_utils.dart';
import 'package:flutter/material.dart';

Widget renderSensorTile(BuildContext ctx, Sensor sensor,
    {bool showAddress = true}) {
  final theme = Theme.of(ctx);
  final nameText = Text(
    sensor.name,
    style: theme.textTheme.headline6,
  );
  if (!showAddress) return nameText;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      nameText,
      Text(
        sensor.id,
        style: theme.textTheme.subtitle1.copyWith(fontFamily: 'monospace'),
      )
    ],
  );
}

class _Widget extends StatefulWidget {
  final RecordingController _controller;
  final Function(Sensor) _onSelected;

  const _Widget(this._controller, this._onSelected);

  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<_Widget> {
  final _list = LinkedHashMap<String, Sensor>();

  @override
  void initState() {
    super.initState();
    widget._controller.newSensorFound.addListener(_onSensor);
    _startScan();
  }

  @override
  void dispose() {
    widget._controller.newSensorFound.removeListener(_onSensor);
    _stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = _list.values.map((e) => renderSensor(context, e)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(),
        SizedBox(
          width: 0,
          height: 200,
          child: ListView(
            children: children,
          ),
        ),
//        ListView(
//          children: children,
//        ),x
      ],
    );
  }

  _onSensor() {
    final sensor = widget._controller.newSensorFound.value;
    if (mounted) setState(() => _list.putIfAbsent(sensor.id, () => sensor));
  }

  _startScan() async {
    try {
      await widget._controller.startSensorScan();
    } catch (e) {
      print('Error: $e');
      showMessage(context, 'Bluetooth is not available');
    }
  }

  _stopScan() async {
    try {
      await widget._controller.stopSensorScan();
    } catch (e) {
      print('Error: $e');
    }
  }

  Widget renderSensor(BuildContext ctx, Sensor sensor) {
    return ListTile(
      onTap: () => widget._onSelected(sensor),
      title: renderSensorTile(ctx, sensor),
    );
  }
}

Future<Sensor> addSensorDialog(
    BuildContext ctx, RecordingController controller) async {
  var result = await showDialog<Sensor>(
      context: ctx,
      builder: (ctx) => AlertDialog(
            title: Text('Add new sensor'),
            content: _Widget(controller, (sensor) {
              Navigator.of(ctx).pop(sensor);
            }),
            actions: <Widget>[
              FlatButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },
                  child: Text('Cancel'))
            ],
          ));
  return result ?? null;
}
