"""Capture the actual OS surface, including native WebViews, while the test waits."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--device", required=True)
parser.add_argument("--platform", choices=["android", "ios"], required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
command = ["flutter", "drive", "--no-pub", "--driver=integration_test/google_themes_driver.dart",
           "--target=integration_test/wallet_closure_test.dart", "-d", args.device]
adb = str(Path(os.environ.get("ANDROID_SDK_ROOT", os.environ.get("ANDROID_HOME", ""))) / "platform-tools/adb")
process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    for line in process.stdout:
        print(line, end="", flush=True)
        match = re.search(r"NATIVE_CAPTURE_READY:([a-z0-9-]+):([^\r\n]+)", line)
        if not match:
            continue
        name, ack = match.groups()
        screenshot = output / (name + ".png")
        if args.platform == "android":
            with screenshot.open("wb") as image:
                subprocess.run([adb, "-s", args.device, "exec-out", "screencap", "-p"], stdout=image, check=True, timeout=30)
            subprocess.run([adb, "-s", args.device, "shell", "run-as", "com.surprising.surprising_client", "touch", ack], check=True, timeout=15)
        else:
            subprocess.run(["xcrun", "simctl", "io", args.device, "screenshot", str(screenshot)], check=True, timeout=30)
            Path(ack).touch()
    sys.exit(process.wait())
except BaseException:
    if process.poll() is None:
        process.terminate()
    raise
