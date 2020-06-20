import 'package:android/data_provider.dart';
import 'package:flutter/material.dart';

import 'ui_app.dart';

void backgroundMain() {
  DataProvider.backgroundCallback();
}

void main() {
  DataProvider.initBackground(backgroundMain);
  runApp(App());
}
