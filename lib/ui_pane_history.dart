import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/data_storage.dart';
import 'package:android/ui_main.dart';
import 'package:android/ui_utils.dart';
import 'package:flutter/cupertino.dart';
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
  final titleEditor = TextEditingController();
  final descritptionEditor = TextEditingController();
  TabController lapTabs;

  int _lapsCount(Record record) => (record?.laps?.length ?? 0) + 1;

  Future _load(BuildContext ctx) async {
    try {
      final item = await widget.provider.records
          .loadOne(widget.provider.indicators, widget.record.id);
      setState(() {
        _record = item;
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
    final _textFromCtrl = (TextEditingController ctrl) {
      final result = ctrl.text?.trim();
      if (result.isEmpty) return null;
      return result;
    };
    item.title = _textFromCtrl(titleEditor);
    item.description = _textFromCtrl(descritptionEditor);
    try {
      await widget.provider.records.updateFields(item);
      Navigator.pop(ctx, true);
    } catch (e) {
      print('Failed to update: $e');
      showMessage(ctx, 'Something is not good');
    }
  }

  Widget _buildOverview(BuildContext ctx, Record item, int endIndex) {
    final page = [
      [
        {'id': endIndex != null ? 'time_lap' : 'time_total'},
        {'id': endIndex != null ? 'loc_lap_distance' : 'loc_total_distance'},
      ],
      [
        {'id': endIndex != null ? 'loc_lap_speed_ms' : 'loc_total_speed_ms'},
        {'id': endIndex != null ? 'loc_lap_pace_sm' : 'loc_total_pace_sm'},
      ]
    ];
    return renderSensors(
        ctx,
        widget.provider.indicators,
        endIndex != null ? item.trackpoints[endIndex] : item.trackpoints.last,
        page,
        'Overview:');
  }

  Widget _buildHrm(BuildContext ctx, Record item, int endIndex) {
    final scope = endIndex != null ? 'lap' : 'total';
    final page = [
      [
        {'id': 'sensor_hrm_${scope}_avg'},
      ],
      [
        {'id': 'sensor_hrm_${scope}_min'},
        {'id': 'sensor_hrm_${scope}_max'},
      ]
    ];
    return renderSensors(
        ctx,
        widget.provider.indicators,
        endIndex != null ? item.trackpoints[endIndex] : item.trackpoints.last,
        page,
        'Heart rate:');
  }

  Widget _buildPower(BuildContext ctx, Record item, int endIndex) {
    final scope = endIndex != null ? 'lap' : 'total';
    final page = [
      [
        {'id': 'sensor_power_${scope}_avg'},
      ],
      [
        {'id': 'sensor_power_${scope}_min'},
        {'id': 'sensor_power_${scope}_max'},
      ]
    ];
    return renderSensors(
        ctx,
        widget.provider.indicators,
        endIndex != null ? item.trackpoints[endIndex] : item.trackpoints.last,
        page,
        'Power:');
  }

  Widget _buildTab(BuildContext ctx, int index, Record record) {
    final listItems = <Widget>[];
    int endIndex;
    if (index == null) {
      listItems.add(_buildEditForm(context, record));
      listItems.add(_buildOverview(context, record, null));
    } else {
      endIndex = index < record.laps.length
          ? record.laps[index]
          : record.trackpoints.length - 1;
      listItems.add(_buildOverview(context, record, endIndex));
    }
    if (record.trackpoints.last.containsKey('sensor_hrm')) {
      listItems.add(_buildHrm(ctx, record, endIndex));
    }
    if (record.trackpoints.last.containsKey('sensor_power')) {
      listItems.add(_buildPower(ctx, record, endIndex));
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
