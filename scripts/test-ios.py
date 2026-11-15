"""Compile before simulator startup, then run all tests on an isolated CI device."""
import argparse
import json
import subprocess
import sys


def run(command, timeout):
    print('+ ' + ' '.join(command), flush=True)
    return subprocess.run(command, check=True, timeout=timeout)


parser = argparse.ArgumentParser()
parser.add_argument('--suite', choices=['all', 'orientation', 'interaction'], default='all')
suite = parser.parse_args().suite
focused = {
    'all': [],
    'orientation': ['-only-testing:CardLedgerTests/OrientationTests'],
    'interaction': ['-only-testing:CardLedgerTests/CardMotionTests',
                    '-only-testing:CardLedgerUITests/CardInteractionUITests',
                    '-only-testing:CardLedgerUITests/CollectionUITests/testNoResultsOffersClearFiltersAndCardTypeIncludesNonSports'],
}[suite]

project = ['-project', 'CardLedger.xcodeproj', '-scheme', 'CardLedger',
           '-derivedDataPath', 'build/TestDerived',
           'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES']
device_id = None
try:
    # Compiler errors should surface even if a hosted simulator cannot boot.
    run(['xcodebuild', 'build-for-testing', *project,
         '-destination', 'generic/platform=iOS Simulator'], 300)
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], timeout=60))
    runtime, template = next((runtime, d) for runtime, items in devices['devices'].items()
                             if 'iOS-26-0' in runtime for d in items if 'iPhone' in d['name'])
    # Avoid reusing potentially stale pre-created devices in the runner image.
    device_id = subprocess.check_output(
        ['xcrun', 'simctl', 'create', 'CardLedger CI', template['deviceTypeIdentifier'], runtime],
        text=True, timeout=60).strip()
    run(['xcrun', 'simctl', 'boot', device_id], 60)
    try:
        run(['xcrun', 'simctl', 'bootstatus', device_id, '-b'], 180)
    except subprocess.TimeoutExpired:
        # Only startup is retried; failed tests remain failures.
        run(['xcrun', 'simctl', 'shutdown', device_id], 60)
        run(['xcrun', 'simctl', 'erase', device_id], 60)
        run(['xcrun', 'simctl', 'boot', device_id], 60)
        run(['xcrun', 'simctl', 'bootstatus', device_id, '-b'], 180)
    run(['xcodebuild', 'test-without-building', *project,
         '-destination', 'platform=iOS Simulator,id=' + device_id,
         '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
         '-default-test-execution-time-allowance', '60',
         '-maximum-test-execution-time-allowance', '180',
         '-resultBundlePath', 'TestResults.xcresult', *focused], 1200)
except (subprocess.CalledProcessError, subprocess.TimeoutExpired, StopIteration, KeyError) as error:
    print('iOS verification failed: ' + str(error), flush=True)
    subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'booted'], timeout=30)
    sys.exit(1)
finally:
    if device_id:
        subprocess.run(['xcrun', 'simctl', 'shutdown', device_id], timeout=30)
        subprocess.run(['xcrun', 'simctl', 'delete', device_id], timeout=30)

