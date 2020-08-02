import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/data_storage_profiles.dart';
import 'package:android/data_storage_records.dart';
import 'package:android/ui_main.dart';
import 'package:android/ui_pane_activity.dart';
import 'package:android/ui_utils.dart';
import 'package:charts_flutter_cf/charts_flutter_cf.dart' as charts;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryPane extends MainPaneState {
  final _records = Map<int, HistoryResult>();
  Map<int, Profile> _profiles;
  Map<String, SyncConfig> _syncConfigs;
  HistoryRange _range = HistoryRange.Week;
  DateTime _date = DateTime.now();
  final _dateTimeFormat = dateTimeFormat();
  final _pages = PageController(keepPage: false);
  int _page = 0;
  final _keys = [
    'time_total',
    'loc_total_distance',
  ];
  String _statKey = 'time_total';
  bool configVisible = false;

  _historyUpdated() {
    _load(context);
  }

  _toggleConfigPanel() {
    setState(() => configVisible = !configVisible);
  }

  Future _load(BuildContext ctx) async {
    try {
      final profiles = await widget.provider.profiles.all();
      final syncConfigs = await widget.provider.sync.all();
      setState(() {
        _date = DateTime.now();
        _records.clear();
        _profiles = Map.fromIterable(profiles, key: (el) => el.id);
        _syncConfigs =
            Map.fromIterable(syncConfigs, key: (el) => el.id.toString());
      });
    } catch (e) {
      print('Load history error: $e');
    }
  }

  @override
  void dispose() {
    widget.provider.recording.historyNotifier.removeListener(_historyUpdated);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _range = HistoryRange.values.firstWhere(
        (r) =>
            r.toString() ==
            widget.provider.preferences.getString('history_range'),
        orElse: () => _range);
    _statKey = _keys.firstWhere(
        (el) => el == widget.provider.preferences.getString('history_stat_key'),
        orElse: () => _statKey);
    widget.provider.recording.historyNotifier.addListener(_historyUpdated);
    _load(context);
  }

  Future _addRecord(BuildContext ctx) async {
    await _RecordEditor.open(ctx, widget.provider);
    return _load(ctx);
  }

  Future _startImport(BuildContext ctx) async {
    widget.provider.recording.startImport();
  }

  Future _loadPage(BuildContext ctx, int index) async {
    try {
      final data = await widget.provider.records.history(
          widget.provider.profiles, _range, _date, index,
          statKey: _statKey);
      if (mounted) setState(() => _records[index] = data);
    } catch (e) {
      print('Error in history(): $e');
    }
  }

  Widget _buildChart(BuildContext ctx, HistoryResult data) {
    final textColor =
        charts.ColorUtil.fromDartColor(Theme.of(ctx).textTheme.bodyText1.color);
    double max = 0;
    data.keyStats.values.forEach((el) {
      if (el != null && el > max) max = el;
    });
    List<charts.TickSpec<num>> ticks;
    if (max == 0) {
      ticks = [charts.TickSpec(0, label: '0'), charts.TickSpec(100, label: '')];
    } else {
      final half = widget.provider.indicators.formatSimple(_statKey, max / 2);
      final full = widget.provider.indicators.formatSimple(_statKey, max);
      ticks = [
        charts.TickSpec(0, label: ''),
        charts.TickSpec(50, label: half),
        charts.TickSpec(100, label: full),
      ];
    }
    final vert = charts.NumericAxisSpec(
      showAxisLine: false,
      tickProviderSpec: charts.StaticNumericTickProviderSpec(ticks),
      renderSpec: charts.SmallTickRendererSpec(
          labelStyle: charts.TextStyleSpec(color: textColor)),
    );
    final hor = charts.AxisSpec<String>(
      showAxisLine: false,
      tickProviderSpec: charts.StaticOrdinalTickProviderSpec([]),
      renderSpec: charts.SmallTickRendererSpec(
          labelStyle: charts.TextStyleSpec(color: textColor)),
    );
    final dataSeries = charts.Series<MapEntry<int, double>, String>(
        id: 'main',
        data: data.keyStats.entries.toList(),
        domainFn: (val, index) {
          return val.toString();
        },
        colorFn: (val, index) => (val.value ?? 0) > 0
            ? charts.MaterialPalette.green.shadeDefault
            : charts.MaterialPalette.gray.shadeDefault,
        measureFn: (val, index) {
          return (val.value ?? 0) > 0 ? val.value / max * 100 : 5;
        });
    final graph = charts.BarChart(
      [dataSeries],
      animate: false,
      defaultInteractions: false,
      primaryMeasureAxis: vert,
      domainAxis: hor,
    );
    return SizedBox(
      child: graph,
      height: 100,
    );
  }

  Widget _buildPage(BuildContext ctx, int index) {
    final data = _records[index];
    if (_profiles == null) {
      return Container();
    }
    if (data == null) {
      _loadPage(ctx, index);
      return Container();
    }
    final stats = _keys
        .map((e) => renderSensor(
            ctx, 26, widget.provider.indicators, data.stats, e,
            expand: false, withType: true, border: false))
        .toList();
    final colItems = <Widget>[];
    colItems.add(_buildChart(ctx, data));
    colItems.add(Wrap(
      children: stats,
      alignment: WrapAlignment.spaceBetween,
      runAlignment: WrapAlignment.spaceBetween,
    ));
    final total = Padding(
      padding: EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: colItems,
      ),
    );
    final list = RefreshIndicator(
        child: ListView.builder(
            itemCount: data.records.length,
            itemBuilder: (ctx, idx) => _buildItem(ctx, index, idx)),
        onRefresh: () => _load(context));
    return Column(
      children: [total, Expanded(child: list)],
    );
  }

  _onPageChange(int index) {
    setState(() {
      _page = index;
    });
  }

  Widget _buildConfigPanel(BuildContext ctx) {
    final textStyle = Theme.of(ctx).textTheme.button;
    Widget _buildGrid(Map<String, Widget> data) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: data.entries
            .map((row) => Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                        child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        row.key,
                        style: textStyle,
                      ),
                    )),
                    Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: row.value,
                    ),
                  ],
                ))
            .toList(),
      );
    }

    return _buildGrid(LinkedHashMap.fromIterables([
      'Range:',
      'Metric:',
    ], <Widget>[
      RaisedButton(
        color: Colors.blue,
        child: Text(_rangeTitle(_range)),
        onPressed: () => _changeRange(ctx),
      ),
      RaisedButton(
        color: Colors.blue,
        child: Text(_keyTitle(_statKey)),
        onPressed: () => _changeKey(ctx),
      ),
    ]));
  }

  T _nextArrayValue<T>(List<T> data, T value) {
    return data[(data.indexOf(value) + 1) % data.length];
  }

  _changeRange(BuildContext ctx) {
    final range = _nextArrayValue(HistoryRange.values, _range);
    widget.provider.preferences.setString('history_range', range.toString());
    _range = range;
    _records.clear();
    setState(() {
      _pages.jumpToPage(0);
    });
  }

  _changeKey(BuildContext ctx) {
    final key = _nextArrayValue(_keys, _statKey);
    widget.provider.preferences.setString('history_stat_key', key);
    _statKey = key;
    _records.clear();
    _loadPage(ctx, _page);
  }

  Widget _buildTitle(HistoryResult data) {
    if (data == null) return Text('Loading...');
    switch (_range) {
      case HistoryRange.Week:
        return Text('Week ${DateFormat.yMMMd().format(data.start)}');
      case HistoryRange.Month:
        return Text('Month ${DateFormat.yMMM().format(data.start)}');
      case HistoryRange.Year:
        return Text('Year ${DateFormat.y().format(data.start)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body = PageView.builder(
      onPageChanged: _onPageChange,
      reverse: true,
      itemBuilder: _buildPage,
      controller: _pages,
    );
    if (configVisible) {
      body = Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildConfigPanel(context), Expanded(child: body)],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(_records[_page]),
        actions: <Widget>[
          IconButton(
              icon: Icon(Icons.tune), onPressed: () => _toggleConfigPanel()),
          dotsMenu(
              context,
              HashMap.fromIterables([
                "Add activity",
                "Import TCX...",
              ], [
                () => _addRecord(context),
                () => _startImport(context),
              ])),
        ],
      ),
      body: body,
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }

  Widget _buildItem(BuildContext ctx, int page, int index) {
    final item = _records[page].records[index];
    final dateTime = _dateTimeFormat
        .format(DateTime.fromMillisecondsSinceEpoch(item.started));
    final theme = Theme.of(ctx).primaryTextTheme;
    final profile = _profiles[item.profileID];
    final bottomRow = <Widget>[
      Padding(
        padding: EdgeInsets.only(right: 4.0),
        child: Padding(
            padding: EdgeInsets.all(4.0), child: profileIcon(profile, 16.0)),
      ),
      Expanded(
          child: Text(
        profile?.title ?? '?',
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.subtitle2,
      ))
    ];
    if (textIsNotEmpty(item.title)) {
      bottomRow.add(
        Text(
          dateTime,
          textAlign: TextAlign.end,
          style: theme.subtitle2,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final sync = item.syncJson;
    sync.entries.forEach((el) {
      final config = _syncConfigs[el.key];
      if (config != null && el.value != null) {
        bottomRow.add(Padding(
            padding: EdgeInsets.only(left: 4.0),
            child: Icon(
              config.provider.icon(),
              size: 16.0,
            )));
      }
    });
    final colItems = <Widget>[
      Text(
        item.smartTitle(),
        style: theme.subtitle1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    ];
    colItems.add(Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: bottomRow,
    ));
    final meta = item.metaJson;
    if (meta != null) {
      final items = [
        'time_total',
        'loc_total_${profile.speedIndicator()}',
        'loc_total_distance',
        'sensor_hrm_total_avg',
        'sensor_power_total_avg',
      ]
          .map((e) {
            final value = item.metaJson[e];
            if (value != null && value > 0) {
              return renderSensor(ctx, 20, widget.provider.indicators, meta, e,
                  expand: false, caption: false, border: false, withType: true);
            }
          })
          .where((e) => e != null)
          .take(3);
      if (items.isNotEmpty) {
        colItems.add(Wrap(
          children: items.toList(),
          alignment: WrapAlignment.spaceBetween,
          runAlignment: WrapAlignment.spaceBetween,
        ));
      }
    }
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: colItems,
    );
    return Card(
        child: InkWell(
      onTap: () => _openRecord(ctx, item),
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: col,
      ),
    ));
  }

  Future _openRecord(BuildContext ctx, Record item) async {
    await RecordDetailsPane.open(ctx, widget.provider, item.id);
    return _load(ctx);
  }

  String _rangeTitle(HistoryRange range) {
    switch (range) {
      case HistoryRange.Week:
        return 'Week';
      case HistoryRange.Month:
        return 'Month';
      case HistoryRange.Year:
        return 'Year';
    }
  }

  String _keyTitle(String statKey) {
    switch (statKey) {
      case 'loc_total_distance':
        return 'Total distance';
      case 'time_total':
        return 'Total duration';
    }
  }
}

