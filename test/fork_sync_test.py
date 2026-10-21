"""Offline regressions for stable sync, source review and fail-closed RU parity."""
from __future__ import annotations
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool/fork'))
import localization as l
import sync as sync_tool


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()


def write(root, path, value):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value)


class IcuContractTest(unittest.TestCase):
    def test_nested_select_and_plural_are_checked_recursively(self):
        source = '{who, select, bot{{count, plural, =1{One} other{{count} bots}}} other{Other}}'
        translated = '{who, select, other{Другой} bot{{count, plural, other{Ботов: {count}} =1{Один}}}}'
        self.assertEqual(l.icu_contract(source), l.icu_contract(translated))
        changed = translated.replace('{count}', '{total}')
        self.assertNotEqual(l.icu_contract(source), l.icu_contract(changed))
        self.assertNotEqual(l.icu_contract(source), l.icu_contract(translated.replace('=1', '=2')))

    def test_malformed_icu_is_rejected(self):
        for value in ['{count', 'bad }', '{x, plural, one{1}}', '{x, select, other{a} other{b}}']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                l.icu_contract(value)

    def test_apostrophe_is_literal_under_flutter_default(self):
        self.assertEqual(l.icu_contract("It's {count}"), l.icu_contract('Это {count}'))

    def test_native_placeholder_type_position_and_quantity_matter(self):
        l.native_contract({'one': '%1$d task', 'other': '%1$d tasks'}, {'one': '%1$d задача', 'other': 'Задач: %1$d'})
        for bad in [{'one': '%1$s задача', 'other': '%1$d задач'}, {'other': '%1$d задач'}]:
            with self.subTest(value=bad), self.assertRaises(ValueError):
                l.native_contract({'one': '%1$d task', 'other': '%1$d tasks'}, bad)

    def test_duplicate_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.json'
            path.write_text('{"key": "one", "key": "two"}')
            with self.assertRaises(ValueError):
                l.read_json(path)


class CatalogFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for locale, text in [('en', 'Hello {name}'), ('es', 'Hola {name}'), ('ru', 'Привет, {name}')]:
            l.write_json(self.root / f'lib/l10n/app_{locale}.arb', {
                '@@locale': locale, 'greet': text,
                '@greet': {'placeholders': {'name': {'type': 'String'}}},
            })
        write(self.root, str(l.ANDROID / 'values/strings.xml'), '<resources><string name="greet">Hello %1$s</string></resources>')
        write(self.root, str(l.ANDROID / 'values-ru/strings.xml'), '<resources><string name="greet">Привет, %1$s</string></resources>')
        l.write_json(self.root / l.ALLOW, {})
        self.review()

    def review(self):
        entries, _ = l.entries(self.root)
        l.write_json(self.root / l.LEDGER, {
            key: {'source': l.digest(entry['source']), 'translation': l.digest(entry['translation'])}
            for key, entry in entries.items()
        })

    def edit_arb(self, locale, **changes):
        path = self.root / f'lib/l10n/app_{locale}.arb'
        value = l.read_json(path)
        value.update(changes)
        l.write_json(path, value)


