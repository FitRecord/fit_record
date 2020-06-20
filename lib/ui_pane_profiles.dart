import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/data_sensor.dart';
import 'package:android/data_storage.dart';
import 'package:android/ui_dialog_sensors.dart';
import 'package:android/ui_main.dart';
import 'package:android/ui_utils.dart';
import 'package:flutter/material.dart';

class _ConfigEditor extends StatefulWidget {
  final Function(Map<String, dynamic> data) _onChanged;
  final DataProvider _provider;

  const _ConfigEditor(this._onChanged, this._provider);

  @override
  State<StatefulWidget> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<_ConfigEditor> {
  final _sensors = <Sensor>[];

  @override
  void initState() {
    super.initState();
    _load(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    items.add(ListTile(
      title: Text(
        'Sensors:',
        style: Theme.of(context).textTheme.headline5,
      ),
      trailing: IconButton(
          icon: Icon(Icons.add), onPressed: () => _addSensor(context)),
    ));
    items.addAll(_sensors.map((item) {
      return ListTile(
        leading: Checkbox(value: true, onChanged: null),
        title: renderSensorTile(context, item, showAddress: !item.system),
        trailing: !item.system
            ? dotsMenu(
                context,
                LinkedHashMap.fromIterables(
                    ['Remove'], [() => _deleteSensor(context, item)]))
            : null,
      );
    }));
    return ListView(
      children: items,
    );
  }

  _load(BuildContext ctx) async {
    try {
      final data = await widget._provider.profiles.allSensors();
      setState(() {
        _sensors.clear();
        _sensors.addAll(data);
      });
    } catch (e) {
      showMessage(ctx, 'Something is not right');
      print('Error: $e');
    }
  }

  _deleteSensor(BuildContext ctx, Sensor sensor) async {
    final q = await yesNoDialog(ctx, 'Remove the sensor?');
    if (!q) return;
    try {
      await widget._provider.profiles.removeSensor(sensor);
      _load(ctx);
    } catch (e) {
      showMessage(ctx, 'Something is not right');
      print('Error: $e');
    }
  }

  _addSensor(BuildContext ctx) async {
    final sensor = await addSensorDialog(ctx, widget._provider.recording);
//    print('New sensor: $sensor');
    if (sensor == null) return;
    try {
      final result = await widget._provider.profiles.addSensor(sensor);
      if (result) return _load(ctx);
    } catch (e) {
      showMessage(ctx, 'Something is not right');
      print('Error: $e');
    }
  }
}

class _ScreenEditor extends StatefulWidget {
  final List<List<List<Map<String, dynamic>>>> json;
  final Function(List<List<List<Map<String, dynamic>>>> data) onChanged;
  final SensorIndicatorManager _indicators;

  _ScreenEditor(this.json, this.onChanged, this._indicators);

  @override
  State<StatefulWidget> createState() => _ScreenEditorState();
}

class _ScreenEditorState extends State<_ScreenEditor> {
  int _page = 0;

  List<PopupMenuEntry<String>> _buildSensorsList(bool withRemove) {
    final list = widget._indicators.indicators.entries.map((e) {
      return PopupMenuItem<String>(
        child: Text(e.value.name()),
        value: e.key,
      ) as PopupMenuEntry<String>;
    }).toList();
    if (withRemove) {
      list.insertAll(0, [
        PopupMenuItem<String>(
          child: Text('Remove'),
          value: '',
        ),
        PopupMenuDivider()
      ]);
    }
    return list;
  }

  Widget _buildSensor(BuildContext ctx, String id, double textSize) {
    return renderSensor(ctx, 30, widget._indicators, Map(), id);
  }

  _addRow(BuildContext ctx, String id) {
    setState(() {
      widget.json[_page].add(<Map<String, dynamic>>[
        {'id': id}
      ]);
      widget.onChanged(widget.json);
    });
  }

  _addItem(BuildContext ctx, List<Map<String, dynamic>> row, String id) {
    setState(() {
      row.add({'id': id} as Map<String, dynamic>);
      widget.onChanged(widget.json);
    });
  }

  _removeItem(BuildContext ctx, List<Map<String, dynamic>> row,
      Map<String, dynamic> item) {
    if (row.length == 1) {
      if (widget.json[_page].length == 1) {
        return showMessage(ctx, "Last row couldn't be removed");
      }
      setState(() {
        widget.json[_page].remove(row);
        widget.onChanged(widget.json);
      });
    } else {
      setState(() {
        row.remove(item);
        widget.onChanged(widget.json);
      });
    }
  }

  _goLeft() {
    setState(() {
      if (_page > 0) _page--;
    });
  }

  _goRight() {
    setState(() {
      if (_page < widget.json.length - 1) _page++;
    });
  }

  _deletePage() async {
    final yes = await yesNoDialog(context, "Delete the page?");
    setState(() {
      if (yes && widget.json.length > 1) {
        widget.json.removeAt(_page);
        if (_page > 0) _page--;
        widget.onChanged(widget.json);
      }
    });
  }

  _addPage(String id) {
    setState(() {
      widget.json.add([
        [
          {'id': id} as Map<String, dynamic>
        ]
      ]);
      _page = widget.json.length - 1;
      widget.onChanged(widget.json);
    });
  }

  @override
  void didUpdateWidget(_ScreenEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _page = 0;
  }

  Widget _buildButtonBar(BuildContext ctx) {
    final onLeft = _page == 0 ? null : _goLeft;
    final onRight = _page >= widget.json.length - 1 ? null : _goRight;
    final onDelete = widget.json.length <= 1 ? null : _deletePage;
    return BottomAppBar(
      child: Row(children: [
        IconButton(icon: Icon(Icons.chevron_left), onPressed: onLeft),
        Expanded(child: Text('Page ${_page}')),
        PopupMenuButton<String>(
            itemBuilder: (ctx) => _buildSensorsList(false),
            onSelected: (id) {
              _addPage(id);
            },
            icon: Icon(Icons.add)),
        IconButton(icon: Icon(Icons.delete_outline), onPressed: onDelete),
        IconButton(icon: Icon(Icons.chevron_right), onPressed: onRight),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.json[_page].map((row) {
      final items = row.map((item) {
        return Expanded(
            child: PopupMenuButton<String>(
                child: _buildSensor(context, item['id'], 30),
                initialValue: item['id'],
                onSelected: (id) {
                  if (id == '') return _removeItem(context, row, item);
                  setState(() {
                    item['id'] = id;
                    widget.onChanged(widget.json);
                  });
                },
                itemBuilder: (ctx) => _buildSensorsList(true))) as Widget;
      }).toList();
      items.add(PopupMenuButton<String>(
          itemBuilder: (ctx) => _buildSensorsList(false),
          onSelected: (id) {
            _addItem(context, row, id);
          },
          icon: Icon(Icons.add)));
      return Row(
        children: items,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
      ) as Widget;
    }).toList();
    rows.add(PopupMenuButton<String>(
        itemBuilder: (ctx) => _buildSensorsList(false),
        onSelected: (id) {
          _addRow(context, id);
        },
        icon: Icon(Icons.add)));
    final bottom = _buildButtonBar(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
            child: Center(
          child: Column(
            children: rows,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        )),
        bottom
      ],
    );
  }
}

class ProfilesPane extends MainPaneState {
  List<Profile> profiles;
  Profile profile;

  _init() async {
    try {
      final list = await widget.provider.profiles.all();
      setState(() {
        profiles = list;
        profile = list.first;
      });
    } catch (e) {
      print('Failed to get profiles $e');
      showMessage(context, "Something is not good");
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Iterable<Map<String, String>> _activeTabs() {
    return [
      {'id': 'screens', 'title': 'Screen (App)'},
      {'id': 'screens_ext', 'title': 'Screen (Watch)'},
      {'id': 'config', 'title': 'Configuration'},
    ].where((element) => element['id'] != 'screens_ext');
  }

  Widget _appBar(BuildContext ctx, List<Tab> tabs) {
    final selector = DropdownButton<Profile>(
        value: profile,
        items: profiles.map((profile) {
          return DropdownMenuItem<Profile>(
              value: profile,
              child: Row(
                children: [
                  profileIcon(profile),
                  Text(
                    profile.title,
                    style: Theme.of(ctx).primaryTextTheme.headline6,
                  )
                ],
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
              ));
        }).toList(),
        onChanged: (value) => null);
    return AppBar(
      title: selector,
      bottom: TabBar(tabs: tabs),
      actions: [
        IconButton(
          icon: Icon(Icons.edit),
//          onPressed: () => null,
        ),
        IconButton(
          icon: Icon(Icons.add),
//          onPressed: () => null,
        ),
      ],
    );
  }

  _updateJsonField(BuildContext ctx, String field, dynamic json) async {
    try {
      widget.provider.profiles.updateJsonField(profile, field, json);
    } catch (e) {
      print('Failed to update: $e');
      showMessage(ctx, "Something is not good");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (profile == null)
      return Scaffold(
        appBar: AppBar(),
        bottomNavigationBar: widget.bottomNavigationBar,
      );
    final tabs = _activeTabs();
    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: _appBar(
              context,
              tabs
                  .map((e) => Tab(
                        text: e['title'],
                      ))
                  .toList()),
          bottomNavigationBar: widget.bottomNavigationBar,
          body: TabBarView(
              children: tabs.map((e) => _buildTab(e['id'])).toList()),
        ));
  }

  Widget _buildTab(String id) {
    switch (id) {
      case 'screens':
        return _ScreenEditor(
            profile.screensJson,
            (json) => _updateJsonField(context, 'screens', json),
            widget.provider.indicators);
      case 'config':
        return _ConfigEditor(
            (json) => _updateJsonField(context, 'config', json),
            widget.provider);
    }
    return Container();
  }
}
