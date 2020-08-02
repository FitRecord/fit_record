import 'dart:collection';
import 'dart:math';

import 'package:android/data_provider.dart';
import 'package:android/data_storage_profiles.dart';
import 'package:android/data_storage_records.dart';
import 'package:android/ui_utils.dart';
import 'package:charts_flutter_cf/charts_flutter_cf.dart' as charts;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong/latlong.dart';

class RecordDetailsPane extends StatefulWidget {
  final DataProvider provider;
  final int id;

  const RecordDetailsPane(this.provider, this.id);

  @override
  State<StatefulWidget> createState() => _RecordDetailsState();

  static Future open(BuildContext ctx, DataProvider provider, int id) async {
    return Navigator.push(ctx,
        MaterialPageRoute(builder: (ctx) => RecordDetailsPane(provider, id)));
  }
}

class _TabInfo {
  final int _lap;
  final Map<String, double> _row;
  final ChartSeries _altitude, _pace, _hrm, _power, _cadence;
  final List<charts.TickSpec> _ticks;
  final Polyline _path;
  final Polyline _subPath;
  LatLngBounds _bounds;
  MapController _map;
  _TabInfo(this._lap, this._row, this._altitude, this._pace, this._hrm,
      this._power, this._cadence, this._ticks, this._path, this._subPath) {
    if (_path != null) {
      double latMin = _path.points.first.latitude;
      double lonMin = _path.points.first.longitude;
      double latMax = latMin;
      double lonMax = lonMin;
      _path.points.forEach((p) {
        latMin = min(latMin, p.latitude);
        lonMin = min(lonMin, p.longitude);
        latMax = max(latMax, p.latitude);
        lonMax = max(lonMax, p.longitude);
      });
      _bounds = LatLngBounds(LatLng(latMin, lonMin), LatLng(latMax, lonMax));
      _map = MapController();
    }
  }

  String scope() => _lap == 0 ? 'total' : 'lap';
}

