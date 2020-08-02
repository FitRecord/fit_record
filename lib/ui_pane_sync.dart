import 'package:android/data_storage_profiles.dart';
import 'package:android/data_sync.dart';
import 'package:android/data_sync_impl.dart';
import 'package:android/ui_main.dart';
import 'package:android/ui_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';

class SyncPane extends MainPaneState {
  List<SyncConfig> configs;

  _load() async {
    try {
      final list = await widget.provider.sync.all();
      setState(() => configs = list);
    } catch (e) {
      print('_load error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  _addNewConfig(BuildContext ctx, String provider) async {
    await _SyncConfigEditor.open(
        ctx, widget.provider.sync, widget.provider.sync.newConfig(provider));
    return _load();
  }

  _editConfig(BuildContext ctx, SyncConfig config) async {
    await _SyncConfigEditor.open(ctx, widget.provider.sync, config);
    return _load();
  }

  _showProviderSelector(BuildContext ctx) {
    return showModalBottomSheet(
        context: ctx,
        useRootNavigator: true,
        isScrollControlled: false,
        builder: (ctx) => ListView(
              reverse: true,
              children: widget.provider.sync.providers.keys.map((e) {
                final provider = widget.provider.sync.providers[e];
                return ListTile(
                  leading: Icon(provider.icon()),
                  title: Text(provider.name()),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addNewConfig(ctx, e);
                  },
                );
              }).toList(),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final addButton = RaisedButton(
      onPressed: () => _showProviderSelector(context),
      child: Text('New configuration'),
    );
    var list = ListView();
    if (configs != null)
      list = ListView(
        children: configs?.map((e) => _buildItem(context, e))?.toList(),
      );
    return Scaffold(
      appBar: AppBar(
        title: Text('Synchronization'),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: list), addButton],
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }

  Widget _buildItem(BuildContext ctx, SyncConfig e) {
    final provider = widget.provider.sync.providers[e.service];
    return ListTile(
      onTap: () => _editConfig(ctx, e),
      leading: Icon(provider.icon()),
      title: Text(e.title),
//      trailing: IconButton(icon: Icon(Icons.sync), onPressed: () => null),
    );
  }
}

class _SyncConfigEditor extends StatefulWidget {
  final SyncManager _manager;
  SyncProvider _provider;
  final SyncConfig _config;

  _SyncConfigEditor(this._manager, this._config) {
    _provider = _manager.providers[_config.service];
  }

  @override
  State<StatefulWidget> createState() => _SyncConfigEditorState();

  static Future open(
      BuildContext ctx, SyncManager manager, SyncConfig config) async {
    return Navigator.push(
      ctx,
      MaterialPageRoute(
          builder: (ctx) => _SyncConfigEditor(manager, config),
          fullscreenDialog: true),
    );
  }
}

class _SyncConfigEditorState extends State<_SyncConfigEditor> {
  final titleCtrl = TextEditingController();
  int _challenge;

  @override
  void dispose() {
    super.dispose();
    widget._manager.oauthCallbackReceived.removeListener(_onOauthCallback);
  }

  @override
  void initState() {
    super.initState();
    titleCtrl.text = widget._config.title;
    widget._manager.oauthCallbackReceived.addListener(_onOauthCallback);
  }

  _onOauthCallback() async {
    final callback = widget._manager.oauthCallbackReceived.value;
    if (callback?.service == widget._config.service &&
        callback?.challenge == _challenge) {
      // Complete OAuth flow
      try {
        await widget._manager.completeOauth(widget._config, callback?.uri);
      } catch (e) {
        print('_onOauthCallback error: $e');
        showMessage(context, 'Something is not good');
        rethrow;
      }
    }
  }

  _save(BuildContext ctx) async {
    if (!widget._manager.authorized(widget._config)) {
      showMessage(ctx, 'Please authorize the Application');
    }
    try {
      widget._config.title = titleCtrl.text.trim();
      await widget._manager.save(widget._config);
      Navigator.pop(ctx);
    } catch (e) {
      print('Save error: $e');
      showMessage(ctx, 'Something is not good');
    }
  }

  _startOAuth(BuildContext ctx) async {
    try {
      _challenge = await widget._manager.startOauth(widget._config.service);
    } catch (e) {
      print('_startOAuth error: $e');
    }
  }

  _delete(BuildContext ctx) async {
    final yes = await yesNoDialog(ctx, 'Delete the Configuration?');
    if (!yes) return;
    try {
      await widget._manager.delete(widget._config);
      Navigator.pop(ctx);
    } catch (e) {
      print('Delete error: $e');
      showMessage(ctx, 'Something is not good');
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget._config.id == null
        ? 'New configuration'
        : 'Update configuration';
    final items = <Widget>[];
    items.add(TextFormField(
      controller: titleCtrl,
      decoration: InputDecoration(labelText: 'Title'),
    ));
    items.add(dropdownFormItem(
        'Direction',
        [0, 1, 2],
        ['Two-way', 'Upload only', 'Download only'],
        widget._config.direction,
        (value) => setState(() => widget._config.direction = value)));
    items.add(dropdownFormItem(
        'Mode',
        [0, 1, 2],
        ['Manual', 'Wi-Fi only', 'Automatic'],
        widget._config.mode,
        (value) => setState(() => widget._config.mode = value)));
    if (widget._provider.oauth()) {
      items.add(RaisedButton(
        onPressed: () => _startOAuth(context),
        child: Text('Authorize'),
      ));
    }
    final actions = <Widget>[];
    if (widget._config.id != null) {
      actions.add(IconButton(
        icon: Icon(Icons.delete),
        onPressed: () => _delete(context),
      ));
    }
    return Scaffold(
      appBar: AppBar(
        title: iconWithText(Icon(widget._provider.icon()), title),
        actions: actions,
      ),
      body: formWithItems(context, items),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _save(context),
        child: Icon(Icons.done),
      ),
    );
  }
}
