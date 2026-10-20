#!/usr/bin/env python3
"""RU catalog contract and reviewed-source ledger. Standard library only."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
LEDGER = Path('tool/fork/translation_review.json')
ALLOW = Path('tool/fork/untranslated_allowlist.json')
ANDROID = Path('android/app/src/main/res')
CATEGORIES = {'plural', 'select', 'selectordinal'}


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'duplicate JSON key: {key}')
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique)


def write_json(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def icu_contract(text):
    """Recursive ICU shape, independent of prose/order, including nested arms.

    Matches Flutter's default use-escaping:false (apostrophes are literal).
    Exact selectors are intentional: a sync never invents or drops an arm.
    """
    nodes = []
    position = 0
    while position < len(text):
        if text[position] == '}':
            raise ValueError('unmatched ICU closing brace')
        if text[position] != '{':
            position += 1
            continue
        end, depth = position + 1, 1
        while end < len(text) and depth:
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        if depth:
            raise ValueError('unclosed ICU argument')
        content = text[position + 1:end - 1]
        match = re.fullmatch(r'\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:,\s*([A-Za-z]+)\s*,(.*))?', content, re.S)
        if not match:
            raise ValueError('invalid ICU argument')
        name, kind, body = match.groups()
        kind = kind or 'argument'
        arms = []
        if kind in CATEGORIES:
            rest = body.strip()
            if rest.startswith('offset:'):
                raise ValueError('unsupported ICU plural offset; review tooling first')
            while rest:
                selector = re.match(r'(=?[A-Za-z0-9_]+)\s*\{', rest)
                if not selector:
                    raise ValueError('invalid ICU selector')
                label = selector[1]
                start = selector.end()
                stop, level = start, 1
                while stop < len(rest) and level:
                    level += (rest[stop] == '{') - (rest[stop] == '}')
                    stop += 1
                if level:
                    raise ValueError('unclosed ICU selector')
                if label in [arm[0] for arm in arms]:
                    raise ValueError('duplicate ICU selector')
                arms.append((label, icu_contract(rest[start:stop - 1])))
                rest = rest[stop:].strip()
            if 'other' not in [arm[0] for arm in arms]:
                raise ValueError('ICU selector missing other')
        elif kind != 'argument':
            raise ValueError(f'unsupported ICU kind: {kind}')
        node = (name, kind, tuple(sorted(arms)))
        # Prose may repeat a variable more often in a translation.
        if node not in nodes:
            nodes.append(node)
        position = end
    return tuple(sorted(nodes))


def placeholders(shape):
    result = set()
    for name, _, arms in shape:
        result.add(name)
        for _, child in arms:
            result.update(placeholders(child))
    return result


def metadata(catalog, key):
    # Descriptions are translator guidance, never a runtime type contract.
    return catalog.get('@' + key, {}).get('placeholders', {})


def native_resources(directory):
    result = {}
    for path in sorted(directory.glob('*.xml')):
        for node in ET.parse(path).getroot():
            if node.tag not in {'string', 'plurals', 'string-array'} or node.get('translatable') == 'false':
                continue
            key = node.tag + '/' + node.attrib['name']
            if key in result:
                raise ValueError(f'duplicate Android resource: {key}')
            result[key] = (path.name, node)
    return result


def native_value(node):
    if node.tag == 'string':
        return ''.join(node.itertext())
    if node.tag == 'plurals':
        return {item.attrib['quantity']: ''.join(item.itertext()) for item in node}
    return [''.join(item.itertext()) for item in node]


def printf_contract(value):
    # Ignore %% and compare index + conversion, including repeated positions.
    return Counter(re.findall(r'%(?!%)(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[a-zA-Z]', value.replace('%%', '')))


def native_contract(source, target):
    if type(source) is not type(target):
        raise ValueError('Android resource type differs')
    if isinstance(source, str):
        if printf_contract(source) != printf_contract(target):
            raise ValueError('Android format placeholders differ')
    elif isinstance(source, dict):
        if set(source) != set(target):
            raise ValueError('Android plural quantities differ')
        for key in source:
            native_contract(source[key], target[key])
    else:
        if len(source) != len(target):
            raise ValueError('Android string-array length differs')
        for left, right in zip(source, target):
            native_contract(left, right)


def entries(root):
    en = read_json(root / 'lib/l10n/app_en.arb')
    es = read_json(root / 'lib/l10n/app_es.arb')
    ru = read_json(root / 'lib/l10n/app_ru.arb')
    keys = {key for key in en if not key.startswith('@')}
    if keys != {key for key in es if not key.startswith('@')}:
        raise ValueError('upstream EN/ES key mismatch')
    if ru.get('@@locale') != 'ru':
        raise ValueError('Russian ARB locale must be ru')
    result = {}
    for key in sorted(keys):
        result['arb/' + key] = {
            'source': {'en': en[key], 'es': es[key], 'placeholders': metadata(es, key)},
            'translation': ru.get(key),
            'metadata': metadata(ru, key),
        }
    extras = ['arb/' + key for key in ru if not key.startswith('@') and key not in keys]
    canonical = native_resources(root / ANDROID / 'values')
    russian = native_resources(root / ANDROID / 'values-ru')
    for key, (filename, node) in canonical.items():
        result['android/' + key] = {
            'source': native_value(node),
            'translation': native_value(russian[key][1]) if key in russian else None,
            'file': filename,
        }
    extras += ['android/' + key for key in russian if key not in canonical]
    return result, sorted(extras)


def entry_errors(key, entry, allow):
    source, target = entry['source'], entry['translation']
    if target is None:
        return ['missing']
    if not isinstance(target, (str, dict, list)) or not str(target).strip():
        return ['blank']
    problems = []
    leaves = target.values() if isinstance(target, dict) else target if isinstance(target, list) else [target]
    if any(not isinstance(value, str) or not value.strip() for value in leaves):
        problems.append('blank translation leaf')
    try:
        if key.startswith('arb/'):
            if not isinstance(target, str):
                raise ValueError('ARB message must be a string')
            shape = icu_contract(source['es'])
            if placeholders(icu_contract(source['en'])) != placeholders(shape):
                raise ValueError('upstream EN/ES placeholder mismatch')
            if icu_contract(target) != shape:
                raise ValueError('RU ICU contract differs')
            if entry['metadata'] != source['placeholders']:
                raise ValueError('RU placeholder metadata differs')
        else:
            native_contract(source, target)
    except (ValueError, TypeError) as error:
        problems.append(str(error))
    # An exact, reviewed exception is needed for proper names, protocol labels,
    # commands and punctuation-only copy. It cannot bless a later changed value.
    exception = allow.get(key, {})
    approved = exception.get('translation') == target and bool(exception.get('reason'))
    text = json.dumps(target, ensure_ascii=False)
    if not re.search('[А-Яа-яЁё]', text) and not approved:
        problems.append('no Russian prose; explicit proper-name/protocol exception required')
    if key.startswith('arb/') and target in (source['en'], source['es']) and not approved:
        problems.append('source-language fallback')
    return problems


def report(root):
    catalog, extras = entries(root)
    ledger = read_json(root / LEDGER) if (root / LEDGER).exists() else {}
    allow = read_json(root / ALLOW) if (root / ALLOW).exists() else {}
    delta = {}
    for key, entry in catalog.items():
        reasons = entry_errors(key, entry, allow)
        previous = ledger.get(key)
        if previous is None:
            reasons.append('new')
        elif previous.get('source') != digest(entry['source']):
            reasons.append('source_changed')
        elif previous.get('translation') != digest(entry['translation']):
            reasons.append('translation_not_reviewed')
        if reasons:
            delta[key] = {'reasons': reasons, **entry}
    return {'schema': 1, 'untranslated': delta, 'obsolete': extras}


def prepare(root):
    """Prune removed keys and synchronize metadata; never synthesize RU text."""
    en = read_json(root / 'lib/l10n/app_en.arb')
    es = read_json(root / 'lib/l10n/app_es.arb')
    old = read_json(root / 'lib/l10n/app_ru.arb')
    ru = {'@@locale': 'ru'}
    for key in en:
        if key.startswith('@'):
            continue
        if key in old:
            ru[key] = old[key]
        if '@' + key in es:
            ru['@' + key] = es['@' + key]
    write_json(root / 'lib/l10n/app_ru.arb', ru)
    canonical = native_resources(root / ANDROID / 'values')
    russian = native_resources(root / ANDROID / 'values-ru')
    files = {}
    for key, (filename, _) in canonical.items():
        if key in russian:
            files.setdefault(filename, ET.Element('resources')).append(russian[key][1])
    for path in (root / ANDROID / 'values-ru').glob('*.xml'):
        path.unlink()
    for filename, node in files.items():
        ET.indent(node, space='    ')
        ET.ElementTree(node).write(root / ANDROID / 'values-ru' / filename, encoding='utf-8', xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'prepare', 'review'])
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--keys', type=Path, help='JSON array of explicitly reviewed arb/ or android/ keys')
    parser.add_argument('--all', action='store_true', help='explicit initial full-catalog review')
    args = parser.parse_args()
    root = args.root.resolve()
    if args.command == 'prepare':
        prepare(root)
    if args.command == 'review':
        if bool(args.keys) == args.all:
            parser.error('review requires exactly one of --keys or --all')
        catalog, extras = entries(root)
        allow = read_json(root / ALLOW)
        selected = read_json(args.keys) if args.keys else sorted(catalog)
        ledger = read_json(root / LEDGER) if (root / LEDGER).exists() else {}
        for key in selected:
            errors = entry_errors(key, catalog[key], allow)
            if errors:
                raise ValueError(f'{key}: {errors}')
            ledger[key] = {'source': digest(catalog[key]['source']), 'translation': digest(catalog[key]['translation'])}
        ledger = {key: value for key, value in sorted(ledger.items()) if key in catalog}
        write_json(root / LEDGER, ledger)
    delta = report(root)
    if args.report:
        write_json(args.report, delta)
    print(f"RU localization: {len(delta['untranslated'])} unresolved, {len(delta['obsolete'])} obsolete")
    return int(bool(delta['untranslated'] or delta['obsolete']))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f'localization gate: {error}', file=sys.stderr)
        sys.exit(1)
