import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class ReleaseFixture {
  final apkBytes = utf8.encode(
    'synthetic signed APK bytes; native validation is mocked',
  );
  late final hash = sha256.convert(apkBytes).toString();
  final tag = 'v1.3.0-ru.1';
  late final manifest = <String, dynamic>{
    'schemaVersion': 1,
    'packageName': AppUpdateService.packageName,
    'versionName': '1.3.0-ru.1',
    'versionCode': 11631,
    'abi': 'arm64-v8a',
    'flavor': 'full',
    'buildType': 'release',
    'assetName': AppUpdateService.apkName,
    'sha256': hash,
  };
  final requests = <Uri>[];
  Map<String, dynamic> asset(String name, List<int> bytes) => {
    'name': name,
    'state': 'uploaded',
    'size': bytes.length,
    'browser_download_url': AppUpdateService.assetUrl(tag, name).toString(),
    'digest': 'sha256:${sha256.convert(bytes)}',
  };

  http.Client client({
    int status = 200,
    void Function(Map<String, dynamic>)? editRelease,
    List<int>? payload,
    String? redirect,
  }) => MockClient((request) async {
    requests.add(request.url);
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    if (request.url == AppUpdateService.latestUrl) {
      final release = <String, dynamic>{
        'tag_name': tag,
        'draft': false,
        'prerelease': false,
        'published_at': '2026-10-21T12:00:00Z',
        'html_url':
            'https://github.com/${AppUpdateService.repository}/releases/tag/$tag',
        'body': 'Synthetic release notes',
        'assets': [
          asset(AppUpdateService.apkName, apkBytes),
          asset(AppUpdateService.manifestName, manifestBytes),
        ],
      };
      editRelease?.call(release);
      return http.Response(jsonEncode(release), status);
    }
    if (redirect != null) {
      return http.Response('', 302, headers: {'location': redirect});
    }
    if (request.url ==
        AppUpdateService.assetUrl(tag, AppUpdateService.manifestName)) {
      return http.Response.bytes(manifestBytes, 200);
    }
    if (request.url ==
        AppUpdateService.assetUrl(tag, AppUpdateService.apkName)) {
      return http.Response.bytes(payload ?? apkBytes, 200);
    }
    throw StateError('Unexpected URL: ${request.url}');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late String path;
  late List<MethodCall> native;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('hermes-update-test');
    path = directory.uri.resolve('update.apk').toFilePath();
    native = [];
    messenger.setMockMethodCallHandler(AppUpdateService.channel, (call) async {
      native.add(call);
      return call.method == 'prepareDownload' ? path : null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(AppUpdateService.channel, null);
    directory.deleteSync(recursive: true);
  });

  Matcher failure(AppUpdateError kind) =>
      isA<AppUpdateException>().having((e) => e.kind, 'kind', kind);

  test(
    'checks only fork latest and manifest, compares actual versionCode',
    () async {
      final fixture = ReleaseFixture();
      final service = AppUpdateService(client: fixture.client());
      addTearDown(service.close);
      final release = (await service.check())!;
      expect(release.versionName, '1.3.0-ru.1');
      expect(release.isNewerThan(11630), isTrue);
      expect(release.isNewerThan(11631), isFalse);
      expect(release.isNewerThan(20000), isFalse);
      expect(fixture.requests, [
        AppUpdateService.latestUrl,
        AppUpdateService.assetUrl(fixture.tag, AppUpdateService.manifestName),
      ]);
      expect(native, isEmpty);
    },
  );

  for (final status in [403, 429, 500]) {
    test('HTTP $status is explicit and never downloads', () async {
      final fixture = ReleaseFixture();
      final service = AppUpdateService(client: fixture.client(status: status));
      addTearDown(service.close);
      await expectLater(
        service.check(),
        throwsA(
          failure(
            status == 500 ? AppUpdateError.network : AppUpdateError.rateLimit,
          ),
        ),
      );
      expect(fixture.requests, [AppUpdateService.latestUrl]);
    });
  }

  test('404 means no published release; malformed JSON fails closed', () async {
    final noRelease = AppUpdateService(
      client: ReleaseFixture().client(status: 404),
    );
    addTearDown(noRelease.close);
    expect(await noRelease.check(), isNull);
    final invalid = AppUpdateService(
      client: MockClient((_) async => http.Response('not JSON', 200)),
    );
    addTearDown(invalid.close);
    await expectLater(
      invalid.check(),
      throwsA(failure(AppUpdateError.invalidRelease)),
    );
  });

  for (final field in [
    'packageName',
    'abi',
    'flavor',
    'buildType',
    'versionName',
    'versionCode',
    'assetName',
    'sha256',
  ]) {
    test('rejects wrong manifest $field', () async {
      final fixture = ReleaseFixture();
      fixture.manifest[field] = field == 'versionCode' ? 0 : 'wrong';
      final service = AppUpdateService(client: fixture.client());
      addTearDown(service.close);
      await expectLater(
        service.check(),
        throwsA(failure(AppUpdateError.invalidRelease)),
      );
    });
  }

  for (final mutation in [
    'draft',
    'prerelease',
    'foreignUrl',
    'duplicate',
    'noDigest',
    'wrongTag',
    'oversize',
    'missingApk',
  ]) {
    test('rejects release $mutation', () async {
      final fixture = ReleaseFixture();
      final service = AppUpdateService(
        client: fixture.client(
          editRelease: (r) {
            final assets = r['assets'] as List<Map<String, dynamic>>;
            switch (mutation) {
              case 'draft':
                r['draft'] = true;
              case 'prerelease':
                r['prerelease'] = true;
              case 'foreignUrl':
                assets.first['browser_download_url'] =
                    'https://github.com/xP3ta/hermes-console/releases/download/${fixture.tag}/${AppUpdateService.apkName}';
              case 'duplicate':
                assets.add(assets.first);
              case 'noDigest':
                assets.first.remove('digest');
              case 'wrongTag':
                r['tag_name'] = 'v1.3.0';
              case 'oversize':
                assets.first['size'] = AppUpdateService.maxApkBytes + 1;
              case 'missingApk':
                assets.removeAt(0);
            }
          },
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.check(),
        throwsA(failure(AppUpdateError.invalidRelease)),
      );
    });
  }

  test(
    'rejects arbitrary redirects and permits only HTTPS GitHub asset CDN',
    () async {
      for (final url in [
        'https://evil.example/a.apk',
        'http://release-assets.githubusercontent.com/a',
        'https://release-assets.githubusercontent.com.evil.example/a',
        'https://user@release-assets.githubusercontent.com/a',
        'https://release-assets.githubusercontent.com:444/a',
      ]) {
        expect(AppUpdateService.allowedRedirect(Uri.parse(url)), isFalse);
      }
      expect(
        AppUpdateService.allowedRedirect(
          Uri.parse(
            'https://release-assets.githubusercontent.com/github-production-release-asset/1/2?token=synthetic',
          ),
        ),
        isTrue,
      );
      final fixture = ReleaseFixture();
      final service = AppUpdateService(
        client: fixture.client(redirect: 'https://evil.example/a.apk'),
      );
      addTearDown(service.close);
      await expectLater(
        service.check(),
        throwsA(failure(AppUpdateError.invalidRelease)),
      );
      expect(fixture.requests.any((u) => u.host == 'evil.example'), isFalse);
    },
  );

  test(
    'verified download reports progress and validates natively without installing',
    () async {
      final fixture = ReleaseFixture();
      final service = AppUpdateService(client: fixture.client());
      addTearDown(service.close);
      final release = (await service.check())!;
      final progress = <double>[];
      await service.download(release, progress.add);
      expect(progress.last, 1);
      expect(File(path).readAsBytesSync(), fixture.apkBytes);
      expect(native.map((c) => c.method), ['prepareDownload', 'validate']);
      expect(native.last.arguments, {
        'versionName': '1.3.0-ru.1',
        'versionCode': 11631,
        'sha256': fixture.hash,
      });
    },
  );

  test('manifest bytes must match their own GitHub digest', () async {
    final fixture = ReleaseFixture();
    final service = AppUpdateService(
      client: fixture.client(
        editRelease: (r) {
          final assets = r['assets'] as List<Map<String, dynamic>>;
          assets.last['digest'] = 'sha256:${'0' * 64}';
        },
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.check(),
      throwsA(failure(AppUpdateError.integrity)),
    );
    expect(native, isEmpty);
  });

  test(
    'follows the official asset CDN redirect and still checks the digest',
    () async {
      final fixture = ReleaseFixture();
      final base = fixture.client();
      addTearDown(base.close);
      final cdn = Uri.parse(
        'https://release-assets.githubusercontent.com/github-production-release-asset/123/fixture',
      );
      final client = MockClient((request) async {
        expect(request.headers.keys, isNot(contains('Authorization')));
        if (request.url ==
            AppUpdateService.assetUrl(
              fixture.tag,
              AppUpdateService.manifestName,
            )) {
          return http.Response('', 302, headers: {'location': cdn.toString()});
        }
        if (request.url == cdn) {
          return http.Response(jsonEncode(fixture.manifest), 200);
        }
        return base.get(request.url);
      });
      final service = AppUpdateService(client: client);
      addTearDown(service.close);
      expect((await service.check())?.versionCode, 11631);
    },
  );

  test(
    'download refuses an arbitrary initial URL even with a plausible hash',
    () async {
      final fixture = ReleaseFixture();
      final service = AppUpdateService(client: fixture.client());
      addTearDown(service.close);
      final release = AppUpdateRelease(
        versionName: '1.3.0-ru.1',
        versionCode: 11631,
        notes: '',
        apkUrl: Uri.parse('https://evil.example/update.apk'),
        sha256Hex: fixture.hash,
        size: fixture.apkBytes.length,
      );
      await expectLater(
        service.download(release, (_) {}),
        throwsA(failure(AppUpdateError.invalidRelease)),
      );
      expect(fixture.requests, isEmpty);
      expect(File(path).existsSync(), isFalse);
    },
  );

  for (final tamper in ['truncated', 'sameLength', 'oversized']) {
    test(
      'rejects wrong payload length or digest and deletes partial APK',
      () async {
        final fixture = ReleaseFixture();
        final payload = switch (tamper) {
          'truncated' => fixture.apkBytes.sublist(1),
          'sameLength' => [
            fixture.apkBytes.first ^ 1,
            ...fixture.apkBytes.skip(1),
          ],
          _ => [...fixture.apkBytes, 0],
        };
        final service = AppUpdateService(
          client: fixture.client(payload: payload),
        );
        addTearDown(service.close);
        final release = (await service.check())!;
        await expectLater(
          service.download(release, (_) {}),
          throwsA(failure(AppUpdateError.integrity)),
        );
        expect(File(path).existsSync(), isFalse);
        expect(
          native.any((c) => c.method == 'validate' || c.method == 'install'),
          isFalse,
        );
      },
    );
  }

  test(
    'native identity validation failure deletes even a hash-matching APK',
    () async {
      messenger.setMockMethodCallHandler(AppUpdateService.channel, (
        call,
      ) async {
        if (call.method == 'prepareDownload') return path;
        throw PlatformException(code: 'invalid_apk');
      });
      final service = AppUpdateService(client: ReleaseFixture().client());
      addTearDown(service.close);
      final release = (await service.check())!;
      await expectLater(
        service.download(release, (_) {}),
        throwsA(failure(AppUpdateError.integrity)),
      );
      expect(File(path).existsSync(), isFalse);
    },
  );

  test('closed operation fails without a request', () async {
    final fixture = ReleaseFixture();
    final service = AppUpdateService(client: fixture.client())..close();
    await expectLater(
      service.check(),
      throwsA(failure(AppUpdateError.network)),
    );
    expect(fixture.requests, isEmpty);
  });
}
