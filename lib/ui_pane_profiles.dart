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
  final Map<String, dynamic> _data;

  const _ConfigEditor(this._data, this._onChanged, this._provider);

  @override
  State<StatefulWidget> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<_ConfigEditor> {
  final _sensors = <Sensor>[];
  Map<String, dynamic> _sensorsChecks = Map<String, dynamic>();
  Map<String, dynamic> _zonesChecks;

  @override
  void initState() {
    _sensorsChecks = widget._data['sensors'] ?? Map<String, dynamic>();
    _zonesChecks = widget._data['zones'] ?? Map<String, dynamic>();
    super.initState();
    _load(context);
  }

  _checkSensor(BuildContext ctx, String id, bool checked) {
    setState(() {
      _sensorsChecks[id] = checked;
      widget._data['sensors'] = _sensorsChecks;
      widget._onChanged(widget._data);
    });
  }

  _checkZone(String type, bool checked) {
    setState(() {
      _zonesChecks[type] = checked;
      widget._data['zones'] = _zonesChecks;
      widget._onChanged(widget._data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final headerTheme = Theme.of(context).textTheme.headline6;
    final items = <Widget>[];
    items.add(ListTile(
      title: Text(
        'Sensors:',
        style: headerTheme,
      ),
      trailing: IconButton(
          icon: Icon(Icons.add), onPressed: () => _addSensor(context)),
    ));
    items.addAll(_sensors.map((item) {
      final checked = _sensorsChecks[item.id] ?? true;
      return ListTile(
        leading: Checkbox(
            value: checked,
            onChanged: (checked) => _checkSensor(context, item.id, checked)),
        title: renderSensorTile(context, item, showAddress: !item.system),
        trailing: !item.system
            ? dotsMenu(
                context,
                LinkedHashMap.fromIterables(
                    ['Remove'], [() => _deleteSensor(context, item)]))
            : null,
      );
    }));
    items.add(ListTile(
      title: Text(
        'Intensivity zones:',
        style: headerTheme,
      ),
    ));
    items.addAll(ProfilesPane.zonesConfig.entries
        .map((el) => {'type': el.value['id'], 'title': el.value['short']})
        .map((el) => ListTile(
              leading: Checkbox(
                  value: _zonesChecks[el['type']] == true,
                  onChanged: (val) => _checkZone(el['type'], val)),
              title: Text(el['title']),
            )));
    return ListView(
      children: items,
    );
  }

  _load(BuildContext ctx) async {
    try {
      final data = await widget._provider.profiles.allSensors();
      if (mounted)
        setState(() {
          _sensors.clear();
          _sensors.addAll(data);
        });
    } catch (e) {
      print('Error: $e');
      showMessage(ctx, 'Something is not right');
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
  String _selectedTab = 'screens';

  static final zonesConfig = LinkedHashMap.fromIterables([
    'zones_pace',
    'zones_hrm',
    'zones_power',
  ], [
    {'title': 'Pace Zones', 'id': 'pace', 'short': 'Pace'},
    {'title': 'Heart Rate Zones', 'id': 'hrm', 'short': 'Hearth Rate'},
    {'title': 'Power Zones', 'id': 'power', 'short': 'Power'},
  ]);

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

  List<Map<String, String>> _activeTabs() {
    final tabs = <Map<String, String>>[
      {'id': 'screens', 'title': 'Screen (App)'}
    ];
    final config = profile.configJson['zones'] ?? Map();
    tabs.addAll(zonesConfig.entries.map((e) {
      if (config[e.value['id']] == true)
        return {'id': e.key, 'title': e.value['title']};
      return null;
    }).where((element) => element != null));
    tabs.add({'id': 'config', 'title': 'Configuration'});
    return tabs;
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

  _updateJsonField(BuildContext ctx, String field, dynamic json,
      Function(String value) callback) async {
    try {
      final value =
          await widget.provider.profiles.updateJsonField(profile, field, json);
      setState(() => callback(value));
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
    final index = tabs.map((e) => e['id']).toList().indexOf(_selectedTab);
    print('Select tab: $index $_selectedTab');
    return DefaultTabController(
        length: tabs.length,
        initialIndex: index == -1 ? 0 : index,
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

  String _validatePace(String value) {
    int val = parseDuration(value);
    if (val == null || val <= 0) return 'minute:seconds e.g. 4:30';
    return null;
  }

  String _renderPace(double value) => value != null
      ? widget.provider.indicators.formatSimple('pace_sm', value, false)
      : '';

  double _parsePace(String value) {
    final val = parseDuration(value);
    if (val != null) return val / 1000;
    return null;
  }

  Function(List<Map<String, double>>) _saveZones(
      BuildContext ctx, String name, Function(String) callback) {
    return (data) async {
      await _updateJsonField(ctx, name, data, callback);
    };
  }

  Widget _buildZonesEditors(BuildContext ctx, String id) {
    Widget _buildForm(BuildContext ctx, BoxConstraints box) {
      switch (id) {
        case 'zones_pace':
          return _ZonesEditor(
            profile.zonesPaceJson,
            TextInputType.text,
            _renderPace,
            _validatePace,
            _parsePace,
            _saveZones(ctx, 'zones_pace', (val) => profile.zonesPace = val),
          );
        case 'zones_hrm':
          return _ZonesEditor(
            profile.zonesHrmJson,
            TextInputType.numberWithOptions(signed: false, decimal: true),
            (val) => val?.toInt()?.toString(),
            (val) => int.tryParse(val) == null ? 'Invalid number' : null,
            (val) => int.tryParse(val)?.toDouble(),
            _saveZones(ctx, 'zones_hrm', (val) => profile.zonesHrm = val),
          );
        case 'zones_power':
          return _ZonesEditor(
            profile.zonesPowerJson,
            TextInputType.numberWithOptions(signed: false, decimal: true),
            (val) => val?.toInt()?.toString(),
            (val) => int.tryParse(val) == null ? 'Invalid number' : null,
            (val) => int.tryParse(val)?.toDouble(),
            _saveZones(ctx, 'zones_power', (val) => profile.zonesPower = val),
          );
      }
    }

    return LayoutBuilder(builder: (ctx, box) => _buildForm(ctx, box));
  }

  Widget _buildTab(String id) {
    switch (id) {
      case 'screens':
        return _ScreenEditor(
            profile.screensJson,
            (json) => _updateJsonField(context, 'screens', json, (val) {
                  profile.screens = val;
                  _selectedTab = 'screens';
                }),
            widget.provider.indicators);
      case 'zones_pace':
      case 'zones_hrm':
      case 'zones_power':
        return _buildZonesEditors(context, id);
      case 'config':
        return _ConfigEditor(
            profile.configJson,
            (json) => _updateJsonField(context, 'config', json, (val) {
                  profile.config = val;
                  _selectedTab = 'config';
                }),
            widget.provider);
    }
    return Container();
  }
}

class _ZonesEditor extends StatefulWidget {
  final List<Map<String, double>> _data;
  final TextInputType _inputType;
  final String Function(String) _validator;
  final double Function(String) _converter;
  final String Function(double) _renderer;
  final Function(List<Map<String, double>>) _onData;

  _ZonesEditor(this._data, this._inputType, this._renderer, this._validator,
      this._converter, this._onData);

  @override
  State<StatefulWidget> createState() => _ZonesEditorState();
}

class _ZonesEditorState extends State<_ZonesEditor> {
  List<TextEditingController> froms;
  List<TextEditingController> tos;

  _ZonesEditorState() {}

  @override
  void initState() {
    super.initState();
    print('Zones editor: ${widget._data}');
    froms = List.generate(
        5,
        (index) => TextEditingController(
            text: widget._renderer(widget._data[index]['from'])));
    tos = List.generate(
        5,
        (index) => TextEditingController(
            text: widget._renderer(widget._data[index]['to'])));
  }

  Widget _buildForm(BuildContext ctx) {
    final titleStyle = Theme.of(ctx).primaryTextTheme.headline6;
    _changed(int index) {
      final form = Form.of(ctx);
      if (form.validate()) {
        for (var i = 0; i < 5; i++) {
          widget._data[i]['from'] = widget._converter(froms[i].text);
          widget._data[i]['to'] = widget._converter(tos[i].text);
        }
        widget._onData(widget._data);
      }
    }

    _toChanged(String val, int index) {
      if (index < 4) froms[index + 1].text = val;
      _changed(index);
    }

    final list = List.generate(5, (index) {
      bool fromEnabled = index == 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Zone ${index + 1}',
              style: titleStyle,
            ),
          ),
          Row(
            children: [
              Expanded(
                  child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: TextFormField(
                  onChanged: (val) => _changed(index),
                  controller: froms[index],
                  readOnly: !fromEnabled,
                  decoration: InputDecoration(labelText: 'From:'),
                  maxLines: 1,
                  keyboardType: widget._inputType,
                  validator: widget._validator,
                ),
              )),
              Expanded(
                  child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: TextFormField(
                  onChanged: (val) => _toChanged(val, index),
                  controller: tos[index],
                  decoration: InputDecoration(labelText: 'To:'),
                  maxLines: 1,
                  keyboardType: widget._inputType,
                  validator: widget._validator,
                ),
              )),
            ],
          )
        ],
      );
    }).reversed.toList();
    return Column(
      children: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        child: LayoutBuilder(builder: (ctx, box) => _buildForm(ctx)),
      ),
    );
  }
}
