"""Drive the real local Gateway flow and synchronise OS screenshots with the app."""
import argparse
import datetime
import http.server
import os
from pathlib import Path
import subprocess
import threading
import tempfile
import shutil
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['ios', 'android'])
parser.add_argument('--device', required=True)
parser.add_argument('--database', default='surprising_affiliate_qa_20261028')
parser.add_argument('--owner-id', type=int, default=3)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
artifacts = repo.parent / 'surprising-ex/docs/validation/affiliate-20261028'
artifacts.mkdir(parents=True, exist_ok=True)
acks = set()


class Acknowledgements(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get('name', [''])[0]
        self.send_response(200 if name in acks else 202)
        self.end_headers()

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 19095), Acknowledgements)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
if args.platform == 'android':
    # Use the Android build JDK configured by the caller, independently from backend JDK 27.
    for port in ('19094', '19095'):
        subprocess.run(['adb', '-s', args.device, 'reverse', f'tcp:{port}', f'tcp:{port}'], check=True)
code = subprocess.check_output([
    'psql', '-d', args.database, '-Atc',
    f'SELECT invite_code FROM affiliate_profiles WHERE user_id={args.owner_id}'
], text=True).strip()
assert len(code) == 32
cmd = [
    'flutter', '--suppress-analytics', 'drive', '--no-pub', '-d', args.device,
    '--driver=integration_test/affiliate_driver.dart',
    '--target=integration_test/affiliate_live_test.dart',
    '--dart-define=AFFILIATE_TEST_GATEWAY=http://127.0.0.1:19094'
]
confirmation = repo / 'integration_test/affiliate_ios_open.yaml'
try:
    with open(artifacts / f'{args.platform}-device.log', 'w') as log:
        child = subprocess.Popen(cmd, cwd=repo, env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in child.stdout:
            log.write(line)
            log.flush()
            if 'AFFILIATE_DEVICE_SCREENSHOT:' in line:
                name = line.split('AFFILIATE_DEVICE_SCREENSHOT:', 1)[1].strip()
                assert name.startswith(f'affiliate-{args.platform}-') and '/' not in name
                path = artifacts / f'{name}.png'
                if args.platform == 'ios':
                    # The simulator daemon cannot write into macOS Desktop-protected directories.
                    with tempfile.TemporaryDirectory(prefix='affiliate-screenshot-') as temporary:
                        capture = Path(temporary) / 'device.png'
                        subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', str(capture)],
                                       capture_output=True, check=True)
                        shutil.copyfile(capture, path)
                else:
                    with open(path, 'wb') as screenshot:
                        subprocess.run(['adb', '-s', args.device, 'exec-out', 'screencap', '-p'],
                                       stdout=screenshot, check=True)
                acks.add(name)
            if 'AFFILIATE_DEEP_LINK_READY' in line:
                log.write(f'HOST deep link start {datetime.datetime.now().isoformat()}\n')
                uri = 'surprising://affiliate?invite=' + code
                open_cmd = (['xcrun', 'simctl', 'openurl', args.device, uri]
                            if args.platform == 'ios' else
                            ['adb', '-s', args.device, 'shell', 'am', 'start', '-W', '-a',
                             'android.intent.action.VIEW', '-d', uri, 'com.surprising.surprising_client'])
                outcome = subprocess.run(open_cmd, capture_output=True, text=True, check=True)
                log.write('HOST OS DEEP LINK: ' + outcome.stdout + outcome.stderr)
                if args.platform == 'ios':
                    outcome = subprocess.run(['maestro', '--device', args.device, 'test', str(confirmation)],
                                             capture_output=True, text=True, check=True)
                    log.write('HOST SYSTEM CONFIRMATION: ' + outcome.stdout + outcome.stderr)
                log.flush()
        result = child.wait()
finally:
    server.shutdown()
    if 'child' in locals() and child.poll() is None:
        child.terminate()
        child.wait(timeout=30)
print(f'{args.platform} native integration exit={result}', flush=True)
raise SystemExit(result)
