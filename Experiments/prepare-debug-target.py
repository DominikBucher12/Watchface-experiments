#!/usr/bin/env python3
"""Prepare a separately identified, debug-signed ClockFace copy. Never installs/runs it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

RUNTIME = Path('/Library/Developer/CoreSimulator/Volumes/watchOS_23T570/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS 26.5.simruntime/Contents/Resources/RuntimeRoot')
IDENTIFIER = 'dev.develodom.WatchFaceLab.ClockFaceResearch'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-root', type=Path, default=RUNTIME)
    parser.add_argument('--output', type=Path, default=Path('/tmp/WatchFaceLab26-DebugTarget'))
    args = parser.parse_args()
    source = (args.runtime_root / 'Applications/ClockFace.app').resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        parser.error('Output already exists; use a fresh directory. No automatic overwrite.')
    if output == source or source in output.parents or args.runtime_root.resolve() in output.parents:
        parser.error('Output must be outside the simulator runtime.')
    for pattern in ('*.framework', '*.appex', '*.xpc'):
        if any(source.rglob(pattern)):
            parser.error('Unexpected nested code; review signing before preparing this runtime.')
    watched = [source / 'ClockFace', source / 'Info.plist']
    before = {str(path): digest(path) for path in watched}
    output.mkdir(parents=True)
    target = output / 'ClockFaceResearch.app'
    shutil.copytree(source, target, symlinks=True)
    plist_path = target / 'Info.plist'
    info = plistlib.loads(plist_path.read_bytes())
    if info.get('CFBundleIdentifier') != 'com.apple.clockface':
        raise RuntimeError('Unexpected source bundle identity')
    info['CFBundleIdentifier'] = IDENTIFIER
    info['CFBundleDisplayName'] = 'ClockFace Research'
    info['CFBundleName'] = 'ClockFaceResearch'
    info['WKApplication'] = True
    info['WKWatchOnly'] = True
    # Avoid advertising the system app's service names from a second app.
    removed_services = info.pop('SBMachServices', [])
    info.pop('SBAppTags', None)
    plist_path.write_bytes(plistlib.dumps(info))
    entitlements = output / 'Research.entitlements'
    entitlements.write_bytes(plistlib.dumps({
        'com.apple.security.get-task-allow': True,  # host macOS debugger policy
        'com.apple.security.cs.disable-library-validation': True,  # our ad-hoc dylibs
    }))
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', '0',
                    '--entitlements', str(entitlements), str(target)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', '--verbose', str(target)], check=True)
    after = {str(path): digest(path) for path in watched}
    if before != after:
        raise RuntimeError('Original runtime file hash changed unexpectedly')
    report = {
        'source': str(source), 'copy': str(target), 'identifier': IDENTIFIER,
        'runtime_source_hashes_unchanged': before == after,
        'source_sha256': before, 'removed_advertised_services': removed_services,
        'entitlements': plistlib.loads(entitlements.read_bytes()),
        'status': 'Prepared/signed only. Installation, launch and debugger attach untested.',
        'limitations': 'No Apple signing identity/private privileges preserved. Hardcoded service access may still occur. This copy is not the system face host.',
    }
    (output / 'Preparation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
