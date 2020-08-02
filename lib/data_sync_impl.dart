import 'dart:convert';
import 'dart:io';

import 'package:android/data_storage_profiles.dart';
import 'package:android/data_storage_records.dart';
import 'package:android/icons_sync_logo.dart';
import 'package:android/ui_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class HttpException implements Exception {
  final int code;
  final String message;

  HttpException(this.code, this.message);

  @override
  String toString() => 'HTTP error [$code]: $message';
}

bool _dateTimesAreClose(int dt1, int dt2, int tolerance) =>
    (dt1 - dt2).abs() < tolerance;

abstract class SyncProvider {
  final client = http.Client();

  IconData icon();
  String name();
  bool oauth();
  Uri buildOauthUri(Map<String, dynamic> secrets, int challenge) => null;
  Future<Map<String, dynamic>> completeOauth(
          Map<String, dynamic> secrets, Uri uri) =>
      null;

  String _token(Map<String, dynamic> secrets) =>
      secrets != null ? secrets['access_token'] : null;

  Uri _refreshTokenUri() => null;

  Future<T> _httpAuthenticated<T>(
    SyncConfig config,
    dynamic url,
    dynamic body, {
    bool rawBody = false,
    http.BaseRequest request,
  }) async {
    return _jsonHttp(url, body,
        rawBody: rawBody,
        bearerToken: _token(config.secretsJson),
        request: request);
  }

  Future<T> _jsonHttp<T>(
    dynamic url,
    dynamic body, {
    String method,
    String bearerToken,
    bool rawBody = false,
    http.BaseRequest request,
  }) async {
    final headers = Map<String, String>();
    if (bearerToken != null) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }
    if (request == null) if (body != null) {
      request = http.Request('post', url);
      if (rawBody) {
        (request as http.Request).bodyFields = body as Map<String, String>;
      } else {
        (request as http.Request).body = jsonEncode(body);
      }
    } else
      request = http.Request('get', url);
    request.headers.addAll(headers);
    final response = await request.send();
    if (response.statusCode < 400) {
      final str = await response.stream.bytesToString();
      if (response.headers['content-type']?.startsWith('application/json') ==
          true) {
//        print('JSON: $str');
        return jsonDecode(str);
      }
      return str as T;
    }
    final str = await response.stream.bytesToString();
    print(
        'HTTP error: ${response.statusCode} - ${response.reasonPhrase}, $url, $str');
    throw HttpException(response.statusCode, response.reasonPhrase);
  }

  Future<Map<String, dynamic>> _oauthTokenExchange(
      Uri uri, String client_id, String client_secret,
      {String code, String token, Map<String, String> extra}) async {
    Map body;
    if (code != null) {
      body = <String, String>{
        'client_id': client_id,
        'client_secret': client_secret,
        'code': code,
        'grant_type': 'authorization_code'
      };
    } else {
      body = <String, String>{
        'client_id': client_id,
        'client_secret': client_secret,
        'grant_type': 'refresh_token',
        'refresh_token': token
      };
    }
    try {
      if (extra != null) body.addAll(extra);
//      print('_oauthTokenExchange $body $uri');
      return _jsonHttp(uri, body, rawBody: true);
    } on HttpException catch (e) {
      if (e.code == 401) throw Exception('Invalid token exchange');
      throw e;
    }
  }

  Future<bool> fix401(Map<String, dynamic> secrets, SyncConfig config) async {
    if (oauth()) {
      final tokenUri = _refreshTokenUri();
      if (config.secretsJson == null) return false;
      final newSecrets = await _oauthTokenExchange(
        tokenUri,
        secrets['client_id'],
        secrets['client_secret'],
        token: config.secretsJson['refresh_token'],
      );
      config.secretsJson = newSecrets;
      return true;
    }
    return false;
  }

  Future<dynamic> getActivityID(SyncConfig config, Record record);

  Future uploadActivity(
      SyncConfig config, Record record, Profile profile, dynamic data);
}

class StravaProvider extends SyncProvider {
  final String _HOST = 'www.strava.com';

  @override
  IconData icon() => SyncLogo.strava;

  @override
  String name() => 'Strava';

  @override
  bool oauth() => true;

  @override
  Uri buildOauthUri(Map<String, dynamic> secrets, int challenge) {
    final callback = '${secrets['callback_uri']}/${challenge}';
    final uri = Uri(
      scheme: 'https',
      host: _HOST,
      path: '/oauth/mobile/authorize',
      queryParameters: {
        'client_id': secrets['client_id'],
        'redirect_uri': callback,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'activity:read_all,activity:write'
      },
    );
    return uri;
  }

