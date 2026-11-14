"""Validate the exported artifact, not just project settings, before upload."""
import plistlib
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as ipa:
    paths = [p for p in ipa.namelist() if p.startswith('Payload/') and p.endswith('.app/Info.plist') and p.count('/') == 2]
    if len(paths) != 1:
        raise SystemExit('Expected exactly one app Info.plist')
    info = plistlib.loads(ipa.read(paths[0]))
    expected = {'CFBundleIdentifier': 'com.jverdi.cardledger', 'CFBundleDisplayName': 'Card Ledger', 'UIDeviceFamily': [1]}
    for key, value in expected.items():
        if info.get(key) != value:
            raise SystemExit(f'Unexpected exported {key}: {info.get(key)!r}')
    print(f"Verified Card Ledger {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iPhone family")
