#!/usr/bin/env python3
"""Lightweight invariant checks; never reads a keystore or signing secret."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'io.github.dedtsss.hermesconsole'
CI_ARTIFACT_WORKFLOW = '.github/workflows/fork-android-check.yml'
CI_ARTIFACT_ACTION = 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
CI_ARTIFACT_NAME = 'ru-fullrelease-arm64-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}'
CI_ARTIFACT_PATH = 'build/app/outputs/flutter-apk/app-arm64-v8a-full-release.apk'


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
    workflow_dir = root / '.github/workflows'
    workflows = list(workflow_dir.glob('*.yml')) + list(workflow_dir.glob('*.yaml'))
    upload_workflows = []
    for workflow in workflows:
        text = workflow.read_text()
        if 'actions/upload-artifact' in text:
            upload_workflows.append(workflow)
            assert workflow.relative_to(root).as_posix() == CI_ARTIFACT_WORKFLOW, (
                f'artifact upload added outside the RU Android CI workflow: {workflow}'
            )

    assert len(upload_workflows) == 1, 'exactly one RU Android CI artifact upload is required'
    android_workflow = upload_workflows[0].read_text()
    upload_step = android_workflow.split('      - name: Archive unsigned ARM64 CI candidate\n', 1)
    assert len(upload_step) == 2, 'the only upload must be the named ARM64 CI candidate step'
    upload_step = upload_step[1].split('\n      - ', 1)[0]
    assert upload_step.count('actions/upload-artifact@') == 1
    assert upload_step.count('path:') == 1, 'the upload must contain exactly one file path'
    assert upload_step.count('name:') == 1, 'the upload must contain exactly one artifact name'
    assert CI_ARTIFACT_ACTION in upload_step, 'artifact action must stay pinned'
    assert f'name: {CI_ARTIFACT_NAME}' in upload_step, 'artifact name must be run-unique'
    assert f'path: {CI_ARTIFACT_PATH}' in upload_step, 'only the ARM64 fullRelease APK may upload'
    assert 'if-no-files-found: error' in upload_step
    assert 'retention-days: 7' in upload_step
    assert 'KEYSTORE_BASE64' not in upload_step and 'key.properties' not in upload_step
    print('RU package, release signing configuration, locale and pairing identity preserved')


if __name__ == '__main__':
    check()
