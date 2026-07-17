# surprising-client

Flutter mobile client for Surprising Exchange.

## Features

- Native Flutter K-line chart via `kline_chart`.
- Login and register through `surprising-gateway`.
- Market list, candlestick, L2 order book, spot, USDT-margined, and coin-margined trading views.
- Real order submit, cancel, market close, wallet balances, transfers, positions, risk, liquidation records, and WebSocket event feed. TP/SL placement is fixed to mark-price triggering; status snapshots update the open-trigger list immediately, with a full REST refresh after private WebSocket reconnect.

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

Local WebSocket uses `userId` query fallback by default because the backend local WebSocket service allows it. For production, set `SURPRISING_WS_QUERY_USER_ID=false` and configure the WebSocket JWT secret to match the gateway issuer/secret.

## Verification

```bash
flutter analyze
flutter test
flutter build ios --debug --no-codesign
flutter build apk --debug
```