class LocalizationGateTest(CatalogFixture):
    def test_reviewed_catalog_passes_and_new_key_fails_without_fallback(self):
        self.assertFalse(l.report(self.root)['untranslated'])
        self.edit_arb('en', added='New key')
        self.edit_arb('es', added='Nueva clave')
        l.prepare(self.root)
        self.assertNotIn('added', l.read_json(self.root / 'lib/l10n/app_ru.arb'))
        delta = l.report(self.root)['untranslated']
        self.assertEqual(set(delta), {'arb/added'})
        self.assertEqual(delta['arb/added']['reasons'], ['missing', 'new'])

    def test_changed_english_spanish_or_metadata_requires_review(self):
        for field in ('en', 'es', 'metadata'):
            with self.subTest(field=field):
                path = self.root / f"lib/l10n/app_{'es' if field == 'metadata' else field}.arb"
                before = path.read_bytes()
                value = l.read_json(path)
                if field == 'metadata':
                    value['@greet']['placeholders']['name']['type'] = 'Object'
                else:
                    value['greet'] += '!'
                l.write_json(path, value)
                self.assertIn('source_changed', l.report(self.root)['untranslated']['arb/greet']['reasons'])
                path.write_bytes(before)

    def test_modified_translation_requires_review_and_english_is_rejected(self):
        self.edit_arb('ru', greet='Здравствуйте, {name}')
        reasons = l.report(self.root)['untranslated']['arb/greet']['reasons']
        self.assertIn('translation_not_reviewed', reasons)
        self.edit_arb('ru', greet='Hello {name}')
        self.assertIn('source-language fallback', l.report(self.root)['untranslated']['arb/greet']['reasons'])

    def test_exact_exception_cannot_approve_another_value(self):
        self.edit_arb('en', greet='Hermes')
        self.edit_arb('es', greet='Hermes')
        self.edit_arb('ru', greet='Hermes')
        entries, _ = l.entries(self.root)
        entry = entries['arb/greet']
        allow = {'arb/greet': {'translation': 'Hermes', 'reason': 'product name'}}
        self.assertEqual(l.entry_errors('arb/greet', entry, allow), [])
        entry = {**entry, 'translation': 'English fallback'}
        self.assertTrue(l.entry_errors('arb/greet', entry, allow))

    def test_native_new_text_or_printf_change_fails_closed(self):
        path = self.root / l.ANDROID / 'values/strings.xml'
        path.write_text('<resources><string name="greet">Hello %1$d</string><string name="new">New</string></resources>')
        delta = l.report(self.root)['untranslated']
        self.assertIn('source_changed', delta['android/string/greet']['reasons'])
        self.assertIn('Android format placeholders differ', delta['android/string/greet']['reasons'])
        self.assertIn('missing', delta['android/string/new']['reasons'])

    def test_staging_prunes_obsolete_keys_and_synchronizes_source_metadata(self):
        self.edit_arb('ru', obsolete='Лишний')
        self.assertEqual(l.report(self.root)['obsolete'], ['arb/obsolete'])
        l.prepare(self.root)
        self.assertNotIn('obsolete', l.read_json(self.root / 'lib/l10n/app_ru.arb'))
        self.assertFalse(l.report(self.root)['untranslated'])


class StableSelectionTest(unittest.TestCase):
    def release(self, tag, **overrides):
        return {'tag_name': tag, 'draft': False, 'prerelease': False,
                'published_at': '2026-10-12T23:01:42Z', **overrides}

    def test_semver_not_publication_order_or_unreleased_main(self):
        releases = [self.release('v1.2.15'), self.release('v1.2.9'),
                    self.release('v2.0.0-rc1'), self.release('main'),
                    self.release('v3.0.0', prerelease=True), self.release('v4.0.0', draft=True)]
        self.assertEqual(sync_tool.latest(releases)['tag_name'], 'v1.2.15')
        with self.assertRaises(ValueError):
            sync_tool.version('v1.2.15; command')


