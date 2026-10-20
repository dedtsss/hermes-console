#!/usr/bin/env python3
"""Rebind upstream source SBOM fingerprints for an identity-only Gradle overlay.

Dependency graphs and asset inventories are retained byte-for-byte as data.
This is allowed only if every generator input equals the pinned upstream input,
except the Android application ID and comments. CI runs the complete generator
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
        if path != changed and value != upstream[path]:
            raise ValueError(f'SBOM generator input changed: {relative}; use full Flutter CI regeneration')
    strip_comments = lambda text: re.sub(r'//[^\n]*', '', text).split()
    if strip_comments(inputs[changed].decode().replace('io.github.dedtsss.hermesconsole', 'dev.xpetalab.hermesconsole')) != strip_comments(upstream[changed].decode()):
        raise ValueError('Gradle overlay exceeds identity/comments; use full Flutter CI regeneration')
    with patch.object(Path, 'read_bytes', lambda path: upstream[path]):
        old_fingerprint = generator.fingerprint_inputs()
    for path in sorted((root / 'sbom').glob('*.json')):
        document = json.loads(path.read_text())
        if path.name.endswith('.cdx.json'):
            prop = next(item for item in document['metadata']['properties'] if item['name'] == 'hermes.input.sha256')
            actual = prop['value']
            if actual not in {old_fingerprint, fingerprint}:
                raise ValueError('source SBOM fingerprint is not the pinned upstream/overlay input')
            prop['value'] = fingerprint
            variant = path.name.removesuffix('.cdx.json')
            document['serialNumber'] = generator.serial_number(variant, fingerprint, None)
        else:
            if document['inputFingerprint'] not in {old_fingerprint, fingerprint}:
                raise ValueError('source inventory fingerprint is not the pinned upstream/overlay input')
            document['inputFingerprint'] = fingerprint
        generator.write_json(path, document)
    print('Source SBOM identity overlay rebound; full generator comparison remains mandatory in CI')


if __name__ == '__main__':
    rebind()
