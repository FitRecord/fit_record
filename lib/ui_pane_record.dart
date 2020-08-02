import 'dart:math';

import 'package:android/data_storage_profiles.dart';
import 'package:android/ui_main.dart';
import 'package:android/ui_utils.dart';
import 'package:flutter/material.dart';

enum RecordState { Idle, Ready, Recording, Paused }

class RecordPane extends MainPaneState {
  RecordState _state = RecordState.Idle;
  List<Profile> _profiles;
  Profile _profile;
  Map<String, double> sensorsData;
  List<Map<String, int>> sensorsStatus;

  _loadProfiles() async {
    try {
      final data = await widget.provider.profiles.all();
      setState(() {
        _profiles = data;
        _profile = data.first;
      });
    } catch (e) {
      print('Error _loadProfiles: $e');
    }
  }

  _statusChanged() async {
    try {
      final r = await widget.provider.records.active();
      if (r != null) {
        setState(() {
          _state = r.status == 0 ? RecordState.Recording : RecordState.Paused;
        });
      } else {
        final activated = await widget.provider.recording.activated();
        setState(() {
          _state = activated ? RecordState.Ready : RecordState.Idle;
        });
      }
    } catch (e) {
      print('Error _statusChanged: $e');
    }
  }

  _sensorStatusUpdated() {
    setState(() {
      sensorsStatus = widget.provider.recording.sensorStatusUpdated.value;
      print('Sensor status: ${sensorsStatus}');
    });
  }

  _sensorDataUpdated() {
    setState(() {
      sensorsData = widget.provider.recording.sensorDataUpdated.value
          ?.map((key, value) => MapEntry<String, double>(key, value));
    });
  }

  @override
  void dispose() {
    widget.provider.recording.statusNotifier.removeListener(_statusChanged);
    widget.provider.recording.sensorDataUpdated
        .removeListener(_sensorDataUpdated);
    widget.provider.recording.sensorStatusUpdated
        .removeListener(_sensorStatusUpdated);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.provider.recording.sensorDataUpdated.addListener(_sensorDataUpdated);
    widget.provider.recording.sensorStatusUpdated
        .addListener(_sensorStatusUpdated);

    widget.provider.recording.statusNotifier.addListener(_statusChanged);
    _loadProfiles();
    _statusChanged();
  }

  _getReady(BuildContext ctx) async {
    try {
      await widget.provider.profiles.ensure(_profile);
      await widget.provider.recording.activate(_profile);
      setState(() {
        _state = RecordState.Ready;
        sensorsData = Map<String, double>();
      });
    } catch (e) {
      print('Error _getReady: $e');
    }
  }

  _backToIdle(BuildContext ctx) async {
    try {
      await widget.provider.recording.deactivate();
      setState(() => _state = RecordState.Idle);
    } catch (e) {
      print('Error _backToReady: $e');
    }
  }

  Widget _withPadding(Widget w) => Padding(
        padding: EdgeInsets.all(8.0),
        child: w,
      );

  Widget _buildScreen(BuildContext ctx, List<List<Map<String, dynamic>>> page) {
    final column =
        renderSensors(ctx, widget.provider.indicators, sensorsData, page);
    return Center(
      child: column,
    );
  }

  Widget _bottomButton(
      IconData icon, String text, Color color, Function() handler) {
    return _withPadding(RaisedButton.icon(
        padding: EdgeInsets.all(16.0),
        onPressed: handler,
        color: color,
        icon: Icon(icon),
        label: Text(text)));
  }