class StageIntegrationTest(CatalogFixture):
    def setUp(self):
        super().setUp()
        git(self.root, 'init', '-b', 'main')
        git(self.root, 'config', 'user.name', 'Synthetic Test')
        git(self.root, 'config', 'user.email', 'test@example.invalid')
        # Initial upstream tree excludes all fork-local files.
        write(self.root, 'pubspec.yaml', 'version: 1.0.0+1\n')
        write(self.root, 'identity.txt', 'official\n')
        upstream_paths = ['pubspec.yaml', 'identity.txt', 'lib/l10n/app_en.arb', 'lib/l10n/app_es.arb', str(l.ANDROID / 'values/strings.xml')]
        git(self.root, 'add', '--', *upstream_paths)
        git(self.root, 'commit', '-m', 'synthetic upstream baseline')
        self.baseline = git(self.root, 'rev-parse', 'HEAD')
        # New stable release has untranslated messages and native resources.
        self.edit_arb('en', added='New message')
        self.edit_arb('es', added='Nuevo mensaje')
        write(self.root, 'pubspec.yaml', 'version: 1.0.1+2\n')
        write(self.root, str(l.ANDROID / 'values/strings.xml'), '<resources><string name="greet">Hello %1$s</string><string name="added">New native text</string></resources>')
        git(self.root, 'add', '--', 'pubspec.yaml', 'lib/l10n/app_en.arb', 'lib/l10n/app_es.arb', str(l.ANDROID / 'values/strings.xml'))
        git(self.root, 'commit', '-m', 'synthetic stable update')
        self.target = git(self.root, 'rev-parse', 'HEAD')
        git(self.root, 'tag', 'v1.0.1')
        git(self.root, 'switch', '-c', 'fork', self.baseline)
        git(self.root, 'remote', 'add', 'origin', 'https://github.com/dedtsss/hermes-console.git')
        self.manifest = {'patch': ['identity.txt'], 'local': [str(sync_tool.PIN), str(sync_tool.MANIFEST), str(sync_tool.PATCH), str(l.LEDGER), str(l.ALLOW), 'lib/l10n/app_ru.arb', str(l.ANDROID / 'values-ru/strings.xml'), 'tool/fork/untranslated.json'], 'derived': []}
        l.write_json(self.root / sync_tool.PIN, {'repository': sync_tool.UPSTREAM, 'tag': 'v1.0.0', 'commit': self.baseline})
        l.write_json(self.root / sync_tool.MANIFEST, self.manifest)
        l.write_json(self.root / 'tool/fork/untranslated.json', l.report(self.root))
        write(self.root, 'identity.txt', 'ru\n')
        sync_tool.refresh(self.root)
        git(self.root, 'add', '--', *self.manifest['local'], *self.manifest['patch'])
        git(self.root, 'commit', '-m', 'synthetic RU overlay')
        self.previous = git(self.root, 'rev-parse', 'HEAD')
        self.output = self.root.parent / (self.root.name + '-staged')
        self.addCleanup(lambda: subprocess.run(['git', 'worktree', 'remove', '--force', str(self.output)], cwd=self.root, capture_output=True))
        self.release = {'tag_name': 'v1.0.1', 'draft': False, 'prerelease': False, 'published_at': '2026-10-12T23:01:42Z'}

    def stage(self):
        with patch.object(sync_tool, 'URL', str(self.root)), patch.object(sync_tool.source_sbom, 'rebind'):
            sync_tool.stage(self.root, self.release, self.output)

    def test_stage_preserves_identity_and_history_but_blocks_new_ru(self):
        self.stage()
        self.assertEqual(git(self.root, 'rev-parse', 'HEAD'), self.previous)
        self.assertEqual(git(self.root, 'status', '--porcelain'), '')
        self.assertEqual((self.output / 'identity.txt').read_text(), 'ru\n')
        head = git(self.output, 'rev-parse', 'HEAD')
        self.assertEqual(git(self.output, 'show', '-s', '--format=%P', head), self.previous + ' ' + self.target)
        delta = l.read_json(self.output / 'tool/fork/untranslated.json')
        self.assertEqual(set(delta['untranslated']), {'arb/added', 'android/string/added'})
        self.assertNotIn('added', l.read_json(self.output / 'lib/l10n/app_ru.arb'))
        sync_tool.check_overlay(self.output)
        with self.assertRaises(ValueError):
            self.stage()

    def test_unclassified_or_stale_overlay_stops(self):
        write(self.root, 'unreviewed.txt', 'extra\n')
        git(self.root, 'add', '--', 'unreviewed.txt')
        git(self.root, 'commit', '-m', 'unclassified delta')
        with self.assertRaisesRegex(ValueError, 'unclassified'):
            self.stage()
        self.assertFalse(self.output.exists())

    def test_conflict_stops_without_mutating_caller_or_leaving_branch(self):
        write(self.root, str(sync_tool.PATCH), 'invalid patch\n')
        git(self.root, 'add', '--', str(sync_tool.PATCH))
        git(self.root, 'commit', '-m', 'stale overlay')
        with self.assertRaisesRegex(ValueError, 'stale'):
            self.stage()
        self.assertFalse(self.output.exists())

    def replace_synthetic_release(self, path, text):
        git(self.root, 'switch', '-c', 'release-edit', self.target)
        write(self.root, path, text)
        git(self.root, 'add', '--', path)
        git(self.root, 'commit', '-m', 'synthetic conflicting release')
        git(self.root, 'tag', '-f', 'v1.0.1')
        git(self.root, 'switch', 'fork')

    def test_actual_upstream_overlay_conflict_rolls_back_worktree(self):
        self.replace_synthetic_release('identity.txt', 'changed official identity\n')
        with self.assertRaises(subprocess.CalledProcessError):
            self.stage()
        self.assertFalse(self.output.exists())
        self.assertEqual(git(self.root, 'status', '--porcelain'), '')
        self.assertEqual(git(self.root, 'rev-parse', 'HEAD'), self.previous)

    def test_upstream_collision_with_owned_ru_file_is_rejected(self):
        self.replace_synthetic_release('lib/l10n/app_ru.arb', '{"@@locale": "ru"}\n')
        with self.assertRaisesRegex(ValueError, 'upstream now owns fork-local'):
            self.stage()
        self.assertFalse(self.output.exists())

    def test_retry_produces_identical_commit(self):
        self.stage()
        first = git(self.output, 'rev-parse', 'HEAD')
        git(self.root, 'worktree', 'remove', '--force', str(self.output))
        git(self.root, 'branch', '-D', 'sync/upstream-v1.0.1')
        self.stage()
        self.assertEqual(git(self.output, 'rev-parse', 'HEAD'), first)

    def test_upstream_push_target_is_rejected(self):
        git(self.root, 'remote', 'set-url', 'origin', 'https://github.com/xP3ta/hermes-console.git')
        with self.assertRaisesRegex(ValueError, 'owner fork'):
            self.stage()


if __name__ == '__main__':
    unittest.main()
