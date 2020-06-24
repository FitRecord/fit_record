import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/data_storage.dart';
import 'package:android/ui_main.dart';
import 'package:android/ui_utils.dart';
import 'package:charts_flutter_cf/charts_flutter_cf.dart' as charts;
import 'package:flutter/material.dart';

class HistoryPane extends MainPaneState {
  List<Record> _records;
  Map<int, Profile> _profiles;
  final _dateTimeFormat = dateTimeFormat();

  Future _load(BuildContext ctx) async {
    try {
      final list = await widget.provider.records.history();
      final profiles = await widget.provider.profiles.all();
      setState(() {
        _profiles = Map.fromIterable(profiles, key: (el) => el.id);
        _records = list;
      });
    } catch (e) {
      print('Load history error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History'),
      ),
      body: RefreshIndicator(
          child: ListView.builder(
              itemCount: _records?.length ?? 0,
              itemBuilder: (ctx, index) => _buildItem(ctx, index)),
          onRefresh: () => _load(context)),
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }

  _deleteRecord(BuildContext ctx, Record record) async {
    final yes = await yesNoDialog(ctx, 'Delete selected record?');
    if (!yes) return;
    try {
      widget.provider.records.deleteOne(record);
      return _load(ctx);
    } catch (e) {
      print('Error deleting: $e');
    }
  }

  Widget _buildItem(BuildContext ctx, int index) {
    final item = _records[index];
    final dateTime = _dateTimeFormat
        .format(DateTime.fromMillisecondsSinceEpoch(item.started));
    final theme = Theme.of(ctx).primaryTextTheme;
    final profile = _profiles[item.profileID];
    final bottomRow = <Widget>[
      profileIcon(profile),
      Text(
        profile?.title ?? '?',
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.subtitle2,
      )
    ];
    if (profile?.title == null) {
      bottomRow.add(Expanded(
          child: Text(
        dateTime,
        textAlign: TextAlign.end,
        style: theme.caption,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      )));
    }
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item.smartTitle(),
          style: theme.subtitle1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: bottomRow,
        )
      ],
    );
    return ListTile(
      onTap: () => _openRecord(ctx, item),
      title: col,
      trailing: dotsMenu(
          ctx,
          LinkedHashMap.fromIterables(
              ['Delete'], [() => _deleteRecord(ctx, item)])),
    );
  }

  Future _openRecord(BuildContext ctx, Record item) async {
    await RecordDetailsPane.open(ctx, widget.provider, item);
    return _load(ctx);
  }
}

class RecordDetailsPane extends StatefulWidget {
  final DataProvider provider;
  final Record record;

  const RecordDetailsPane(this.provider, this.record);

  @override
  State<StatefulWidget> createState() => _RecordDetailsState();

  static Future open(
      BuildContext ctx, DataProvider provider, Record record) async {
    return Navigator.push(
        ctx,
        MaterialPageRoute(
            builder: (ctx) => RecordDetailsPane(provider, record)));
  }
}

