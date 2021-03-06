import 'dart:collection';

import 'package:android/data_provider.dart';
import 'package:android/data_storage_profiles.dart';
import 'package:android/data_storage_records.dart';
import 'package:android/data_sync_impl.dart';
import 'package:flutter/services.dart';

class OAuthCallback {
  final String service;
  final int challenge;
  final Uri uri;

  OAuthCallback(this.service, this.challenge, this.uri);
}

class SyncManager {
  final _syncChannel = MethodChannel('org.fitrecord/sync');
  final ProfileStorage _profileStorage;
  final providers = LinkedHashMap.fromIterables(
    ['strava', 'dropbox'],
    <SyncProvider>[StravaProvider(), DropboxProvider()],
  );

  SyncManager(this._profileStorage) {
    _syncChannel.setMethodCallHandler((call) async {
      switch (call.method) {
      }
    });
  }

  SyncConfig newConfig(String name) {
    final provider = providers[name];
    return SyncConfig(null, name, provider.name(), 0, 0, null, null);
  }

  Future<Map<String, dynamic>> _secrets(String service) =>
      _syncChannel.invokeMapMethod<String, dynamic>('getSecrets', service);

  Future<Uri> buildOauthUri(String service) async {
    final provider = providers[service];
    final challenge = DateTime.now().millisecondsSinceEpoch;
    final secrets = await _secrets(service);
    return provider.buildOauthUri(secrets, challenge);
  }

  completeOauth(SyncConfig config, Map data) async {
    final query = data['query'];
    if (query == null || query['error'] != null)
      throw ArgumentError('Invalid query');
    final provider = providers[config.service];
    final secrets = await _secrets(config.service);
    final tokenData = await provider.completeOauth(secrets, query);
    config.secretsJson = tokenData;
  }

  bool authorized(SyncConfig config) {
    final provider = providers[config.service];
    if (provider.oauth() && config.secretsJson != null) return true;
    return false;
  }

  save(SyncConfig config) async {
    return _profileStorage.saveSyncConfig(config);
  }

  Future<List<SyncConfig>> all() async {
    final list = await _profileStorage.allSyncConfigs();
    return list
        .where((element) => providers.containsKey(element.service))
        .map((e) {
      e.provider = providers[e.service];
      return e;
    }).toList();
  }

  Future<T> _httpAuthenticated<T>(SyncProvider provider, SyncConfig config,
      Future<T> Function() callback) async {
    try {
      return await callback();
    } on HttpException catch (e) {
//      print('Http error in _httpAuthenticated: $e, ${config.secretsJson}');
      if (e.code == 401) {
        // Try to fix
        final secrets = await _secrets(config.service);
        final fixed = await provider.fix401(secrets, config);
        print('Fix 401 result: $fixed');
        if (fixed == true) {
          await _profileStorage.updateSyncSecrets(config);
          return await callback();
        }
      }
      rethrow;
    }
  }

  Future upload(DataProvider dataProvider, Record record, Profile profile,
      SyncConfig config) async {
    final provider = providers[config.service];
    dynamic id = await _httpAuthenticated(
        provider, config, () => provider.getActivityID(config, record));
    if (id == null) {
      // Upload
      final exporter = dataProvider.export.exporter('tcx');
      final stream =
          await dataProvider.export.export(exporter, dataProvider, record);
      id = await _httpAuthenticated(provider, config,
          () => provider.uploadActivity(config, record, profile, stream));
    } else {
      await _httpAuthenticated(provider, config,
          () => provider.updateActivity(config, record, profile, id));
    }
    await dataProvider.records.updateSync(record, config.id, id);
    print('Upload: $id, ${record.syncJson}');
  }

  Future delete(SyncConfig config) {
    return _profileStorage.deleteSyncConfig(config);
  }
}
