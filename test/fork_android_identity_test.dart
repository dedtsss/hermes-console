import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fork has a side-by-side Android identity and preserves pairing links', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final qaManifest = File('android/app/src/qa/AndroidManifest.xml')
        .readAsStringSync();
    final strings = File('android/app/src/main/res/values/strings.xml')
        .readAsStringSync();
    final russianStrings = File('android/app/src/main/res/values-ru/strings.xml')
        .readAsStringSync();
    final pairing = File('lib/core/services/pairing_link.dart').readAsStringSync();

    expect(gradle, contains('applicationId = "io.github.dedtsss.hermesconsole"'));
    expect(gradle, contains('applicationIdSuffix = ".qa"'));
    expect(
      gradle,
      isNot(contains('applicationId = "dev.xpetalab.hermesconsole"')),
    );
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(qaManifest, contains('android:label="@string/app_name_qa"'));
    expect(strings, contains('<string name="app_name">Hermes Console RU</string>'));
    expect(russianStrings, contains('<string name="app_name">Hermes Console RU</string>'));
    expect(manifest, contains('<data android:scheme="hermes" android:host="pair"/>'));
    expect(pairing, contains("static const scheme = 'hermes'"));
    expect(pairing, contains("static const authority = 'pair'"));
  });
}