class _RecordEditor extends StatefulWidget {
  final DataProvider _provider;

  const _RecordEditor(this._provider);

  static Future open(BuildContext ctx, DataProvider provider) => Navigator.push(
      ctx,
      MaterialPageRoute(
          builder: (ctx) => _RecordEditor(provider), fullscreenDialog: true));

  @override
  State<StatefulWidget> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  List<Profile> _profiles;
  Profile _profile;
  TextEditingController _title, _description, _distance, _duration;
  DateTime _dateTime;

  final _formID = GlobalKey<FormState>();

  _load(BuildContext ctx) async {
    try {
      final list = await widget._provider.profiles.all();
      setState(() {
        _profiles = list;
        _profile = list.first;
      });
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _dateTime = _fromDateTime(DateTime.now(), TimeOfDay.now());
    _title = TextEditingController();
    _description = TextEditingController();
    _distance = TextEditingController(text: '0');
    _duration = TextEditingController(text: '0:00');
    _load(context);
  }

  DateTime _fromDateTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  _selectDate(BuildContext ctx) async {
    final date = await showDatePicker(
        context: ctx,
        initialDate: _dateTime,
        firstDate: _dateTime.add(Duration(days: -365 * 100)),
        lastDate: _dateTime);
    if (date != null) {
      print('New date: $_dateTime $date');
      setState(() {
        _dateTime = _fromDateTime(date, TimeOfDay.fromDateTime(_dateTime));
      });
    }
  }

  _selectTime(BuildContext ctx) async {
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time != null) {
      setState(() {
        _dateTime = _fromDateTime(_dateTime, time);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyText1;
    Widget body = Container();
    if (_profiles != null) {
      final dropDown = DropdownButtonFormField<Profile>(
          value: _profile,
          items: _profiles.map((e) {
            return DropdownMenuItem(value: e, child: profileInfo(e, textStyle));
          }).toList(),
          onChanged: (p) => setState(() => _profile = p));
      final items = <Widget>[
        dropDown,
        TextFormField(
          controller: _duration,
          style: sensorTextStyle(context, 20),
          maxLines: 1,
          decoration: InputDecoration(labelText: 'Duration:'),
          validator: (value) => _validateDuration(value),
        ),
        TextFormField(
          controller: _distance,
          style: sensorTextStyle(context, 20),
          maxLines: 1,
          keyboardType: TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(labelText: 'Distance (in km):'),
          validator: (value) => _validateDistance(value),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
                child: Text(
              '${dateTimeFormat().format(_dateTime)}',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.button,
            )),
            IconButton(
                icon: Icon(Icons.calendar_today),
                onPressed: () => _selectDate(context)),
            IconButton(
                icon: Icon(Icons.access_time),
                onPressed: () => _selectTime(context))
          ],
        ),
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 1,
          decoration: InputDecoration(labelText: 'Title:'),
        ),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          maxLines: null,
          decoration: InputDecoration(labelText: 'Description:'),
        ),
      ];
      body = Form(
          key: _formID,
          autovalidate: false,
          child: ListView(
            padding: EdgeInsets.only(bottom: 80.0),
            children: items
                .where((el) => el != null)
                .map((e) => Padding(
                      padding: EdgeInsets.all(8.0),
                      child: e,
                    ))
                .toList(),
          ));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('New Activity'),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.done),
        onPressed: () => _save(context),
      ),
      body: body,
    );
  }

  String _validateDuration(String value) {
    int val = parseDuration(value);
    if (val == null || val < 0) return 'Invalid value';
    if (val == 0) return 'Mandatory field';
    return null;
  }

  String _validateDistance(String value) {
    double val = double.tryParse(value);
    if (val == null || val < 0) {
      return 'Invalid value';
    }
    return null;
  }

  _save(BuildContext context) async {
    if (!_formID.currentState.validate()) return false;
    try {
      final id = await widget._provider.records.addManual(widget._provider,
          _profile.id, _dateTime, parseDuration(_duration.text),
          title: textFromCtrl(_title),
          description: textFromCtrl(_description),
          distance: double.parse(textFromCtrl(_distance)) * 1000);
      Navigator.pop(context, id);
    } catch (e) {
      print('Error addManual: e');
    }
  }
}
