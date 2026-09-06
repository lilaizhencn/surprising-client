# AGENTS.md

Surprising Client 是 iOS / Android 客户端。Web 的产品线能力变更，需要同步检查移动端。

## 技术栈

- Flutter / Dart。
- 常用命令：
  - `flutter analyze`
  - `flutter test`
  - `flutter run`

## 产品线和订阅

- iOS 和 Android 必须同步支持现货、永续、交割、期权。
- 产品切换后要重新加载 instrument、行情、订单、持仓和风险数据，并重新订阅对应 WebSocket。
- 不要把产品切换做成会复用旧订阅状态的简单 tab。
- WebSocket 重连后必须重新订阅公共和私有 channel。
- 新实时 depth 是完整的 20 档替换快照，空盘口也必须替换；兼容旧 delta 时仍须检查 sequence。私有状态使用 accountState 等版本化推送和周期快照，不再订阅 matches，详见 REALTIME.md。

## UI 和文案

- 不要出现 OKX、欧易、Binance 等硬编码品牌。
- 移动端重点检查小屏、长 symbol、深浅色主题、键盘弹出、下拉选择、滚动区域。
- 交易、充值、资金、持仓、风险展示必须和后端字段一致。

## 验证和提交

- 提交前跑 `flutter analyze` 和 `flutter test`。
- 如果改到 Android/iOS 原生配置，说明改动原因并检查对应平台能启动。
- 通过验证后 commit and push。
- 不提交 `build/`、`.dart_tool/`、`.idea/`、本地截图或设备缓存。
