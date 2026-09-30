# surprising-client

Flutter mobile client for Surprising Exchange.

## Features

- Native Flutter K-line chart via `kline_chart`.
- Email/phone registration, login with EMAIL/PHONE/TOTP challenges, email verification and password recovery through `surprising-gateway`.
- Market list, candlestick, L2 order book, spot, USDT-margined, and coin-margined trading views.
- Real order submit, cancel, market close, wallet balances, transfers, positions, risk, liquidation records, and WebSocket event feed. TP/SL placement is fixed to mark-price triggering; versioned private snapshots update open triggers and recover state after private WebSocket reconnect.

## Local Backend

Start the backend from `surprising-ex` and make sure these ports are reachable:

- REST gateway: `9094`
- WebSocket fanout: `9093`

iOS simulator can use localhost:

```bash
flutter run \
  --dart-define=SURPRISING_GATEWAY_URL=http://127.0.0.1:9094 \
  --dart-define=SURPRISING_WEBSOCKET_URL=ws://127.0.0.1:9093/ws/v1
```

Android emulator must use the host bridge:

```bash
flutter run \
  --dart-define=SURPRISING_GATEWAY_URL=http://10.0.2.2:9094 \
  --dart-define=SURPRISING_WEBSOCKET_URL=ws://10.0.2.2:9093/ws/v1
```

Private WebSocket authentication sends the access token in an authenticate frame. Query user-ID fallback is disabled by default; enable `SURPRISING_WS_QUERY_USER_ID=true` only for a local backend that explicitly supports it.

Production builds use the shared API and WebSocket domain by default:

```text
REST: https://ex-api.tokdou.com
WS:   wss://ex-api.tokdou.com/ws/v1
```

Explicit `--dart-define` values still override these defaults.

## Verification

```bash
flutter analyze
flutter test
flutter build ios --debug --no-codesign
flutter build apk --debug
```

## Mobile / Web parity verification

The home and market pages default to U-margined perpetual markets. Search, product filters, market-to-trade navigation, recent trades, position/order tabs and TP/SL forms use the current gateway contract. REST and WS instrument IDs are mapped to display symbols per product. Colors follow the Web blue/light/dark palette.

Run `flutter analyze` and `flutter test`. `test/mobile_parity_test.dart` covers the wire ID contract, authentication challenges, password recovery, live trade merging, exact price increments and compact light/dark layouts. Existing realtime tests cover private authentication, reconnects, snapshot fences and depth updates.

Public read-only smoke check on 2026-09-30: instrument list, 20-level book, candles, recent trades and public WS subscriptions succeeded. Authenticated trading and OTP delivery still require staging credentials and device acceptance. This machine has no running mobile device and an incomplete Xcode installation, so unit/widget and public API checks do not establish iOS/Android runtime acceptance.

Android debug build was attempted with JDK 21; Gradle dependency downloads from plugins.gradle.org failed during TLS handshake. No native configuration was changed to work around the local environment.
