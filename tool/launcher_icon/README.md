# AETERN native launcher icon

Source: unchanged `surprising-ex-web/public/favicon.svg` at
`d72c9146a961a95b9348ec108ffec99272ed1e58`, matching
`src/components/layout/AeternMark.tsx` and the App's `AeternLogoMark` geometry.
Source SHA-256: `3c9114d17376e0360e99524df40027c090cea2aaa460d7cd3e6f9405c941048c`.

Keep the original white apex, cyan → violet → magenta infinity stroke and
translucent gradient rim; do not re-draw or invent another palette.

## Regenerate

Use an isolated Python environment, the pinned tools in `requirements.txt`,
and a system Cairo library (Homebrew `cairo` on macOS):

```sh
python3 -m venv /tmp/aetern-icon-tools
/tmp/aetern-icon-tools/bin/pip install -r tool/launcher_icon/requirements.txt
/tmp/aetern-icon-tools/bin/python tool/launcher_icon/generate.py
/tmp/aetern-icon-tools/bin/python tool/launcher_icon/generate.py --check
/tmp/aetern-icon-tools/bin/python -m unittest discover -s tool/launcher_icon -p 'test_*.py'
flutter test test/native_branding_test.dart test/native_launcher_icon_test.dart
```

The generator reads all existing iOS `Contents.json` size/scale entries and
writes RGB PNGs without an alpha channel. The background is the same full-bleed
`#05060F`; iOS applies its own outer mask. No pre-rounded transparent corners,
text or JPEG intermediates are added.

Android legacy square/round launchers are generated at all five densities.
API 26+ uses an opaque background color plus an RGBA adaptive foreground; the
unchanged 32-unit Web badge is scaled to 54dp and centered on the 108dp canvas,
inside the guaranteed 66dp circular safe zone. The same adaptive layers serve
square, squircle and circle masks. Legacy round icons receive a small safe inset.

The actual 1024px iOS launcher/preview is
`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`.
Generated resources are checked in; Python/Cairo are developer tools only,
not app runtime dependencies. No app name, application ID or Bundle ID changes.
