#!/bin/bash
set -euo pipefail
KEYCHAIN_PATH="$RUNNER_TEMP/cardledger-signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$KEYCHAIN_PASSWORD"
python3 - <<'PY'
import base64, os
from pathlib import Path
for key, filename in [('BUILD_CERTIFICATE_BASE64', 'distribution.p12'), ('BUILD_PROVISION_PROFILE_BASE64', 'profile.mobileprovision')]:
    path = Path(os.environ['RUNNER_TEMP']) / filename
    path.write_bytes(base64.b64decode(os.environ[key], validate=True))
    path.chmod(0o600)
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$RUNNER_TEMP/distribution.p12" -P "$BUILD_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
security cms -D -i "$RUNNER_TEMP/profile.mobileprovision" > "$RUNNER_TEMP/profile.plist"
python3 - <<'PY'
import datetime, os, plistlib, shutil, uuid
from pathlib import Path
root = Path(os.environ['RUNNER_TEMP'])
profile = plistlib.loads((root / 'profile.plist').read_bytes())
profile_id = str(uuid.UUID(profile['UUID'])).upper()
team = os.environ['APPLE_TEAM_ID']
assert team in profile['TeamIdentifier'], 'Signing profile belongs to a different Apple team'
assert profile['Name'] == os.environ['PROFILE_NAME'], 'Signing profile name mismatch'
assert profile['Entitlements']['application-identifier'] == team + '.com.jverdi.cardledger', 'Signing profile bundle ID mismatch'
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Signing profile expired'
assert not profile['Entitlements'].get('get-task-allow'), 'Development profile cannot sign a TestFlight build'
assert not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'), 'App Store distribution profile required'
destination = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
destination.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'profile.mobileprovision', destination / (profile_id + '.mobileprovision'))
with open(os.environ['GITHUB_ENV'], 'a') as stream:
    stream.write('CARD_PROFILE_UUID=' + profile_id + '\n')
PY
