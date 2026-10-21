#!/usr/bin/env python3
"""Detect published stable upstream releases and stage a reviewed RU overlay.

No push, PR, signing, artifact upload or publication is performed by this tool.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import localization
import source_sbom

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = 'xP3ta/hermes-console'
FORK = 'dedtsss/hermes-console'
URL = f'https://github.com/{UPSTREAM}.git'
BRANCH_PREFIX = 'sync/upstream-'
PIN = Path('tool/fork/upstream.json')
MANIFEST = Path('tool/fork/overlay.json')
PATCH = Path('tool/fork/overlay.patch')
TAG = re.compile(r'^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')


def run(*args, root=ROOT, check=True, **kwargs):
    return subprocess.run(args, cwd=root, check=check, capture_output=True, text=True, **kwargs)


def git(*args, root=ROOT):
    return run('git', *args, root=root).stdout.strip()


def version(tag):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError('only stable vMAJOR.MINOR.PATCH tags are allowed')
    return tuple(map(int, match.groups()))


def stable_release(release):
    return (
        release.get('draft') is False
        and release.get('prerelease') is False
        and isinstance(release.get('published_at'), str)
        and TAG.fullmatch(release.get('tag_name', '')) is not None
    )


def latest(releases):
    candidates = [release for release in releases if stable_release(release)]
    if not candidates:
        raise ValueError('no published stable releases found')
    return max(candidates, key=lambda item: version(item['tag_name']))


def releases():
    # Paginate, so a page full of previews cannot hide the latest stable.
    data = run('gh', 'api', '--paginate', f'repos/{UPSTREAM}/releases', '--jq', '.[] | @json').stdout
    return [json.loads(line) for line in data.splitlines() if line.strip()]


def assert_fork(root):
    origin = git('remote', 'get-url', '--push', 'origin', root=root)
    allowed = {f'https://github.com/{FORK}.git', f'https://github.com/{FORK}', f'git@github.com:{FORK}.git'}
    if origin not in allowed:
        raise ValueError('origin must point to the owner fork; upstream is read-only')


def path_manifest(root):
    manifest = localization.read_json(root / MANIFEST)
    for group in ('patch', 'local', 'derived'):
        paths = manifest[group]
        if len(paths) != len(set(paths)):
            raise ValueError('duplicate overlay path')
        for item in paths:
            path = Path(item)
            if path.is_absolute() or '..' in path.parts or any(part.startswith('.') for part in path.parts[:-1] if part != '.github'):
                raise ValueError(f'unsafe overlay path: {item}')
    all_paths = [item for group in ('patch', 'local', 'derived') for item in manifest[group]]
    if len(set(all_paths)) != len(all_paths):
        raise ValueError('overlay path belongs to more than one group')
    return manifest


def overlay_diff(root, baseline, paths):
    return run('git', 'diff', '--binary', '--no-ext-diff', baseline, '--', *paths, root=root).stdout


def check_overlay(root):
    pin = localization.read_json(root / PIN)
    if pin['repository'] != UPSTREAM:
        raise ValueError('unexpected upstream repository')
    if not re.fullmatch('[0-9a-f]{40}', pin['commit']):
        raise ValueError('upstream commit must be a full immutable SHA')
    version(pin['tag'])
    manifest = path_manifest(root)
    baseline = pin['commit']
    git('cat-file', '-e', baseline + '^{commit}', root=root)
    if overlay_diff(root, baseline, manifest['patch']) != (root / PATCH).read_text(encoding='utf-8'):
        raise ValueError('overlay.patch is stale; review changes, then run refresh-overlay')
    allowed = set(manifest['patch'] + manifest['local'] + manifest['derived'])
    changed = set(git('diff', '--name-only', baseline, '--', root=root).splitlines())
    if changed - allowed:
        raise ValueError(f'unclassified fork changes: {sorted(changed - allowed)}')
    return pin, manifest


def refresh(root):
    pin = localization.read_json(root / PIN)
    manifest = path_manifest(root)
    (root / PATCH).write_text(overlay_diff(root, pin['commit'], manifest['patch']), encoding='utf-8')


def stage(root, release, output):
    assert_fork(root)
    if git('status', '--porcelain', '--untracked-files=all', root=root):
        raise ValueError('staging requires a clean tracked and untracked working tree')
    pin, manifest = check_overlay(root)
    delta = localization.report(root)
    if delta['untranslated'] or delta['obsolete']:
        raise ValueError('current fork translations must pass before staging another release')
    if not stable_release(release):
        raise ValueError('release must be published, non-draft and non-prerelease')
    tag = release['tag_name']
    branch = BRANCH_PREFIX + tag
    if version(tag) <= version(pin['tag']):
        raise ValueError('release must be newer than the pinned stable baseline')
    if output.exists() or output == root or root in output.parents:
        raise ValueError('output worktree must be new and outside the caller checkout')
    if run('git', 'show-ref', '--verify', '--quiet', f'refs/heads/{branch}', root=root, check=False).returncode == 0:
        raise ValueError(f'{branch} already exists; finish the pending sync first')
    previous = git('rev-parse', 'HEAD', root=root)
    # Fetch exactly the release tag, never upstream main and never local tags.
    git('fetch', '--no-tags', URL, f'refs/tags/{tag}', root=root)
    target = git('rev-parse', 'FETCH_HEAD^{commit}', root=root)
    old_build = re.search(r'^version: .+\+(\d+)\s*$', git('show', f"{pin['commit']}:pubspec.yaml", root=root), re.M)
    pubspec = git('show', f'{target}:pubspec.yaml', root=root)
    new_build = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$', pubspec, re.M)
    if not new_build or new_build[1] != tag[1:] or not old_build or int(new_build[2]) <= int(old_build[1]):
        raise ValueError('release tag/version/build number mismatch or downgrade')
    tracked = set(git('ls-tree', '-r', '--name-only', target, root=root).splitlines())
    collisions = tracked & set(manifest['local'])
    if collisions:
        raise ValueError(f'upstream now owns fork-local paths; review required: {sorted(collisions)}')
    # The worktree is throwaway and separate from the caller's branch/index.
    git('worktree', 'add', '--detach', str(output), target, root=root)
    try:
        patch = (root / PATCH).read_text(encoding='utf-8')
        run('git', 'apply', '--check', '-', root=output, input=patch)
        run('git', 'apply', '-', root=output, input=patch)
        git('checkout', previous, '--', *manifest['local'], root=output)
        localization.write_json(output / PIN, {'repository': UPSTREAM, 'tag': tag, 'commit': target})
        localization.prepare(output)
        localization.write_json(output / 'tool/fork/untranslated.json', localization.report(output))
        source_sbom.rebind(output)
        refresh(output)
        git('add', '--', *manifest['patch'], *manifest['local'], *manifest['derived'], root=output)
        tree = git('write-tree', root=output)
        commit = run('git', 'commit-tree', tree, '-p', previous, '-p', target, root=output,
                     input=f'Sync stable upstream {tag}; RU translation review required\n',
                     env={**os.environ, 'GIT_AUTHOR_DATE': release['published_at'],
                          'GIT_COMMITTER_DATE': release['published_at']}).stdout.strip()
        git('update-ref', f'refs/heads/{branch}', commit, '0' * 40, root=root)
        git('reset', '--hard', commit, root=output)
    except Exception:
        git('worktree', 'remove', '--force', str(output), root=root)
        raise
    print(json.dumps({'branch': branch, 'tag': tag, 'upstream_commit': target,
                      'worktree': str(output), 'head': commit}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['detect', 'stage', 'check-overlay', 'refresh-overlay'])
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--tag', help='published stable release tag to stage')
    parser.add_argument('--output', type=Path, help='new isolated worktree for staging')
    parser.add_argument('--releases-json', type=Path, help='offline detection fixture (detect only)')
    args = parser.parse_args()
    root = args.root.resolve()
    if args.command == 'check-overlay':
        check_overlay(root)
        print('Stable baseline and explicit overlay match')
    elif args.command == 'refresh-overlay':
        refresh(root)
    elif args.command == 'detect':
        data = localization.read_json(args.releases_json) if args.releases_json else releases()
        release = latest(data)
        pin = localization.read_json(root / PIN)
        print(json.dumps({'repository': UPSTREAM, 'current': pin['tag'], 'latest': release['tag_name'],
                          'behind': version(release['tag_name']) > version(pin['tag'])}, indent=2))
    else:
        if not args.output or not args.tag or args.releases_json:
            parser.error('stage requires --tag and --output, without a detection fixture')
        version(args.tag)
        release = json.loads(run('gh', 'api', f'repos/{UPSTREAM}/releases/tags/{args.tag}').stdout)
        stage(root, release, args.output.resolve())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        # Never print command environment or remote response bodies.
        print(f'stable sync stopped: {error}', file=sys.stderr)
        sys.exit(1)
