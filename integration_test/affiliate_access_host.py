"""Run device UI contracts against Web's affiliate-access-fixture.py on port 19106."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['ios', 'android'])
parser.add_argument('--device', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
reverse = ['adb', '-s', args.device, 'reverse', 'tcp:19106', 'tcp:19106']
if args.platform == 'android':
    subprocess.run(reverse, check=True)
request = urllib.request.Request('http://127.0.0.1:19106/__qa/reset-captures', method='POST',
                                 data=json.dumps({'prefix': args.platform + '-'}).encode(),
                                 headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(request) as response:
    assert response.status == 200
command = ['flutter', '--suppress-analytics', 'drive', '--no-pub', '-d', args.device,
           '--driver=integration_test/affiliate_driver.dart',
           '--target=integration_test/affiliate_access_test.dart']
child = None
captures = []
try:
    with (output / f'{args.platform}.log').open('w') as log:
        child = subprocess.Popen(command, cwd=repo, env=dict(os.environ, CI='true'),
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in child.stdout:
            log.write(line)
            log.flush()
            if 'AFFILIATE_ACCESS_SCREENSHOT:' not in line:
                continue
            name = line.split('AFFILIATE_ACCESS_SCREENSHOT:', 1)[1].strip()
            assert name.startswith(args.platform + '-') and '/' not in name
            path = output / (name + '.png')
            if args.platform == 'ios':
                with tempfile.TemporaryDirectory(prefix='affiliate-access-capture-') as temporary:
                    capture = Path(temporary) / 'device.png'
                    subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', str(capture)],
                                   capture_output=True, check=True)
                    shutil.copyfile(capture, path)
            else:
                with path.open('wb') as screenshot:
                    subprocess.run(['adb', '-s', args.device, 'exec-out', 'screencap', '-p'],
                                   stdout=screenshot, check=True)
            request = urllib.request.Request('http://127.0.0.1:19106/__qa/ack', method='POST',
                                             data=json.dumps({'name': name}).encode(),
                                             headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(request) as response:
                assert response.status == 200
            captures.append(name)
        result = child.wait()
finally:
    if child is not None and child.poll() is None:
        child.terminate()
        child.wait(timeout=30)
    if args.platform == 'android':
        subprocess.run(['adb', '-s', args.device, 'reverse', '--remove', 'tcp:19106'], check=False)
(output / f'{args.platform}-result.json').write_text(json.dumps({
    'scope': 'native device UI with explicit local HTTP contract fixture; no real financial writes',
    'device': args.device, 'exit_code': result, 'screenshots': captures,
}, indent=2) + '\n')
print(args.platform, 'exit', result)
raise SystemExit(result)
