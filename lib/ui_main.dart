import 'package:android/data_provider.dart';
import 'package:android/ui_pane_history.dart';
import 'package:android/ui_pane_profiles.dart';
import 'package:android/ui_pane_record.dart';
import 'package:android/ui_pane_sync.dart';
import 'package:flutter/material.dart';

class MainPane<T extends MainPaneState> extends StatefulWidget {
  final DataProvider provider;
  final BottomNavigationBar bottomNavigationBar;
  final T Function() _createState;

  const MainPane(this.provider, this.bottomNavigationBar, this._createState);

  @override
  State<StatefulWidget> createState() => _createState();
}

abstract class MainPaneState extends State<MainPane> {}

class MainView extends StatefulWidget {
  DataProvider _dataProvider;
  MainView(this._dataProvider);

  @override
  State<StatefulWidget> createState() => MainViewState();
}

class MainViewState extends State<MainView> {
  int _selectedView = 0;

  @override
  void initState() {
    super.initState();
  }

  _selectView(int index) {
    setState(() {
      _selectedView = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(icon: Icon(Icons.timer), title: Text('Record')),
      BottomNavigationBarItem(
          icon: Icon(Icons.history), title: Text('History')),
      BottomNavigationBarItem(
          icon: Icon(Icons.directions_run), title: Text('Profiles')),
      BottomNavigationBarItem(icon: Icon(Icons.sync), title: Text('Sync')),
    ];
    final bottom = BottomNavigationBar(
      currentIndex: _selectedView,
      items: items,
      onTap: _selectView,
      type: BottomNavigationBarType.fixed,
    );
    switch (_selectedView) {
      case 0:
        return MainPane(widget._dataProvider, bottom, () => RecordPane());
      case 1:
        return MainPane(widget._dataProvider, bottom, () => HistoryPane());
      case 2:
        return MainPane(widget._dataProvider, bottom, () => ProfilesPane());
      case 3:
        return MainPane(widget._dataProvider, bottom, () => SyncPane());
    }
    return null;
  }
}
