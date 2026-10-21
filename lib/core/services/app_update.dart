import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

enum AppUpdateError {
  network,
  rateLimit,
  invalidRelease,
  integrity,
  unsupported,
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.kind);
  final AppUpdateError kind;
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.versionName,
    required this.versionCode,
    required this.notes,
    required this.apkUrl,
    required this.sha256Hex,
    required this.size,
  });

  final String versionName;
  final int versionCode;
  final String notes;
  final Uri apkUrl;
  final String sha256Hex;
  final int size;

  bool isNewerThan(int installedCode) => versionCode > installedCode;
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const packageName = 'io.github.dedtsss.hermesconsole';
  static const repository = 'dedtsss/hermes-console';
  static const apkName = 'hermes-console-ru-arm64-v8a-full-release.apk';
  static const manifestName = 'hermes-console-ru-update.json';
  static const channel = MethodChannel('hermes/app_update');
  static final latestUrl = Uri.https(
    'api.github.com',
    '/repos/$repository/releases/latest',
  );
  static const maxApkBytes = 512 * 1024 * 1024;
  final http.Client _client;
  bool _closed = false;

  static Uri assetUrl(String tag, String name) =>
      Uri.https('github.com', '/$repository/releases/download/$tag/$name');

  static bool allowedRedirect(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      !uri.hasFragment &&
      uri.host == 'release-assets.githubusercontent.com';

  static Map<String, dynamic> _object(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const AppUpdateException(AppUpdateError.invalidRelease);
    }
    return value;
  }

  static Map<String, dynamic> _asset(
    Map<String, dynamic> release,
    String tag,
    String name,
  ) {
    final assets = release['assets'];
    if (assets is! List) {
      throw const AppUpdateException(AppUpdateError.invalidRelease);
    }
    final matches = assets
        .whereType<Map<String, dynamic>>()
        .where((a) => a['name'] == name)
        .toList();
    if (matches.length != 1) {
      throw const AppUpdateException(AppUpdateError.invalidRelease);
    }
    final asset = matches.single;
    if (asset['state'] != 'uploaded' ||
        asset['browser_download_url'] != assetUrl(tag, name).toString() ||
        asset['size'] is! int ||
        (asset['size'] as int) <= 0 ||
        asset['digest'] is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(asset['digest'] as String)) {
      throw const AppUpdateException(AppUpdateError.invalidRelease);
    }
    return asset;
  }

  Future<AppUpdateRelease?> check() async {
    try {
      final response = await _request(latestUrl, redirects: false);
      if (response.statusCode == 404) return null;
      _status(response.statusCode);
      final release = _object(await _bytes(response, 1024 * 1024));
      final tag = release['tag_name'];
      if (release['draft'] != false ||
          release['prerelease'] != false ||
          release['published_at'] is! String ||
          tag is! String ||
          !RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+-ru\.[1-9][0-9]*$').hasMatch(tag) ||
          release['html_url'] !=
              'https://github.com/$repository/releases/tag/$tag') {
        throw const AppUpdateException(AppUpdateError.invalidRelease);
      }
      final apk = _asset(release, tag, apkName);
      final manifest = _asset(release, tag, manifestName);
      if ((apk['size'] as int) > maxApkBytes ||
          (manifest['size'] as int) > 16384) {
        throw const AppUpdateException(AppUpdateError.invalidRelease);
      }
      final manifestResponse = await _request(assetUrl(tag, manifestName));
      _status(manifestResponse.statusCode);
      final bytes = await _bytes(manifestResponse, 16384);
      if (bytes.length != manifest['size'] ||
          'sha256:${sha256.convert(bytes)}' != manifest['digest']) {
        throw const AppUpdateException(AppUpdateError.integrity);
      }
      final info = _object(bytes);
      if (info['schemaVersion'] != 1 ||
          info['packageName'] != packageName ||
          info['versionName'] != tag.substring(1) ||
          info['versionCode'] is! int ||
          (info['versionCode'] as int) <= 0 ||
          (info['versionCode'] as int) > 2100000000 ||
          info['abi'] != 'arm64-v8a' ||
          info['flavor'] != 'full' ||
          info['buildType'] != 'release' ||
          info['assetName'] != apkName ||
          'sha256:${info['sha256']}' != apk['digest']) {
        throw const AppUpdateException(AppUpdateError.invalidRelease);
      }
      return AppUpdateRelease(
        versionName: info['versionName'] as String,
        versionCode: info['versionCode'] as int,
        notes: (release['body'] is String ? release['body'] as String : '')
            .substring(
              0,
              (release['body'] is String
                      ? (release['body'] as String).length
                      : 0)
                  .clamp(0, 20000),
            ),
        apkUrl: assetUrl(tag, apkName),
        sha256Hex: info['sha256'] as String,
        size: apk['size'] as int,
      );
    } on AppUpdateException {
      rethrow;
    } on FormatException {
      throw const AppUpdateException(AppUpdateError.invalidRelease);
    } catch (_) {
      throw const AppUpdateException(AppUpdateError.network);
    }
  }

  Future<void> download(
    AppUpdateRelease release,
    void Function(double) progress,
  ) async {
    File? file;
    IOSink? sink;
    var complete = false;
    try {
      final path = await channel.invokeMethod<String>('prepareDownload');
      if (path == null) {
        throw const AppUpdateException(AppUpdateError.unsupported);
      }
      file = File(path);
      final response = await _request(release.apkUrl);
      _status(response.statusCode);
      if (response.contentLength != null &&
          response.contentLength != release.size) {
        throw const AppUpdateException(AppUpdateError.integrity);
      }
      sink = file.openWrite();
      var received = 0;
      final deadline = DateTime.now().add(const Duration(minutes: 15));
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_closed || DateTime.now().isAfter(deadline)) {
          throw const AppUpdateException(AppUpdateError.network);
        }
        received += chunk.length;
        if (received > release.size || received > maxApkBytes) {
          throw const AppUpdateException(AppUpdateError.integrity);
        }
        sink.add(chunk);
        // Backpressure bounds memory even when storage is slower than the network.
        await sink.flush();
        progress(received / release.size);
      }
      await sink.close();
      sink = null;
      if (received != release.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              release.sha256Hex) {
        throw const AppUpdateException(AppUpdateError.integrity);
      }
      await validate(release);
      complete = true;
    } on AppUpdateException {
      rethrow;
    } on PlatformException {
      throw const AppUpdateException(AppUpdateError.integrity);
    } catch (_) {
      throw const AppUpdateException(AppUpdateError.network);
    } finally {
      await sink?.close();
      if (!complete && file != null && await file.exists()) await file.delete();
    }
  }

  static Map<String, Object> _arguments(AppUpdateRelease release) => {
    'versionName': release.versionName,
    'versionCode': release.versionCode,
    'sha256': release.sha256Hex,
  };

  static Future<void> validate(AppUpdateRelease release) =>
      channel.invokeMethod<void>('validate', _arguments(release));

  static Future<String?> install(AppUpdateRelease release) =>
      channel.invokeMethod<String>('install', _arguments(release));

  Future<http.StreamedResponse> _request(
    Uri uri, {
    bool redirects = true,
  }) async {
    final allowedAsset =
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        RegExp(
          r'^/dedtsss/hermes-console/releases/download/v[0-9]+\.[0-9]+\.[0-9]+-ru\.[1-9][0-9]*/(hermes-console-ru-update\.json|hermes-console-ru-arm64-v8a-full-release\.apk)$',
        ).hasMatch(uri.path);
    if (uri != latestUrl && !allowedAsset) {
      throw const AppUpdateException(AppUpdateError.invalidRelease);
    }
    for (var hop = 0; hop < 4; hop++) {
      if (_closed) throw const AppUpdateException(AppUpdateError.network);
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['User-Agent'] = 'Hermes-Console-RU-updater';
      if (uri.host == 'api.github.com') {
        request.headers['Accept'] = 'application/vnd.github+json';
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (!redirects || location == null) {
        throw const AppUpdateException(AppUpdateError.invalidRelease);
      }
      final next = uri.resolve(location);
      if (!allowedRedirect(next)) {
        throw const AppUpdateException(AppUpdateError.invalidRelease);
      }
      await response.stream.listen(null).cancel();
      uri = next;
    }
    throw const AppUpdateException(AppUpdateError.invalidRelease);
  }

  static void _status(int status) {
    if (status == 403 || status == 429) {
      throw const AppUpdateException(AppUpdateError.rateLimit);
    }
    if (status != 200) throw const AppUpdateException(AppUpdateError.network);
  }

  static Future<List<int>> _bytes(
    http.StreamedResponse response,
    int limit,
  ) async {
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > limit) {
        throw const AppUpdateException(AppUpdateError.invalidRelease);
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
