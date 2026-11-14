"""Bound simulator startup and testing separately so CI cannot silently stall."""
import json
import subprocess
import sys


def run(command, timeout):
    print('+ ' + ' '.join(command), flush=True)
    return subprocess.run(command, check=True, timeout=timeout)


devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
device = next(d for runtime, items in devices['devices'].items()
              if 'iOS-26-0' in runtime for d in items if 'iPhone' in d['name'])
try:
    if device['state'] != 'Booted':
        run(['xcrun', 'simctl', 'boot', device['udid']], 60)
    try:
        run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], 90)
    except subprocess.TimeoutExpired:
        # A fresh GitHub runner occasionally stalls during first simulator boot.
        # Retry startup once; test failures are never retried or hidden.
        run(['xcrun', 'simctl', 'shutdown', device['udid']], 60)
        run(['xcrun', 'simctl', 'boot', device['udid']], 60)
        run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], 180)
    run(['xcodebuild', 'test', '-project', 'CardLedger.xcodeproj', '-scheme', 'CardLedger',
         '-destination', 'platform=iOS Simulator,id=' + device['udid'],
         '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
         '-default-test-execution-time-allowance', '60',
         '-maximum-test-execution-time-allowance', '120',
         'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES',
         '-resultBundlePath', 'TestResults.xcresult'], 600)
except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
    print('iOS verification failed: ' + str(error), flush=True)
    subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'booted'], timeout=30)
    sys.exit(1)
