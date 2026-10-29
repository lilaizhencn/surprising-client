"""Run native Flutter acceptance and capture the platform compositor, including UIKit glass."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--api', required=True)
parser.add_argument('--kyc-only', action='store_true')
args = parser.parse_args()
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
android = args.device.startswith('emulator-')
adb = str(Path.home() / 'Library/Android/sdk/platform-tools/adb')
if android:
    if not args.kyc_only:
        subprocess.run([adb, '-s', args.device, 'shell', 'cmd', 'device_state', 'state', '2'], check=True)
    subprocess.run([adb, '-s', args.device, 'shell', 'settings', 'put', 'system', 'screen_off_timeout', '1800000'], check=True)
    subprocess.run([adb, '-s', args.device, 'shell', 'svc', 'power', 'stayon', 'true'], check=True)
    subprocess.run([adb, '-s', args.device, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'], check=True)
    subprocess.run([adb, '-s', args.device, 'shell', 'wm', 'dismiss-keyguard'], check=True)
command = ['flutter', 'drive', '--no-pub', '--driver=test_driver/redesign_driver.dart',
           '--target=integration_test/kyc_adaptive_themes_test.dart', '-d', args.device,
           '--dart-define=KYC_QA_URL=' + args.api]
if android:
    command.append('--no-start-paused')
if args.kyc_only:
    command.append('--dart-define=QA_ONLY_KYC=true')
captures = []
samples = []
with (output / 'device.log').open('w') as log:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                               env={**os.environ, 'NATIVE_QA_OUTPUT': str(output)})
    for line in process.stdout:
        log.write(line)
        log.flush()
        posture_match = re.search(r'NATIVE_POSTURE_READY:([a-z0-9-]+):(.+?\.ack)', line)
        if posture_match:
            posture_name, acknowledgement = posture_match.groups()
            states = {'folded': '0', 'unfolded': '2', 'half-opened': '1'}
            if posture_name in states:
                subprocess.run([adb, '-s', args.device, 'shell', 'cmd', 'device_state', 'state', states[posture_name]], check=True)
                subprocess.run([adb, '-s', args.device, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'], check=True)
                subprocess.run([adb, '-s', args.device, 'shell', 'wm', 'dismiss-keyguard'], check=True)
                subprocess.run([adb, '-s', args.device, 'shell', 'am', 'start', '-W', '--activity-single-top', '-n',
                                'com.surprising.surprising_client/.MainActivity'], check=True, stdout=subprocess.DEVNULL)
                time.sleep(2)
            subprocess.run([adb, '-s', args.device, 'shell', 'run-as', 'com.surprising.surprising_client', 'touch', acknowledgement], check=True)
            print('Changed posture to ' + posture_name, flush=True)
            continue
        match = re.search(r'NATIVE_CAPTURE_READY:([a-z0-9-]+):(.+?\.ack)', line)
        if match:
            name, acknowledgement = match.groups()
            screenshot = output / (name + '.png')
            if android:
                displays = subprocess.check_output([adb, '-s', args.device, 'shell', 'dumpsys', 'display'], text=True)
                active = re.search(r'DisplayDeviceInfo\{[^\n]*uniqueId="local:(\d+)"[^\n]*\bstate ON,', displays)
                if not active:
                    raise RuntimeError('No active physical display for screenshot')
                png = subprocess.check_output([adb, '-s', args.device, 'exec-out', 'screencap', '-p', '-d', active.group(1)])
                if not png.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise RuntimeError('Android screenshot did not return a PNG')
                screenshot.write_bytes(png)
                subprocess.run([adb, '-s', args.device, 'shell', 'run-as', 'com.surprising.surprising_client', 'touch', acknowledgement], check=True)
            else:
                subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', str(screenshot)], check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                Path(acknowledgement).touch()
            if name in {'after-navigation-cycles', 'kyc-renewed', 'kyc-polling-after60s'}:
                if android:
                    result = subprocess.run([adb, '-s', args.device, 'shell', 'dumpsys', 'meminfo', 'com.surprising.surprising_client'], capture_output=True, text=True)
                    (output / (name + '-memory.txt')).write_text(result.stdout)
                else:
                    result = subprocess.run(['ps', '-axo', 'pid=,pcpu=,rss=,comm='], capture_output=True, text=True)
                    for row in result.stdout.splitlines():
                        if args.device in row and '/Runner.app/Runner' in row:
                            pid, cpu, rss, _ = row.split(None, 3)
                            samples.append({'capture': name, 'time': time.time(), 'pid': int(pid), 'cpuPercent': float(cpu), 'rssKiB': int(rss)})
            captures.append(name)
            print('Captured ' + name, flush=True)
        elif any(word in line for word in ['Error', 'Exception', 'FAILED', 'All tests passed', 'Xcode build done']):
            print(line.rstrip(), flush=True)
    code = process.wait()
(output / 'result.json').write_text(json.dumps({'device': args.device, 'exitCode': code,
    'captures': captures, 'processSamples': samples, 'syntheticIdentity': True, 'osFileSelectorSubstituted': True}, indent=2))
raise SystemExit(code)
