"""Fork-only distribution boundaries and dependency-free SBOM rebinding."""
import json
from pathlib import Path
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool/fork'))
import source_sbom

ANDROID = '{http://schemas.android.com/apk/res/android}'


class ForkAppUpdateTest(unittest.TestCase):
    def test_only_full_declares_install_permission_and_narrow_provider(self):
        full = ET.parse(ROOT / 'android/app/src/full/AndroidManifest.xml').getroot()
        permission = 'android.permission.REQUEST_INSTALL_PACKAGES'
        self.assertEqual([node.get(ANDROID + 'name') for node in full.findall('uses-permission')], [permission])
        for flavor in ('main', 'qa', 'play'):
            path = ROOT / f'android/app/src/{flavor}/AndroidManifest.xml'
            if path.exists():
                self.assertNotIn(permission, path.read_text())
        provider = full.find('application/provider')
        self.assertEqual(provider.get(ANDROID + 'exported'), 'false')
        self.assertEqual(provider.get(ANDROID + 'grantUriPermissions'), 'true')
        self.assertEqual(provider.get(ANDROID + 'authorities'), '${applicationId}.app_update_provider')
        paths = ET.parse(ROOT / 'android/app/src/main/res/xml/app_update_paths.xml').getroot()
        self.assertEqual([(node.tag, node.get('path')) for node in paths], [('cache-path', 'app_update/')])

    def test_sbom_version_bump_rejects_dependencies_and_non_monotonic_versions(self):
        before = 'name: hermes_android\nversion: 1.3.0+9630\ndependencies:\n  http: ^1.2.0\n'
        after = before.replace('1.3.0+9630', '1.3.0-ru.1+9631')
        self.assertEqual(source_sbom.fork_version(after, before), ('1.3.0+9630', '1.3.0-ru.1+9631'))
        self.assertEqual(source_sbom.fork_version(before, before), ('1.3.0+9630', '1.3.0+9630'))
        for bad in (
            after.replace('9631', '9630'), after.replace('9631', '9000'),
            after.replace('ru.1', 'beta.1'), after.replace('ru.1', 'ru.0'),
            after.replace('1.3.0-ru', '1.3.1-ru'), after.replace('^1.2.0', '^2.0.0'),
        ):
            with self.subTest(pubspec=bad), self.assertRaises(ValueError):
                source_sbom.fork_version(bad, before)

    def test_rebound_sboms_preserve_real_stable_third_party_graph(self):
        baseline = json.loads((ROOT / 'tool/fork/upstream.json').read_text())['commit']
        for variant in ('playRelease', 'fullRelease'):
            path = f'sbom/{variant}.cdx.json'
            old = json.loads(subprocess.check_output(['git', 'show', f'{baseline}:{path}'], cwd=ROOT))
            current = json.loads((ROOT / path).read_text())
            external = lambda d: [c for c in d['components'] if c['name'] != 'hermes_android']
            self.assertEqual(external(current), external(old))
            def edges(document):
                return [{**edge, 'ref': 'root' if edge['ref'].startswith('pkg:pub/hermes_android@') else edge['ref']}
                        for edge in document['dependencies']]
            self.assertEqual(edges(current), edges(old))
            own = current['metadata']['component']
            self.assertIn(own, current['components'])
            self.assertIn(own['bom-ref'], [d['ref'] for d in current['dependencies']])


if __name__ == '__main__':
    unittest.main()
