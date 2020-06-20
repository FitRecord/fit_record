import 'package:android/data_provider.dart';
import 'package:android/ui_pane_history.dart';
import 'package:android/ui_pane_profiles.dart';
import 'package:android/ui_pane_record.dart';
import 'package:android/ui_utils.dart';
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
  @override
  State<StatefulWidget> createState() => MainViewState();
}

class MainViewState extends State<MainView> {
  DataProvider _dataProvider;
  int _selectedView = 0;

  _init() async {
    try {
      final provider = await openProvider();
      setState(() {
        _dataProvider = provider;
      });
    } catch (e) {
      print('Failed to init: $e');
      showMessage(context, "Something is not good");
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  _selectView(int index) {
    setState(() {
      _selectedView = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dataProvider == null) {
      return Scaffold(
        appBar: AppBar(),
      );
    }
    final items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(icon: Icon(Icons.timer), title: Text('Record')),
      BottomNavigationBarItem(
          icon: Icon(Icons.history), title: Text('History')),
      BottomNavigationBarItem(
          icon: Icon(Icons.directions_run), title: Text('Profiles')),
    ];
    final bottom = BottomNavigationBar(
      currentIndex: _selectedView,
      items: items,
      onTap: _selectView,
    );
    switch (_selectedView) {
      case 0:
        return MainPane(_dataProvider, bottom, () => RecordPane());
      case 1:
        return MainPane(_dataProvider, bottom, () => HistoryPane());
      case 2:
        return MainPane(_dataProvider, bottom, () => ProfilesPane());
    }
    return null;
  }
}
