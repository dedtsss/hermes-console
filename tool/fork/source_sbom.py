#!/usr/bin/env python3
"""Rebind upstream source SBOMs for identity and a fork-only version bump.

Dependency graphs and asset inventories are retained, apart from the root app version.
This is allowed only if every generator input equals the pinned upstream input,
except Android identity/comments and the root application's version. CI runs the complete generator
with the pinned Flutter dependencies and rejects any disagreement.
"""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import re
import subprocess
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def fork_version(current, upstream):
    pattern = r'^version: (\d+\.\d+\.\d+)(?:-ru\.([1-9][0-9]*))?\+(\d+)$'
    before = re.search(pattern, upstream, re.M)
    after = re.search(pattern, current, re.M)
    if not before or not after:
        raise ValueError('invalid app version; use full Flutter CI regeneration')
    if current != upstream:
        if (after[1] != before[1] or not after[2] or int(after[3]) <= int(before[3])
                or re.sub(pattern, '', current, flags=re.M) != re.sub(pattern, '', upstream, flags=re.M)):
            raise ValueError('pubspec overlay exceeds a monotonic RU version bump; use full Flutter CI regeneration')
    return before[0].split(': ', 1)[1], after[0].split(': ', 1)[1]


def rebind(root=ROOT):
    spec = importlib.util.spec_from_file_location('fork_sbom_generator', root / 'tool/sbom/generate.py')
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    generator.ROOT = root
    baseline = json.loads((root / 'tool/fork/upstream.json').read_text())['commit']
    changed = root / 'android/app/build.gradle.kts'
    original_read = Path.read_bytes
    inputs = {}

    def capture(path):
        value = original_read(path)
        inputs[path] = value
        return value

    with patch.object(Path, 'read_bytes', capture):
        fingerprint = generator.fingerprint_inputs()
    upstream = {}
    for path, value in inputs.items():
        relative = path.relative_to(root).as_posix()
        upstream[path] = subprocess.check_output(['git', 'show', f'{baseline}:{relative}'], cwd=root)
        if path not in {changed, root / 'pubspec.yaml'} and value != upstream[path]:
            raise ValueError(f'SBOM generator input changed: {relative}; use full Flutter CI regeneration')
    pubspec = root / 'pubspec.yaml'
    old_version, new_version = fork_version(inputs[pubspec].decode(), upstream[pubspec].decode())
    strip_comments = lambda text: re.sub(r'//[^\n]*', '', text).split()
    if strip_comments(inputs[changed].decode().replace('io.github.dedtsss.hermesconsole', 'dev.xpetalab.hermesconsole')) != strip_comments(upstream[changed].decode()):
        raise ValueError('Gradle overlay exceeds identity/comments; use full Flutter CI regeneration')
    with patch.object(Path, 'read_bytes', lambda path: upstream[path]):
        old_fingerprint = generator.fingerprint_inputs()
    identity_inputs = {**upstream, changed: inputs[changed]}
    with patch.object(Path, 'read_bytes', lambda path: identity_inputs[path]):
        identity_fingerprint = generator.fingerprint_inputs()
    for path in sorted((root / 'sbom').glob('*.json')):
        document = json.loads(path.read_text())
        if path.name.endswith('.cdx.json'):
            prop = next(item for item in document['metadata']['properties'] if item['name'] == 'hermes.input.sha256')
            actual = prop['value']
            if actual not in {old_fingerprint, identity_fingerprint, fingerprint}:
                raise ValueError('source SBOM fingerprint is not the pinned upstream/overlay input')
            prop['value'] = fingerprint
            variant = path.name.removesuffix('.cdx.json')
            document['serialNumber'] = generator.serial_number(variant, fingerprint, None)
            old_ref = f'pkg:pub/hermes_android@{document["metadata"]["component"]["version"]}'
            new_ref = f'pkg:pub/hermes_android@{new_version}'
            for component in [document['metadata']['component'], *document['components']]:
                if component['bom-ref'] == old_ref:
                    if component['version'] not in {old_version, new_version}:
                        raise ValueError('unexpected source application version')
                    component.update({'version': new_version, 'bom-ref': new_ref, 'purl': new_ref})
            for dependency in document['dependencies']:
                if dependency['ref'] == old_ref:
                    dependency['ref'] = new_ref
        else:
            if document['inputFingerprint'] not in {old_fingerprint, identity_fingerprint, fingerprint}:
                raise ValueError('source inventory fingerprint is not the pinned upstream/overlay input')
            document['inputFingerprint'] = fingerprint
        generator.write_json(path, document)
    print('Source SBOM identity/version overlay rebound; full generator comparison remains mandatory in CI')


if __name__ == '__main__':
    rebind()
