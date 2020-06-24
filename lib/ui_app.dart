import 'package:android/data_provider.dart';
import 'package:android/ui_main.dart';
import 'package:flutter/material.dart';

class App extends StatefulWidget {
  void Function() backgroundMain;
  App(this.backgroundMain);

  @override
  State<StatefulWidget> createState() => _AppState();
}

class _AppState extends State<App> {
  DataProvider _provider;

  @override
  void initState() {
    super.initState();
    DataProvider.openProvider(widget.backgroundMain)
        .then((value) => setState(() => _provider = value));
  }

  @override
  Widget build(BuildContext context) {
    Widget body = Container();
    if (_provider != null) body = MainView(_provider);

    return MaterialApp(
      title: 'FitRecord',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        accentColor: Colors.blueAccent,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: body,
    );
  }
}
