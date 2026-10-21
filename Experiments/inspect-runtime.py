#!/usr/bin/env python3
"""Read installed watch simulator binaries/plists; emit a compact evidence report.

No framework binaries or Apple headers are copied. No simulator process is touched.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

DEFAULT_RUNTIME = (
    '/Library/Developer/CoreSimulator/Volumes/watchOS_23T570/Library/Developer/'
    'CoreSimulator/Profiles/Runtimes/watchOS 26.5.simruntime/Contents/Resources/RuntimeRoot'
)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, timeout=120).stdout.decode(
        'utf-8', errors='replace'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-root', default=os.getenv('WATCH_RUNTIME_ROOT', DEFAULT_RUNTIME))
    args = parser.parse_args()
    root = Path(args.runtime_root)
    binary = root / 'System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit'
    inventory = []
    for bundle in sorted((root / 'System/Library/NanoTimeKit/FaceBundles').glob('*.bundle')):
        plist = bundle / 'Info.plist'
        info = {}
        if plist.is_file():
            with plist.open('rb') as stream:
                info = plistlib.load(stream)
        inventory.append({
            'directory': bundle.name,
            'has_info_plist': plist.is_file(),
            'identifier': info.get('CFBundleIdentifier'),
            'principal_class': info.get('NSPrincipalClass'),
            'executable': info.get('CFBundleExecutable'),
            'face_metadata': info.get('NTKFaceBundle', {}),
        })
    disassembly = run('xcrun', 'llvm-objdump', '--macho', '--arch=x86_64', '--disassemble', str(binary))
    labels = [
        '+[NTKBundleLoader rootDirectory]',
        '-[NTKFaceBundleManager _init]',
        '-[NTKFaceBundleManager _generateLookupsIfNecessary]',
        '-[NTKFaceBundleManager enumerateFaceBundlesOnDevice:includingLegacy:withBlock:]',
        '-[NTKFaceBundleManager faceBundleForFaceStyle:onDevice:]',
        '-[NTKFaceBundleManager faceBundleForBundleIdentifier:onDevice:forMigration:]',
        '_NTKFaceBundleClassesFromBundle',
        '___41-[NTKFaceBundleLoader _enumerateBundles:]_block_invoke',
        '___46-[NTKFaceBundleLoader _loadClassesUsingBlock:]_block_invoke',
        '-[NTKClockViewController _newFaceControllerForFace:withConfiguration:]',
        '-[NTKFaceViewController initWithFace:configuration:]',
        '-[NTKFaceViewController loadView]',
        '-[NTKFaceViewController configureWithDuration:block:]',
        '-[NTKFaceViewController becomeActive]',
        '-[NTKFaceViewController resignActive]',
    ]
    references = {}
    for label in labels:
        match = re.search(r'^' + re.escape(label) + r':\n(.*?)(?=^\S|\Z)',
                          disassembly, re.MULTILINE | re.DOTALL)
        if not match:
            raise RuntimeError(f'Missing expected symbol: {label}')
        references[label] = [line.strip() for line in match.group(1).splitlines() if any(
            marker in line for marker in (
                'selector ref:', 'cfstring ref:', 'literal pool for:',
                'literal pool symbol address: _OBJC_CLASS', 'symbol stub for: _getenv',
                'callq\t_NTKFaceBundleClassesFromBundle',
            )
        )]
    print(json.dumps({
        'runtime_root': str(root),
        'architecture': 'x86_64',
        'uuid': run('xcrun', 'dwarfdump', '--uuid', str(binary)).strip(),
        'bundle_count': len(inventory),
        'bundles': inventory,
        'references': references,
        'caution': 'Static references only; objc-dispatch comments may be misleading when selectors use registers.',
    }, indent=2))


if __name__ == '__main__':
    main()