  Widget _buildActive(BuildContext ctx) {
    final buttons = <Widget>[];
    switch (_state) {
      case RecordState.Ready:
        buttons.add(_bottomButton(
            Icons.cancel, 'Cancel', Colors.grey, () => _backToIdle(ctx)));
        buttons.add(Expanded(
            child: _bottomButton(
                Icons.play_arrow, 'Start', Colors.red, () => _start(ctx))));
        break;
      case RecordState.Recording:
        buttons.add(
            _bottomButton(Icons.loop, 'Lap', Colors.green, () => _lap(ctx)));
        buttons.add(Expanded(
            child: _bottomButton(
                Icons.pause, 'Pause', Colors.orange, () => _pause(ctx))));
        break;
      case RecordState.Paused:
        buttons.add(_bottomButton(
            Icons.stop, 'Finish', Colors.red, () => _finish(ctx)));
        buttons.add(Expanded(
            child: _bottomButton(
                Icons.play_arrow, 'Resume', Colors.green, () => _start(ctx))));
        break;
      case RecordState.Idle:
        break;
    }
    Widget screens = Container();
    if (sensorsData != null && _profile != null) {
      screens = PageView(
        children:
            _profile.screensJson.map((e) => _buildScreen(ctx, e)).toList(),
      );
    }
    final profileTitle =
        profileInfo(_profile, Theme.of(ctx).textTheme.headline6);
    final sensors =
        sensorsStatus != null ? _buildSensors(ctx, sensorsStatus) : Container();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.all(12.0),
              child: profileTitle,
            ),
            Spacer(),
            sensors
          ],
        ),
        Expanded(child: screens),
        Row(
          children: buttons,
        )
      ],
    );
  }

  Widget _buildIdle(BuildContext ctx) {
    if (_profiles == null) return Container();
    final dropDown = profileDropdown(
      _profiles,
      _profile,
      Theme.of(ctx).textTheme.headline6,
      (value) => setState(() => _profile = value),
    );
    final readyButton = _bottomButton(
        Icons.timer, 'Get ready', Colors.green, () => _getReady(ctx));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
            child: Center(
          child: _withPadding(dropDown),
        )),
        readyButton
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = Container();
    switch (_state) {
      case RecordState.Idle:
        body = _buildIdle(context);
        break;
      case RecordState.Ready:
      case RecordState.Recording:
      case RecordState.Paused:
        body = _buildActive(context);
        break;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Record'),
      ),
      body: body,
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }

  _start(BuildContext ctx) async {
    try {
      await widget.provider.recording.start();
    } catch (e) {
      print('Error _start: $e');
    }
  }

  _lap(BuildContext ctx) async {
    try {
      await widget.provider.recording.lap();
    } catch (e) {
      print('Error _start: $e');
    }
  }

  _pause(BuildContext ctx) async {
    try {
      await widget.provider.recording.pause();
    } catch (e) {
      print('Error _pause: $e');
    }
  }

  _finish(BuildContext ctx) async {
    final save = await yesNoDialog(ctx, 'Do you want to save?');
    try {
      print('Finish: $save');
      final id = await widget.provider.recording.finish(save);
    } catch (e) {
      print('Error _finish: $e');
    }
  }

  Widget _buildSensors(BuildContext ctx, List<Map<String, int>> sensorsStatus) {
    final drawBattery = (int level) {
      var color = Colors.grey.withOpacity(0.5);
      if (level != null) {
        if (level > 0) color = Colors.red;
        if (level > 30) color = Colors.orange;
        if (level > 60) color = Colors.green;
      }
      return CustomPaint(
        foregroundPainter: _BatteryPaint(level ?? 100, color),
        size: Size.fromRadius(16.0),
      );
    };
    final makeIcon = (int type) {
      switch (type) {
        case 1:
          return Icons.location_on;
        case 2:
          return Icons.favorite;
        case 3:
          return Icons.flash_on;
        case 4:
          return Icons.directions_run;
      }
      return Icons.bluetooth;
    };
    final makeColor = (int status) => status == 1 ? Colors.green : Colors.grey;
    final sorted = sensorsStatus;
    sorted.sort((a, b) {
      if (a['connected'] == b['connected'])
        return (b['type'] ?? 0) - (a['type'] ?? 0);
      return a['connected'] - b['connected'];
    });
    final children = sorted.map<Widget>((e) {
      final btn = IconButton(
          icon: Icon(makeIcon(e['type']), color: makeColor(e['connected'])),
          onPressed: () => null);
      final battery = e['battery'];
      return Stack(
        alignment: Alignment.center,
        children: [btn, drawBattery(battery)],
      );
    });
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: children.toList(),
    );
  }
}

class _BatteryPaint extends CustomPainter {
  final int _battery;
  final Color _color;
  Paint _paint;
  double _endRad;

  _BatteryPaint(this._battery, this._color) {
    _paint = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 4;
    _endRad = 2 * pi * _battery / 100;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(Rect.fromLTRB(0, 0, size.width, size.height), -pi / 2,
        _endRad, false, _paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true; // TODO
  }
}
