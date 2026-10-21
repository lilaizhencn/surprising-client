#!/usr/bin/env python3
"""Exercise Android system save/share/gallery with explicitly synthetic fixtures."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', default='emulator-5554')
parser.add_argument('--output', default='/tmp/surprising-native-export-qa')
args = parser.parse_args()
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
adb = ['adb', '-s', args.device]
package = 'com.surprising.surprising_client'
run_id = uuid.uuid4().hex[:10]
saved_name = f'surprising-qa-deposit-{run_id}.png'
gallery_name = f'surprising-qa-gallery-{run_id}.png'
owned_files = []

def run(*command, **kwargs):
    return subprocess.run(list(command), check=True, capture_output=True, timeout=20, **kwargs)

def tree():
    run(*adb, 'shell', 'uiautomator', 'dump', '/sdcard/surprising-export-window.xml')
    xml = run(*adb, 'exec-out', 'cat', '/sdcard/surprising-export-window.xml').stdout
    (out / 'latest-window.xml').write_bytes(xml)
    return list(ET.fromstring(xml).iter('node'))

def click(node):
    coordinates = list(map(int, re.findall(r'\d+', node.attrib['bounds'])))
    run(*adb, 'shell', 'input', 'tap', str((coordinates[0] + coordinates[2]) // 2), str((coordinates[1] + coordinates[3]) // 2))

def wait_node(predicate):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        for node in tree():
            if predicate(node.attrib):
                return node
        time.sleep(.2)
    raise RuntimeError('Expected native control unavailable; see latest-window.xml')

def screenshot(name):
    (out / f'{name}.png').write_bytes(run(*adb, 'exec-out', 'screencap', '-p').stdout)

def act(action, ack):
    cache = str(Path(ack).parent)
    if action == 'save':
        field = wait_node(lambda a: a.get('class') == 'android.widget.EditText' and 'deposit-USDT-ETH' in a.get('text', ''))
        click(field)
        run(*adb, 'shell', 'input', 'keyevent', 'KEYCODE_MOVE_END')
        run(*adb, 'shell', 'input', 'keyevent', '--longpress', 'KEYCODE_DEL')
        # Select all reliably through Android's keyboard shortcut.
        run(*adb, 'shell', 'input', 'keycombination', '113', '29')
        run(*adb, 'shell', 'input', 'text', saved_name)
        screenshot(action)
        click(wait_node(lambda a: a.get('text', '').upper() in ('SAVE', '保存') and a.get('enabled') == 'true'))
        path = f'/sdcard/Download/{saved_name}'
        owned_files.append(path)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            result = subprocess.run(adb + ['exec-out', 'cat', path], capture_output=True, timeout=10)
            if result.returncode == 0 and result.stdout.startswith(b'\x89PNG\r\n\x1a\n'):
                break
            time.sleep(.2)
        else:
            raise RuntimeError('Native save did not produce a PNG in Downloads')
        (out / 'saved-deposit.png').write_bytes(result.stdout)
        run(*adb, 'shell', 'run-as', package, 'sh', '-c', shlex.quote(f'cat > {cache}/native-saved-deposit.png'), input=result.stdout)
    elif action == 'share':
        wait_node(lambda a: a.get('text', '').lower() in ('sharing image', 'share', 'nearby share', 'quick share', 'bluetooth') or 'chooser' in a.get('resource-id', ''))
        screenshot(action)
        run(*adb, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
    elif action == 'cancel-save':
        wait_node(lambda a: a.get('class') == 'android.widget.EditText' and 'deposit-USDT-ETH' in a.get('text', ''))
        screenshot(action)
        run(*adb, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
        run(*adb, 'shell', 'input', 'keyevent', 'KEYCODE_BACK')
    elif action == 'prepare-gallery':
        image = run(*adb, 'exec-out', 'run-as', package, 'cat', f'{cache}/native-synthetic-gallery.png').stdout
        local = out / 'synthetic-gallery.png'
        local.write_bytes(image)
        target = f'/sdcard/Download/{gallery_name}'
        run(*adb, 'push', str(local), target)
        owned_files.append(target)
        run(*adb, 'shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', f'file://{target}')
        run(*adb, 'shell', 'pm', 'grant', package, 'android.permission.CAMERA')
        run(*adb, 'shell', 'pm', 'grant', package, 'android.permission.POST_NOTIFICATIONS')
    elif action == 'gallery':
        node = wait_node(lambda a: gallery_name in a.get('text', '') or gallery_name in a.get('content-desc', '') or (a.get('text') == 'Download' and 'photos' in a.get('package', '')))
        if node.get('text') == 'Download':
            click(node)
            node = wait_node(lambda a: 'photo' in a.get('content-desc', '').lower() and a.get('clickable') == 'true')
        screenshot(action)
        click(node)
    else:
        raise RuntimeError(f'Unknown native action {action}')

environment = os.environ.copy()
environment['NATIVE_QA_OUTPUT'] = str(out)
for key in ('NO_PROXY', 'no_proxy'):
    environment[key] = ','.join(filter(None, [environment.get(key, ''), 'localhost', '127.0.0.1', '::1']))
command = ['flutter', 'drive', '-d', args.device, '--driver=test_driver/redesign_driver.dart', '--target=integration_test/funding_export_test.dart']
completed = []
failure = None
try:
    with (out / 'native-run.log').open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, env=environment)
        for line in process.stdout:
            log.write(line)
            log.flush()
            print(line, end='', flush=True)
            if 'VMServiceFlutterDriver: Connecting to Flutter application' in line:
                # flutter drive installs before connecting and resumes afterward.
                for permission in ('android.permission.CAMERA', 'android.permission.POST_NOTIFICATIONS'):
                    run(*adb, 'shell', 'pm', 'grant', package, permission)
            marker = re.search(r'NATIVE_EXPORT_READY:([a-z-]+):(/[^\s]+\.ack)', line)
            if not marker:
                continue
            action, ack = marker.groups()
            if not re.fullmatch(r'/data/(?:user/0|data)/' + re.escape(package) + r'/(?:cache|code_cache)/native-export-' + re.escape(action) + r'\.ack', ack):
                raise RuntimeError('Unexpected acknowledgment path')
            try:
                act(action, ack)
                completed.append(action)
                print(f'NATIVE_EXPORT_VERIFIED:{action}', flush=True)
            except Exception as error:
                screenshot(f'failed-{action}')
                failure = str(error)
                print(f'NATIVE_EXPORT_FAILURE:{action}:{failure}', flush=True)
            finally:
                run(*adb, 'shell', 'run-as', package, 'touch', ack)
        result = process.wait()
    if failure or result or completed != ['save', 'share', 'cancel-save', 'prepare-gallery', 'gallery']:
        raise RuntimeError(failure or f'Native export QA failed: exit={result}, completed={completed}')
    (out / 'evidence.json').write_text(json.dumps({'platform': 'Android emulator', 'syntheticFixtures': True, 'actions': completed, 'externalMessagesSent': False, 'passed': True}, indent=2) + '\n')
finally:
    for path in owned_files:
        run(*adb, 'shell', 'rm', '-f', path)
