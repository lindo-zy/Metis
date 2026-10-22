#!/usr/bin/env python3
"""Reject duplicate Objective-C runtime classes in each actual co-load group.

Runs on the unpacked final package, on every required architecture. Class names
come from ObjC metadata, so hiding symbols does not silence the audit.
"""
import argparse
import itertools
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def class_names(output):
    classes = set()
    in_classes = False
    for line in output.splitlines():
        if line.startswith('Contents of '):
            in_classes = bool(re.search(r',__objc_(?:classlist|nlclslist)\) section$', line))
            continue
        if in_classes:
            # Class/metaclass ro-data has exactly eight leading spaces. Method,
            # ivar and protocol names have different indentation.
            match = re.match(r'^ {8}name\s+0x[0-9a-fA-F]+\s+(\S+)\s*$', line)
            if match:
                classes.add(match.group(1))
    return classes


def audit(root):
    core = 'Library/Metis/Frameworks/MetisCore.dylib'
    sb, ui, paste = [f'Library/MobileSubstrate/DynamicLibraries/{name}.dylib'
                     for name in ('MetisSpringBoard', 'MetisUIKit', 'MetisPasteServices')]
    prefs = []
    for bundle in sorted((root / 'Library/PreferenceBundles').glob('*.bundle')):
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        executable = info.get('CFBundleExecutable')
        if executable:
            path = bundle / executable
            if path.parent != bundle:
                raise ValueError(f'invalid bundle executable: {bundle.name}')
            prefs.append(str(path.relative_to(root)))
    if not prefs:
        raise ValueError('no preference bundle executables found')
    groups = {'SpringBoard': [core, sb, ui], 'App': [core, ui],
              'Preferences': [core, ui, *prefs], 'PasteServices': [core, paste]}
    paths = sorted(set(itertools.chain.from_iterable(groups.values())))
    classes = {}
    for relative in paths:
        binary = root / relative
        if not binary.is_file():
            raise ValueError(f'missing binary: {relative}')
        arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        if not {'arm64', 'arm64e'}.issubset(arches):
            raise ValueError(f'missing required architecture: {relative}: {arches}')
        for arch in arches:
            output = subprocess.check_output(['otool', '-arch', arch, '-ov', str(binary)], text=True)
            classes[relative, arch] = class_names(output)
            if re.search(r'Contents of .*__objc_(?:classlist|nlclslist)\) section\n[0-9a-fA-F]', output) and not classes[relative, arch]:
                raise ValueError(f'could not parse ObjC class metadata: {relative} ({arch})')
    duplicates = []
    for group, members in groups.items():
        for a, b in itertools.combinations(members, 2):
            for arch in ('arm64', 'arm64e'):
                for name in sorted(classes[a, arch] & classes[b, arch]):
                    duplicates.append(f'{group}/{arch}: {name}: {a} + {b}')
    if duplicates:
        for duplicate in duplicates:
            print(f'error: duplicate Objective-C class: {duplicate}', file=sys.stderr)
        return False
    print(f'==> Objective-C class audit OK ({len(paths)} binaries, 4 co-load groups, arm64 + arm64e)')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, help='unpacked package root')
    args = parser.parse_args()
    try:
        return 0 if audit(args.root) else 1
    except (OSError, ValueError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f'error: Objective-C class audit failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
