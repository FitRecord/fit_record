import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/data_storage.dart';
import 'package:android/ui_utils.dart';
import 'package:charts_flutter_cf/charts_flutter_cf.dart' as charts;
import 'package:flutter/material.dart';

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

  _TabInfo(this._lap, this._row, this._altitude, this._pace, this._hrm,
      this._power, this._cadence, this._ticks);

  String scope() => _lap == 0 ? 'total' : 'lap';
}

class _RecordDetailsState extends State<RecordDetailsPane>
    with SingleTickerProviderStateMixin {
  Record _record;
  Profile _profile;
  List<_TabInfo> _tabInfo;
  final titleEditor = TextEditingController();
  final descritptionEditor = TextEditingController();
  TabController lapTabs;

  int _lapsCount(Record record) => (record?.laps?.length ?? 0) + 1;

  List<_TabInfo> _loadTabs(BuildContext ctx, Profile profile, Record item) {
    if (item.trackpoints.isEmpty) return null;
    final result = <_TabInfo>[];
    _TabInfo _buildOne(int lap, int from, int to) {
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
      final altitude =
          _altitudeSeries(ctx, item.extractData('loc_altitude', from, to));
      final pace = _paceSpeedSeries(
          ctx, indicator, item.extractData(indicator, from, to), true,
          average: row['loc_${scope}_${indicator}']);
      final hrm = _hrmSeries(ctx, item.extractData('sensor_hrm', from, to),
          average: row['sensor_hrm_${scope}_avg']);
      final cadence = _cadenceSeries(
          ctx, item.extractData('sensor_cadence', from, to),
          average: row['sensor_cadence_${scope}_avg']);
      final power = _powerSeries(
          ctx, item.extractData('sensor_power', from, to),
          average: row['sensor_power_${scope}_avg']);
      return _TabInfo(lap, row, altitude, pace, hrm, power, cadence, timeTicks);
    }

    final total = _buildOne(0, 0, null);
    result.add(total);
    final lapCount = _lapsCount(item);
    if (lapCount > 1) {
      // Render lap info
      List.generate(lapCount, (index) => index).forEach((lap) {
        final startIndex = lap > 1 ? item.laps[lap - 1] + 1 : 0;
        final endIndex =
            lap < lapCount - 1 ? item.laps[lap] : item.trackpoints.length - 1;
        result.add(_buildOne(lap + 1, startIndex, endIndex));
      });
    }
    return result;
  }

  Future _load(BuildContext ctx) async {
    try {
      final item = await widget.provider.records
          .loadOne(widget.provider.indicators, widget.id);
      final profile = await widget.provider.profiles.one(item.profileID);
      final _tabs = _loadTabs(ctx, profile, item);
      setState(() {
        _record = item;
        _profile = profile;
        titleEditor.text = item.title ?? '';
        descritptionEditor.text = item.description ?? '';
        lapTabs = TabController(length: _lapsCount(item) + 1, vsync: this);
        _tabInfo = _tabs;
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
    return chartsMake(
        ctx,
        data,
        'altitude',
        charts.MaterialPalette.gray.shadeDefault,
        widget.provider.indicators.indicators['loc_altitude'],
        renderer: 'altitude',
        smooth: 30,
        zoom: 100,
        axisID: 'secondaryMeasureAxisId');
  }

  ChartSeries _hrmSeries(BuildContext ctx, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'hrm',
      charts.MaterialPalette.red.shadeDefault,
      widget.provider.indicators.indicators['sensor_hrm'],
      average: average,
    );
  }

  ChartSeries _cadenceSeries(BuildContext ctx, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'cadence',
      charts.MaterialPalette.pink.shadeDefault,
      widget.provider.indicators.indicators['sensor_cadence'],
      average: average,
    );
  }

  ChartSeries _powerSeries(BuildContext ctx, Map<int, double> data,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'power',
      charts.MaterialPalette.yellow.shadeDefault,
      widget.provider.indicators.indicators['sensor_power'],
      average: average,
    );
  }

  ChartSeries _paceSpeedSeries(
      BuildContext ctx, String indicator, Map<int, double> data, bool invert,
      {double average}) {
    return chartsMake(
      ctx,
      data,
      'pace/speed',
      charts.MaterialPalette.blue.shadeDefault,
      widget.provider.indicators.indicators[indicator],
      smooth: 20,
      average: average,
      invert: invert,
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

  @override
  Widget build(BuildContext context) {
    final item = _record;
    Widget appBarBottom;
    Widget body = Container();
    if (item != null) {
      print('Laps: ${_lapsCount(item)}');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(item?.smartTitle() ?? 'Loading...'),
        actions: [
          dotsMenu(
              context,
              LinkedHashMap.fromIterables([
                'TCX Export',
                'Delete'
              ], [
                () => _exportRecord(context, widget.id, 'tcx'),
                () => _deleteRecord(context, widget.id)
              ]))
        ],
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
