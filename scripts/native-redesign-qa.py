#!/usr/bin/env python3
"""Capture Android platform views and secure-window flags during each test scene.

Run with the supported Android JAVA_HOME/PATH. Uses synthetic fixtures only.
Flutter's native integration screenshot callback runs after the test finishes,
so a file handshake keeps the actual scene mounted until adb has captured it.
"""
import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', default='emulator-5554')
parser.add_argument('--platform', choices=['android', 'ios'], default='android')
parser.add_argument('--output', default='/tmp/surprising-mobile-native-qa')
args = parser.parse_args()
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
adb = ['adb', '-s', args.device]
package = 'com.surprising.surprising_client'
command = [
    'flutter', 'drive', '-d', args.device,
    '--driver=test_driver/redesign_driver.dart',
    '--target=integration_test/redesign_smoke_test.dart',
    '--dart-define=NATIVE_CAPTURE_HANDSHAKE=true',
]
completed = set()
failure = None
environment = os.environ.copy()
environment['NATIVE_QA_OUTPUT'] = str(output)
# Flutter connects to its device VM service over loopback. An inherited HTTP
# proxy must not intercept that connection after a successful native build.
local_hosts = ['localhost', '127.0.0.1', '::1']
for key in ('NO_PROXY', 'no_proxy'):
    environment[key] = ','.join(filter(None, [environment.get(key, ''), *local_hosts]))
with (output / 'native-run.log').open('w') as log:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, bufsize=1, env=environment)
    for line in process.stdout:
        log.write(line)
        log.flush()
        print(line, end='', flush=True)
        marker = re.search(r'NATIVE_CAPTURE_READY:([a-z-]+):(/[^\s]+\.ack)', line)
        if not marker:
            continue
        name, ack = marker.groups()
        if args.platform == 'android':
            valid_ack = bool(re.fullmatch(r'/data/(?:user/0|data)/' + re.escape(package) +
                             r'/(?:cache|code_cache)/native-capture-' + re.escape(name) + r'\.ack', ack))
        else:
            container = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.device,
                                        'com.surprising.surprisingClient', 'data'],
                                       capture_output=True, text=True, check=True, timeout=15).stdout.strip()
            valid_ack = Path(ack).resolve().is_relative_to(Path(container).resolve()) and \
                Path(ack).name == f'native-capture-{name}.ack'
        if not valid_ack:
            failure = f'Unexpected acknowledgment path for {name}'
            process.terminate()
            break
        try:
            if args.platform == 'android':
                capture = subprocess.run(adb + ['exec-out', 'screencap', '-p'],
                                         check=True, capture_output=True, timeout=15)
                (output / f'{name}-os.png').write_bytes(capture.stdout)
                windows = subprocess.run(adb + ['shell', 'dumpsys', 'window', 'windows'],
                                         check=True, capture_output=True, text=True, timeout=15).stdout
                own = '\n'.join(window for window in re.split(r'\n\s*Window #\d+ ', windows)
                                if package in window.split('\n')[0])
                (output / f'{name}-window.txt').write_text(own)
                secure = bool(re.search(r'\bSECURE\b', own))
                if not own or secure != name.startswith('withdrawal-'):
                    raise RuntimeError(f'Unexpected window capture flag for {name}')
            else:
                subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot',
                                str(output / f'{name}-os.png')],
                               check=True, capture_output=True, timeout=15)
                secure = 'inspect_ios_capture'
            completed.add(name)
            print(f'OS_CAPTURE_VERIFIED:{name}:secure={secure}', flush=True)
        except (OSError, subprocess.SubprocessError, RuntimeError) as error:
            failure = str(error)
        finally:
            # Acknowledge even a failed assertion so Flutter can clean up routes.
            if args.platform == 'android':
                subprocess.run(adb + ['shell', 'run-as', package, 'touch', shlex.quote(ack)],
                               check=True, timeout=10)
            else:
                Path(ack).touch()
    result = process.wait()
required = {'home-dark', 'home-light', 'markets-dark', 'tradingview-dark',
            'assets-dark', 'assets-light', 'deposit-entry', 'deposit-assets',
            'deposit-networks', 'deposit-address', 'deposit-menu', 'transfer-dark',
            'withdrawal-assets', 'withdrawal-networks', 'withdrawal-form',
            'withdrawal-protected', 'capture-restored'}
if failure or result or completed != required:
    sys.exit(failure or f'Native QA failed: exit={result}, captured={sorted(completed)}')
print('Native scenarios and phase captures passed. Review platform coverage in the report.')