class _RecordDetailsState extends State<RecordDetailsPane>
    with SingleTickerProviderStateMixin {
  Record _record;
  Profile _profile;
  final titleEditor = TextEditingController();
  final descritptionEditor = TextEditingController();
  TabController lapTabs;

  int _lapsCount(Record record) => (record?.laps?.length ?? 0) + 1;

  Future _load(BuildContext ctx) async {
    try {
      final item = await widget.provider.records
          .loadOne(widget.provider.indicators, widget.record.id);
      final profile = await widget.provider.profiles.one(item.profileID);
      setState(() {
        _record = item;
        _profile = profile;
        titleEditor.text = item.title ?? '';
        descritptionEditor.text = item.description ?? '';
        lapTabs = TabController(length: _lapsCount(item) + 1, vsync: this);
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
        smoothFactor: 80,
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

  ChartSeries _powerSeries(BuildContext ctx, Map<int, double> data,
      {bool extended = false}) {
    return chartsMake(
      ctx,
      data,
      'power',
      charts.MaterialPalette.yellow.shadeDefault,
      widget.provider.indicators.indicators['sensor_power'],
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
      smoothFactor: 120,
      average: average,
      invert: invert,
    );
  }

  Widget _buildOverview(BuildContext ctx, Record item, int from, int to) {
    final scope = to != null ? 'lap' : 'total';
    final page = _profile.defaultScreen(scope, true);
    final indicator = _profile.speedIndicator();
    final altitude =
        _altitudeSeries(ctx, item.extractData('loc_altitude', from, to));
    final hrm = _hrmSeries(ctx, item.extractData('sensor_hrm', from, to));
    final power = _powerSeries(ctx, item.extractData('sensor_power', from, to));
    final pace = _paceSpeedSeries(
        ctx, indicator, item.extractData(indicator, from, to), true);
    final row = to != null ? item.trackpoints[to] : item.trackpoints.last;
    final sensors =
        renderSensors(ctx, widget.provider.indicators, row, page, 'Overview:');
    final axis = [altitude, hrm, power, pace];
    final chart = chartsMakeChart(ctx, axis, chartsNoTicksAxis());
    final pace2 = _paceSpeedSeries(ctx, _profile.speedIndicator(),
        item.extractData(_profile.speedIndicator(), from, to), true,
        average: row['loc_${scope}_${indicator}']);
    final paceChart = chartsMakeChart(ctx, [altitude, pace2], pace2?.axisSpec);
    return columnMaybe([sensors, chart, paceChart]);
  }

  Widget _buildHrm(BuildContext ctx, Record item, int from, int to) {
    final scope = to != null ? 'lap' : 'total';
    final page = [
      [
        {'id': 'sensor_hrm_${scope}_avg'},
      ],
      [
        {'id': 'sensor_hrm_${scope}_min'},
        {'id': 'sensor_hrm_${scope}_max'},
      ]
    ];
    final row = to != null ? item.trackpoints[to] : item.trackpoints.last;
    final sensors = renderSensors(
        ctx, widget.provider.indicators, row, page, 'Heart rate:');
    final altitude =
        _altitudeSeries(ctx, item.extractData('loc_altitude', from, to));
    final hrm = _hrmSeries(ctx, item.extractData('sensor_hrm', from, to),
        average: row['sensor_hrm_${scope}_avg']);
    final chart = chartsMakeChart(ctx, [altitude, hrm], hrm?.axisSpec);
    return columnMaybe([sensors, chart]);
  }

  Widget _buildPower(BuildContext ctx, Record item, int from, int to) {
    final scope = to != null ? 'lap' : 'total';
    final page = [
      [
        {'id': 'sensor_power_${scope}_avg'},
      ],
      [
        {'id': 'sensor_power_${scope}_min'},
        {'id': 'sensor_power_${scope}_max'},
      ]
    ];
    final altitude =
        _altitudeSeries(ctx, item.extractData('loc_altitude', from, to));
    final power = _powerSeries(ctx, item.extractData('sensor_power', from, to));
    final chart = chartsMakeChart(ctx, [altitude, power], power?.axisSpec);
    final sensors = renderSensors(
        ctx,
        widget.provider.indicators,
        to != null ? item.trackpoints[to] : item.trackpoints.last,
        page,
        'Power:');
    return columnMaybe([sensors, chart]);
  }

  Widget _buildTab(BuildContext ctx, int index, Record record) {
    final listItems = <Widget>[];
    int endIndex;
    int startIndex = 0;
    if (index == null) {
      startIndex = 0;
      listItems.add(_buildEditForm(context, record));
      listItems.add(_buildOverview(context, record, 0, null));
    } else {
      endIndex = index < record.laps.length
          ? record.laps[index]
          : record.trackpoints.length - 1;
      startIndex = index > 0 ? record.laps[index - 1] + 1 : 0;
      listItems.add(_buildOverview(context, record, startIndex, endIndex));
    }
    if (record.trackpoints.last.containsKey('sensor_hrm')) {
      listItems.add(_buildHrm(ctx, record, startIndex, endIndex));
    }
    if (record.trackpoints.last.containsKey('sensor_power')) {
      listItems.add(_buildPower(ctx, record, startIndex, endIndex));
    }
    return ListView(
      children: listItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _record ?? widget.record;
    Widget appBarBottom;
    Widget body = Container();
    if (item.trackpoints?.isNotEmpty == true) {
      print('Laps: ${_lapsCount(item)}');
      final lapCount = _lapsCount(item);
      if (lapCount > 1) {
        // Render lap info
        final indexes = List.generate(lapCount, (index) => index);
        final tabs = [Tab(text: 'Overview')];
        tabs.addAll(indexes.map((index) => Tab(text: 'Lap ${index + 1}')));
        appBarBottom = TabBar(
          tabs: tabs,
          controller: lapTabs,
        );
        final tabViews = [_buildTab(context, null, item)];
        tabViews
            .addAll(indexes.map((index) => _buildTab(context, index, item)));
        body = TabBarView(
          controller: lapTabs,
          children: tabViews,
        );
      } else {
        body = _buildTab(context, null, item);
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(item.smartTitle()),
        bottom: appBarBottom,
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _saveForm(context, item),
        child: Icon(Icons.done),
      ),
    );
  }
}