class _RecordDetailsState extends State<RecordDetailsPane>
    with SingleTickerProviderStateMixin {
  Record _record;
  Profile _profile;
  List<_TabInfo> _tabInfo;
  List<SyncConfig> _syncConfigs;
  final titleEditor = TextEditingController();
  final descritptionEditor = TextEditingController();
  TabController lapTabs;
  bool _syncing = false;

  int _lapsCount(Record record) => (record?.laps?.length ?? 0) + 1;

  LatLng _extractPoint(map, key) {
    final lat = map['loc_latitude'];
    final lon = map['loc_longitude'];
    if (lat != null && lon != null) return LatLng(lat, lon);
    return null;
  }

  List<_TabInfo> _loadTabs(BuildContext ctx, Profile profile, Record item) {
    if (item.trackpoints.isEmpty) return null;
    final result = <_TabInfo>[];
    _TabInfo _buildOne(int lap, int from, int to, _TabInfo total) {
      final scope = to != null ? 'lap' : 'total';
      final row = to != null ? item.trackpoints[to] : item.trackpoints.last;
      final first = item.trackpoints[from];
      final totalTime =
          ((row['time_total'] - first['time_total']) / 1000).round();
      final timeStep = secondsStep(totalTime);
      final timeTicks = [
        for (var i = 0; i < totalTime - timeStep; i += timeStep)
          charts.TickSpec(i, label: formatDurationSeconds(i))
      ];
      timeTicks.add(
          charts.TickSpec(totalTime, label: formatDurationSeconds(totalTime)));

      final indicator = profile.speedIndicator();
      final altitude = _altitudeSeries(ctx,
          item.extractData('loc_altitude', from, to, (map, key) => map[key]));
      final pace = _paceSpeedSeries(ctx, indicator, profile,
          item.extractData(indicator, from, to, (map, key) => map[key]),
          average: row['loc_${scope}_${indicator}']);
      final hrm = _hrmSeries(ctx, profile,
          item.extractData('sensor_hrm', from, to, (map, key) => map[key]),
          average: row['sensor_hrm_${scope}_avg']);
      final cadence = _cadenceSeries(ctx,
          item.extractData('sensor_cadence', from, to, (map, key) => map[key]),
          average: row['sensor_cadence_${scope}_avg']);
      final power = _powerSeries(ctx, profile,
          item.extractData('sensor_power', from, to, (map, key) => map[key]),
          average: row['sensor_power_${scope}_avg']);
      final pathData = item
          .extractData('', from, to, _extractPoint)
          ?.values
          ?.where((element) => element != null);
      Polyline polyline;
      if (pathData?.isNotEmpty == true) {
        polyline = Polyline(
            points: pathData.toList(),
            strokeWidth: 3.0,
            color: total != null ? Colors.blue : Colors.red);
      }
      return _TabInfo(
          lap,
          row,
          altitude,
          pace,
          hrm,
          power,
          cadence,
          timeTicks,
          total != null ? total._path : polyline,
          total != null ? polyline : null);
    }

    final total = _buildOne(0, 0, null, null);
    result.add(total);
    final lapCount = _lapsCount(item);
    if (lapCount > 1) {
      // Render lap info
      List.generate(lapCount, (index) => index).forEach((lap) {
        final startIndex = lap > 1 ? item.laps[lap - 1] + 1 : 0;
        final endIndex =
            lap < lapCount - 1 ? item.laps[lap] : item.trackpoints.length - 1;
        result.add(_buildOne(lap + 1, startIndex, endIndex, total));
      });
    }
    return result;
  }

  Future _load(BuildContext ctx) async {
    try {
      final item = await widget.provider.records.loadOne(
          widget.provider.indicators, widget.provider.profiles, widget.id);
      final profile = await widget.provider.profiles.one(item.profileID);
      final _tabs = _loadTabs(ctx, profile, item);
      final syncConfigs = await widget.provider.sync.all();
      setState(() {
        _record = item;
        _profile = profile;
        titleEditor.text = item.title ?? '';
        descritptionEditor.text = item.description ?? '';
        lapTabs = TabController(length: _lapsCount(item) + 1, vsync: this);
        _tabInfo = _tabs;
        _syncConfigs = syncConfigs;
      });
    } catch (e) {
      print('Error loading record: $e');
      showMessage(ctx, 'Something is not good');
    }
  }

  @override
  void initState() {
    super.initState();
    _load(context);
  }

  Widget _buildEditForm(BuildContext ctx, Record record) {
    return Padding(
        padding: EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: titleEditor,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 1,
              decoration: InputDecoration(labelText: 'Title:'),
            ),
            TextFormField(
              controller: descritptionEditor,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              decoration: InputDecoration(labelText: 'Description:'),
            ),
          ],
        ));
  }

  Future _saveForm(BuildContext ctx, Record item) async {
    item.title = textFromCtrl(titleEditor);
    item.description = textFromCtrl(descritptionEditor);
    try {
      await widget.provider.records.updateFields(item);
      Navigator.pop(ctx, true);
    } catch (e) {
      print('Failed to update: $e');
      showMessage(ctx, 'Something is not good');
    }
  }

  ChartSeries _altitudeSeries(BuildContext ctx, Map<int, double> data) {
    return chartsMake(ctx, data, 'altitude', Colors.grey,
        widget.provider.indicators.indicators['loc_altitude'],
        renderer: 'altitude',
        smooth: 30,
        zoom: 100,
        axisID: 'secondaryMeasureAxisId');
  }

  ChartSeries _hrmSeries(
      BuildContext ctx, Profile profile, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'hrm',
      Colors.red,
      widget.provider.indicators.indicators['sensor_hrm'],
      average: average,
      zones: profile.zonesHrmJson,
    );
  }

  ChartSeries _cadenceSeries(BuildContext ctx, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'cadence',
      Colors.pink,
      widget.provider.indicators.indicators['sensor_cadence'],
      average: average,
    );
  }

  ChartSeries _powerSeries(
      BuildContext ctx, Profile profile, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'power',
      Colors.yellow,
      widget.provider.indicators.indicators['sensor_power'],
      average: average,
      zones: profile.zonesPowerJson,
    );
  }

  ChartSeries _paceSpeedSeries(BuildContext ctx, String indicator,
      Profile profile, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'pace/speed',
      Colors.blue,
      widget.provider.indicators.indicators[indicator],
      smooth: 20,
      average: average,
      zones: profile.zonesPaceJson,
    );
  }

  Widget _buildOverview(BuildContext ctx, Record item, _TabInfo tab) {
    final page = _profile.defaultScreen(tab.scope(), true);
    final sensors = renderSensors(
        ctx, widget.provider.indicators, tab._row, page, 'Overview:');
    final paceChart =
        chartsMakeChart(ctx, [tab._pace, tab._altitude], tab._ticks);
    return columnMaybe([sensors, paceChart]);
  }

  Widget _buildHrm(BuildContext ctx, Record item, _TabInfo tab) {
    final scope = tab.scope();
    final page = [
      [
        {'id': 'sensor_hrm_${scope}_avg'},
      ],
      [
        {'id': 'sensor_hrm_${scope}_min'},
        {'id': 'sensor_hrm_${scope}_max'},
      ]
    ];
    final sensors = renderSensors(
        ctx, widget.provider.indicators, tab._row, page, 'Heart rate:');
    final chart = chartsMakeChart(ctx, [tab._hrm, tab._altitude], tab._ticks);
    return columnMaybe([sensors, chart]);
  }

  Widget _buildPower(BuildContext ctx, Record item, _TabInfo tab) {
    final scope = tab.scope();
    final page = [
      [
        {'id': 'sensor_power_${scope}_avg'},
      ],
      [
        {'id': 'sensor_power_${scope}_min'},
        {'id': 'sensor_power_${scope}_max'},
      ]
    ];
    final chart = chartsMakeChart(ctx, [tab._power, tab._altitude], tab._ticks);
    final sensors = renderSensors(
        ctx, widget.provider.indicators, tab._row, page, 'Power:');
    return columnMaybe([sensors, chart]);
  }

  Widget _buildCadence(BuildContext ctx, Record item, _TabInfo tab) {
    final scope = tab.scope();
    final page = [
      [
        {'id': 'sensor_cadence_${scope}_avg'},
      ],
      [
        {'id': 'sensor_cadence_${scope}_min'},
        {'id': 'sensor_cadence_${scope}_max'},
      ]
    ];
    final chart =
        chartsMakeChart(ctx, [tab._cadence, tab._altitude], tab._ticks);
    final sensors = renderSensors(
        ctx, widget.provider.indicators, tab._row, page, 'Cadence:');
    return columnMaybe([sensors, chart]);
  }

  Widget _buildTab(BuildContext ctx, _TabInfo tab, Record record) {
    final listItems = <Widget>[];
    if (tab._lap == 0) {
      listItems.add(_buildEditForm(context, record));
      listItems.add(_buildOverview(context, record, tab));
    } else {
      listItems.add(_buildOverview(context, record, tab));
    }
    if (tab._path != null) {
      final map = mapRenderInteractive(
          ctx, tab._map, [tab._path, tab._subPath], tab._bounds);
      listItems.add(map);
    }
    if (tab._row.containsKey('sensor_hrm')) {
      listItems.add(_buildHrm(ctx, record, tab));
    }
    if (tab._row.containsKey('sensor_power')) {
      listItems.add(_buildPower(ctx, record, tab));
    }
    if (tab._row.containsKey('sensor_cadence')) {
      listItems.add(_buildCadence(ctx, record, tab));
    }
    return ListView(
      padding: EdgeInsets.only(bottom: 80.0),
      children: listItems,
    );
  }

  Future _sync(BuildContext ctx, SyncConfig config) async {
    try {
      setState(() => _syncing = true);
      await widget.provider.sync
          .upload(widget.provider, _record, _profile, config);
    } catch (e) {
      print('_sync error: $e');
      showMessage(ctx, 'Something is not good');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _record;
    Widget appBarBottom;
    Widget body = Container();
    if (item != null) {
//      print('Laps: ${_lapsCount(item)}');
      if (_tabInfo.length > 1) {
        // Render lap info
        final tabs = _tabInfo
            .map((t) => Tab(text: t._lap == 0 ? 'Overview' : 'Lap ${t._lap}'))
            .toList();
        appBarBottom = TabBar(
          tabs: tabs,
          controller: lapTabs,
        );
        final tabViews =
            _tabInfo.map((t) => _buildTab(context, t, item)).toList();
        body = TabBarView(
          controller: lapTabs,
          children: tabViews,
        );
      } else {
        body = _buildTab(context, _tabInfo[0], item);
      }
    } else {
      body = Center(
        child: CircularProgressIndicator(),
      );
    }
    Widget title = Text('Loading...');
    if (item != null && _profile != null) {
      title = Row(
        children: [
          Padding(
            padding: EdgeInsets.only(right: 4.0),
            child: profileIcon(_profile),
          ),
          Expanded(
            child: Text(
              item.smartTitle(),
            ),
          )
        ],
      );
    }
    Widget syncMenu;
    if (_syncConfigs?.isNotEmpty == true) {
      syncMenu = PopupMenuButton<SyncConfig>(
        icon: Icon(Icons.sync),
        onSelected: (item) => _sync(context, item),
        itemBuilder: (ctx) => _syncConfigs
            .map((e) => PopupMenuItem<SyncConfig>(
                  child: ListTile(
                    trailing: Checkbox(
                        value: _record.syncJson[e.id.toString()] != null,
                        onChanged: null),
                    title: Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  value: e,
                ))
            .toList(),
      );
    }
    if (_syncing) {
      body = Stack(
        children: [body, CircularProgressIndicator()],
        alignment: Alignment.center,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: [
          syncMenu,
          dotsMenu(
              context,
              LinkedHashMap.fromIterables(
                ['TCX Export', 'Delete'],
                [
                  () => _exportRecord(context, widget.id, 'tcx'),
                  () => _deleteRecord(context, widget.id)
                ],
              ))
        ].where((e) => e != null).toList(),
        bottom: appBarBottom,
      ),
      body: body,
      floatingActionButton: _record != null
          ? FloatingActionButton(
              onPressed: () => _saveForm(context, item),
              child: Icon(Icons.done),
            )
          : null,
    );
  }

  _deleteRecord(BuildContext ctx, int id) async {
    final yes = await yesNoDialog(ctx, 'Delete selected record?');
    if (!yes) return;
    try {
      await widget.provider.records.deleteOne(id);
      return Navigator.pop(ctx, true);
    } catch (e) {
      print('Error deleting: $e');
    }
  }

  _exportRecord(BuildContext ctx, int id, String type) async {
    try {
      await widget.provider.recording.export(id, type);
    } catch (e) {
      print('Export error: $e');
    }
  }
}
