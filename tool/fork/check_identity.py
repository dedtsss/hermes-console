#!/usr/bin/env python3
"""Lightweight invariant checks; never reads a keystore or signing secret."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'io.github.dedtsss.hermesconsole'


def check(root=ROOT):
    gradle = (root / 'android/app/build.gradle.kts').read_text()
    assert f'applicationId = "{PACKAGE}"' in gradle, 'existing RU application ID changed'
    assert 'namespace = "com.hermesagent.hermes_android"' in gradle
    assert 'applicationIdSuffix = ".qa"' in gradle
    assert 'keyAlias = keystoreProperties["keyAlias"] as String' in gradle
    assert 'signingConfig = signingConfigs.getByName("release")' in gradle
    assert 'Release signing is not configured' in gradle
    for path in (root / 'android/app').rglob('*'):
        if path.is_file() and path.suffix in {'.kt', '.kts', '.xml'}:
            assert 'dev.xpetalab.hermesconsole' not in path.read_text(), f'upstream identity leaked into {path}'
    manifest = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
    assert '<data android:scheme="hermes" android:host="pair"/>' in manifest
    assert 'android:label="@string/app_name"' in manifest
    pairing = (root / 'lib/core/services/pairing_link.dart').read_text()
    assert "static const scheme = 'hermes'" in pairing
    assert "static const authority = 'pair'" in pairing
    notification = (root / 'lib/core/services/notifications/background_listener.dart').read_text()
    assert 'dev.xpetalab.hermesconsole' not in notification
    assert f'{PACKAGE}.voice.NOTIFICATION_ICON_ACTIVE' in notification
    updates = (root / 'lib/core/services/install_source.dart').read_text()
    assert 'https://github.com/dedtsss/hermes-console/releases' in updates
    assert 'xP3ta/hermes-console/releases' not in updates
    assert 'play.google.com' not in updates
    main = (root / 'lib/main.dart').read_text()
    assert "AppLocaleOption('ru', 'Русский', Locale('ru'))" in main
    assert "if (locale?.languageCode == 'ru') return const Locale('ru');" in main
    version = re.search(r'^version: \d+\.\d+\.(\d+)(?:-ru\.[1-9][0-9]*)?\+(\d+)$', (root / 'pubspec.yaml').read_text(), re.M)
    assert version and int(version[2]) > 4964, 'version code must update the established RU install'
    # Upstream release policy has its own signer/package anchors. It stays
    # upstream reference material, never authority to sign or publish RU.
    release_workflow = (root / '.github/workflows/build-apk.yml').read_text()
    assert 'secrets.' not in release_workflow
    assert 'gh release' not in release_workflow
    for workflow in (root / '.github/workflows').glob('*.yml'):
        text = workflow.read_text()
        assert 'actions/upload-artifact' not in text, f'artifact upload added: {workflow}'
    print('RU package, release signing configuration, locale and pairing identity preserved')


if __name__ == '__main__':
    check()
