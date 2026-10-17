#!/usr/bin/env bash
# 镜像类清单审计（03-architecture §1：同一 ObjC 类不得出现在同一进程的多个镜像）。
# 按真实共载组检查：SB={SpringBoard,UIKit,Core}；App={UIKit,Core}；
# Preferences.app={Prefs,*,UIKit,Core}；druid/pasted={PasteServices,Core}。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE="$ROOT_DIR/.theos/_"

audit() {
    python3 - "$@" <<'PYEOF'
import subprocess, sys, itertools, os
stage = os.environ["STAGE"]
def classes(path):
    if not os.path.exists(path):
        print(f"error: missing binary for audit: {path}", file=sys.stderr); sys.exit(2)
    out = subprocess.run(['nm', '-gU', path], capture_output=True, text=True).stdout
    return {l.split()[-1].replace('_OBJC_CLASS_$_','') for l in out.splitlines() if '_OBJC_CLASS_$_' in l}
groups = {
  'SpringBoard': ['Library/MobileSubstrate/DynamicLibraries/MetisSpringBoard.dylib',
                  'Library/MobileSubstrate/DynamicLibraries/MetisUIKit.dylib',
                  'Library/Metis/Frameworks/MetisCore.dylib'],
  'App': ['Library/MobileSubstrate/DynamicLibraries/MetisUIKit.dylib',
          'Library/Metis/Frameworks/MetisCore.dylib'],
  'Preferences': ['Library/PreferenceBundles/MetisPrefs.bundle/MetisPrefs',
                  'Library/PreferenceBundles/MetisCapturePrefs.bundle/MetisCapturePrefs',
                  'Library/PreferenceBundles/MetisKeyboardPrefs.bundle/MetisKeyboardPrefs',
                  'Library/PreferenceBundles/MetisClipboardPrefs.bundle/MetisClipboardPrefs',
                  'Library/MobileSubstrate/DynamicLibraries/MetisUIKit.dylib',
                  'Library/Metis/Frameworks/MetisCore.dylib'],
  'PasteServices': ['Library/MobileSubstrate/DynamicLibraries/MetisPasteServices.dylib',
                    'Library/Metis/Frameworks/MetisCore.dylib'],
}
fail = False
for name, paths in groups.items():
    sets = {p: classes(os.path.join(stage, p)) for p in paths if os.path.exists(os.path.join(stage, p))}
    for a, b in itertools.combinations(sets, 2):
        dup = sets[a] & sets[b]
        if dup:
            fail = True
            print(f"DUPLICATE in {name}: {a} x {b}: {sorted(dup)}")
print("class audit:", "FAIL" if fail else "PASS")
sys.exit(1 if fail else 0)
PYEOF
}

STAGE="$STAGE" audit