  @override
  Future<Map<String, dynamic>> completeOauth(
      Map<String, dynamic> secrets, Uri uri) {
    final tokenUri =
        Uri(scheme: 'https', host: _HOST, path: '/api/v3/oauth/token');
    return _oauthTokenExchange(
      tokenUri,
      secrets['client_id'],
      secrets['client_secret'],
      code: uri.queryParameters['code'],
    );
  }

  @override
  Uri _refreshTokenUri() =>
      Uri(scheme: 'https', host: _HOST, path: '/api/v3/oauth/token');

  Future<List<Map<String, dynamic>>> _listActivities(SyncConfig config,
      {int from, int to}) async {
    final result = <Map<String, dynamic>>[];
    var page = 1;
    var size = 0;
    do {
      final query = <String, dynamic>{'page': page.toString()};
      if (from != null) query['after'] = (from / 1000).round().toString();
      if (to != null) query['before'] = (to / 1000).round().toString();
      final uri = Uri(
          scheme: 'https',
          host: _HOST,
          path: '/api/v3/athlete/activities',
          queryParameters: query);
      final data = await _httpAuthenticated<List>(config, uri, null);
      data.forEach((item) {
        result.add({
          'id': item['id'],
          'start_date':
              DateTime.parse(item['start_date']).millisecondsSinceEpoch,
        });
      });
      page += 1;
      size = data.length;
    } while (size > 0);
    return result;
  }

  @override
  Future<dynamic> getActivityID(SyncConfig config, Record record) async {
    final list = await _listActivities(config,
        from: record.started - 15000, to: record.started + 15000);
    final data = list.firstWhere(
        (data) => _dateTimesAreClose(data['start_date'], record.started, 10000),
        orElse: () => null);
    if (data != null) return data['id'];
    return null;
  }

  @override
  Future uploadActivity(
      SyncConfig config, Record record, Profile profile, data) async {
    final stream = data as Stream<String>;
    final request = http.MultipartRequest(
        'post', Uri(scheme: 'https', host: _HOST, path: '/api/v3/uploads'));
    request.fields['data_type'] = 'tcx';
    request.fields['external_id'] = record.uid;
    if (textIsNotEmpty(record.title)) request.fields['name'] = record.title;
    if (textIsNotEmpty(record.description))
      request.fields['description'] = record.description;
    final bytes =
        await http.ByteStream(stream.transform(utf8.encoder)).toBytes();
    print('File to upload: ${bytes.length}');
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: '${record.uid}.tcx',
    ));
    dynamic output =
        await _httpAuthenticated(config, null, null, request: request);
    final uploadID = output['id_str'];
//    print('Upload result: $output');
    final checkUri =
        Uri(scheme: 'https', host: _HOST, path: '/api/v3/uploads/$uploadID');
    while (output['activity_id'] == null && output['error'] == null) {
      sleep(Duration(seconds: 1));
      output = await _httpAuthenticated(config, checkUri, null);
    }
    if (output['error'] != null) throw Exception(output['error']);
    return output['activity_id'];
  }
}

class DropboxProvider extends SyncProvider {
  final String _HOST = 'api.dropboxapi.com';

  @override
  IconData icon() => SyncLogo.dropbox;

  @override
  String name() => 'Dropbox';

  @override
  bool oauth() => true;

  @override
  Uri buildOauthUri(Map<String, dynamic> secrets, int challenge) {
    final uri = Uri(
      scheme: 'https',
      host: 'www.dropbox.com',
      path: '/oauth2/authorize',
      queryParameters: {
        'state': challenge.toString(),
        'client_id': secrets['client_id'],
        'redirect_uri': secrets['callback_uri'],
        'response_type': 'code',
        'token_access_type': 'offline',
      },
    );
    return uri;
  }

  @override
  Future<Map<String, dynamic>> completeOauth(
      Map<String, dynamic> secrets, Uri uri) {
    final tokenUri = Uri(scheme: 'https', host: _HOST, path: '/oauth2/token');
//    print('completeOauth $tokenUri, $uri');
    return _oauthTokenExchange(
      tokenUri,
      secrets['client_id'],
      secrets['client_secret'],
      code: uri.queryParameters['code'],
      extra: {'redirect_uri': secrets['callback_uri']},
    );
  }

  @override
  Future getActivityID(SyncConfig config, Record record) {
    // TODO: implement getActivityID
    throw UnimplementedError();
  }

  @override
  Future uploadActivity(
      SyncConfig config, Record record, Profile profile, data) {
    // TODO: implement uploadActivity
    throw UnimplementedError();
  }
}
