# surprising-client

Flutter mobile client for Surprising Exchange.

## Features

- Native Flutter K-line chart via `kline_chart`.
- Email/phone registration, login with EMAIL/PHONE/TOTP challenges, email verification and password recovery through `surprising-gateway`.
- Scrollable product tabs for spot, linear/inverse perpetuals, linear/inverse delivery and options; market list, candlestick, L2 order book and recent trades. Unconfigured products retain their page and show an explicit empty state.
- Real order submit, cancel, market close, wallet balances, transfers, positions, risk, liquidation records, and WebSocket event feed. TP/SL forms support mark/last/index sources and market/limit execution; versioned private snapshots update open triggers and recover state after private WebSocket reconnect.

## 算法单参数（2026-10-24）

仅TWAP显示、提交并校验间隔，ICEBERG间隔0表示不适用。TWAP不再发送固定TIF/PostOnly；ICEBERG只提交用户的PostOnly选择，由后端确定GTC/GTX。回包继续严格核对父单身份、数量、时长及实际执行方式，待确认和恢复身份流程保留。

本轮只执行`flutter build bundle --debug --no-pub`并通过（8.988秒）。未运行测试、analyze、设备/模拟器或真实交易；bundle编译不代表iOS/Android原生打包、交互或布局已通过。

## 倒计时撤单模型（2026-10-24）

模型删除`canceledOrders`/`canceledTriggerOrders`及默认零值解析，保留当前响应的五项事实；原时长仅作为SET输入，不再解析回显；原`symbol`字段改为实际`instrumentId`键，不保留旧名称或读取回退。请求、产品归属和页面布局不变。
最终执行`flutter build bundle --debug --no-pub`通过（9.352秒），未运行analyze、测试、设备交互或iOS/Android原生打包。

## 代码职责

| 入口 / owner | 职责 |
| --- | --- |
| `app.dart`、`AppScope` | 应用根、导航、共享依赖；主题和语言独立通知，行情不重建 `MaterialApp` |
| `AppState` | 协调产品选择、业务 owner、账户投影、风险详情读取及单条实时连接，不保存第二份业务状态 |
| `auth/AuthState` | 登录、验证、生物锁、会话代次与串行安全存储；会话只读，正常启动从安全存储恢复并刷新 |
| `trading/TradingOrderState` | 下单、撤单、改单、条件单、算法单及原请求恢复，持有未决身份与查询状态 |
| `wallet/AccountTransferState` | 划转凭证、验证、提交与原请求恢复 |
| `wallet/WalletState` | 资金账户、充值、提现规则与按用户隔离的提现凭证；退出不清除结果未知的财务身份 |
| `MarketDataState` | 盘口、成交、K 线、价格与版本；断档基线恢复 |
| `PrivateSnapshotRecovery` | 六产品私有首基线与坏快照的有界恢复；等待期间不复用旧 READY 状态 |
| `AccountProjection`、`PortfolioIncomeState` | 精确只读权益投影、收益刷新与过期，不修改可用资金 |
| `market/`、`trading/`、`wallet/`、`account/`、`auth/` | 各业务页面与交互；`ui/` 放共享样式、组件及导航约定 |

网络响应在边界校验精确 int64、有限数值、产品身份及完整私有快照。缺金额或 scale 显示不可用，不补零或 1e8。HTTP 截止时间覆盖连接、响应头、完整 body 和解码；取消或销毁释放底层请求，写请求超时仍保留原幂等身份。普通响应上限 8 MiB、文件下载 20 MiB、C2C 附件 10 MiB。

账户风险复用 `refreshRiskDetails`，在私有账户 READY 后读取既有 `/risk/account/latest`，与持仓风险共用请求代次和刷新定时器。按用户、会话、产品及结算资产隔离响应；已连接时每 5 秒刷新，15 秒未更新或私有账户失效即显示不可用，保留手动刷新入口。SPOT 不读取衍生品风险，也不补零。

本轮验证（2026-10-22）：743 项 Flutter 测试通过，12 项依赖环境的测试跳过；最后的输入框样式另验 56 项通过。普通 `lib/main.dart` 应用在 Android、iOS 模拟器分别完成真实登录、现货及 U 本位永续各一笔 PostOnly 挂单与原单撤销；原单均 CANCELED、成交及费用为零，资金差额、冻结与预留均为零。实际检查原生键盘、价格/数量步进、深浅主题与放大字体，测试资源已释放。其他四产品的设备覆盖采用契约样本，真实交易及恢复由后端验证，不代表六产品全部手机流程或生产环境已验收。

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

Public read-only acceptance on 2026-09-30 against `ex-api.tokdou.com`: the catalog currently contains three linear perpetual instruments (BTC/ETH/SOL), with no active instruments in the other five products. All three returned 20-level books, candles and recent trades. Actual WS acknowledgments verified BTC → ETH → SOL unsubscribe/subscribe, 1m → 5m candles and fresh subscriptions after reconnect. Depth, trades, candles, mark, index and funding updates were observed. In-flight old messages before unsubscribe acknowledgment are expected; product/instrument filtering prevents them from replacing the active market. No events arrived after their unsubscribe acknowledgment during this check.

Repeat the read-only deployment check with `dart run tool/public_realtime_smoke.dart`. Run the explicit device test with `flutter test integration_test/public_market_smoke_test.dart -d <device-id>`; it contacts the configured backend and checks the product tabs and live market views without signing in or placing orders.

Xcode 26.5 and the iOS 26.5 iPhone 17 Pro simulator are now available. `flutter build ios --simulator --debug` succeeded, and the installed app launched with live home-market data. The iOS device integration test passed all six product-tab selections and the three available perpetual markets. The project uses Swift Package Manager; `flutter.config.enable-swift-package-manager` is explicitly enabled so native plugins are linked. A supplied test account logged in successfully. Private WS authentication and all 36 subscriptions succeeded; the linear perpetual account returned fresh READY snapshots and REST agreed on zero positions, open orders and active triggers. The other five products returned INITIALIZING snapshots and their account REST endpoints returned HTTP 404; those products are not accepted as ready/empty accounts. No private delta events were generated by this idle account, so non-empty positions and order/TP-SL lifecycle transitions remain covered by protocol regression rather than live execution. No trading actions were submitted. Credentials are not stored in the repository; `dart run tool/private_realtime_smoke.dart` accepts hidden terminal input for a repeatable read-only check.

Android debug build was attempted with JDK 21; Gradle dependency downloads from plugins.gradle.org failed during TLS handshake. No native configuration was changed to work around the local environment.

`test/mobile_audit_test.dart` covers six product tabs at 320px width, empty products, selection races, partial trigger submission, logout during a batch, disposed authentication forms and empty depth. `test/product_realtime_audit_test.dart` checks identical symbols across products, isolated-position risk matching, partial/terminal orders, active/terminal triggers, stale events, wrong users and delayed cancellations. Position identity follows the backend's `instrumentId + positionSide`; margin mode is mutable data, not part of the key.

2026-09-30 verification: analyzer clean, 78 unit/widget tests passed, and the iOS live product-tab integration test passed. Private authentication and subscriptions recovered successfully after reconnect; the active perpetual view received fresh periodic snapshots again.

## Trading detail audit (2026-09-30)

Compared the current Web `TradingAccountTables.tsx`, `TradePage.tsx` and Core order/position DTOs with the client. The mobile layout uses cards and sheets, with the following matching data and interactions:

- Orders: ID, direction/type, margin/position side, limit/average execution price, total/filled/remaining quantity, fill progress, linear order/execution value, settlement asset, fees, reduce-only/post-only flags, time-in-force, creation/update timestamps and status. A product-scoped current-pair filter and last 100 received order updates are available.
- Positions: quantity, leverage, entry/mark price, unrealized/realized PnL, position/maintenance margin, margin ratio, backend liquidation-price snapshot, risk status and linked TP/SL. Account-state leverage snapshots/deltas are merged. The leverage sheet loads the backend settings and validates its range before updating; live account leverage was not changed during acceptance.
- Mark events revalue PnL and equity immediately, including before a risk snapshot arrives. Core positions do not currently provide `instrumentChangeId`; absent revisions use the matching instrument, while explicitly mismatched revisions fail closed. Stale account views hide current PnL. Local PnL is not used to invent maintenance margin, liquidation prices or risk ratios; these remain backend values. Liquidation details refresh after position/balance changes, with request/session/product fences.
- Depth snapshots replace, sort and bound both sides to 20 levels, including empty books. Legacy deltas reject backwards sequence numbers and require a matching previous sequence; gaps trigger recovery. Explicit subscription snapshots establish a new baseline. The full-book sheet supports price aggregation, 10/20 visible levels, cumulative quantities and price-to-ticket selection.
- Recent trades merge REST and WS by trade ID, preserve 64-bit identity, sort by sequence/time/ID, retain 50 rows, and use base-asset units for spot versus contracts for derivatives.

`test/trading_details_test.dart` covers non-empty position/order fixtures, live mark-driven widget repaint, stale and mismatched metadata, leverage pushes/editor validation, terminal order history, depth sequence recovery, aggregation, price selection and 320px light/dark cards. The read-only production public smoke and iOS product-switch test passed again. The supplied production account was empty during the prior authenticated check; real fills, trigger execution and populated-account screenshots remain outside this read-only acceptance.

Trading-detail verification result: `flutter analyze` reported no issues; all 90 unit/widget tests passed. The final iOS simulator app built and launched successfully. Public WebSocket switching/reconnect smoke and the iOS product-tab integration test also passed.

## Account assets / security display audit (2026-09-30)

- Profile links to the asset page. Overview, funding and all six product accounts can be selected independently of the trading instrument/WS subscriptions. The page shows equity, available/frozen funds, valuation currency (USDT/USD/CNY), balance privacy and zero-balance filtering. Removed fixed earn balances, decorative performance data and nonfunctional DEX/earn entries; the transfer/record action opens the existing wallet tools.
- Each trading product has its own valuation readiness. A fresh, fully valued account remains viewable while other products are initializing; the combined total stays unavailable until all required accounts/prices are ready. Funding fetches are separate from derivative services. Expiry/logout, out-of-order wallet responses and disposed requests cannot restore old funding data. Failed history reads do not hide a successful portfolio, and failed FX reads invalidate only the affected rate.
- Security loading begins after dependencies are available, guards session changes, and reports failures separately for MFA, security scenes, keys, KYC, documents, login verification methods, active sessions and login history. Session/history pagination uses backend cursors. Unknown MFA/KYC states are not shown as disabled/unsubmitted. Removed raw server addresses and WS payloads from Profile.
- Login-method binding/modification, session revocation and API IP-allowlist editing are not yet at full Web parity. Existing security mutations have not been exercised against the live account during this read-only audit. KYC submission and key creation are not claimed as end-to-end verified.

`test/account_display_test.dart` covers per-product freshness, wallet/history independence, 320px light/dark account selection/privacy/currency, security partial failures/retry, expired-session responses, wallet response ordering/disposal and FX partial failure. `integration_test/account_display_smoke_test.dart` runs those fixtures on the native runner; it does not imply populated production balances were observed.

`dart run tool/account_readonly_smoke.dart` asks for credentials through hidden terminal input and prints only counts/statuses. The production run authenticated successfully and read MFA, 8 security scenes, 3 login verification methods, active sessions, login history, API keys, KYC/documents and positive USD/CNY rates. Both `/api/v1/gateway/wallet/app/portfolio` and `/api/v1/gateway/wallet/app/orders` returned HTTP 504. Funding totals and records therefore **did not pass live acceptance**; the client displays unavailable/error rather than a fabricated zero. No transfer, withdrawal or security mutation was made.

Verification: `flutter analyze` clean; 98 unit/widget tests passed; all 8 account-display cases passed on the iPhone 17 Pro iOS 26.5 simulator. Android device acceptance and live security mutations remain unverified.

## 现货委托对齐进度（2026-10-19）

本轮只调试 SPOT，其他产品页的完整业务验收仍待逐条完成。Client 增加与 Web 一致的
BBO 对手/同向 1、5 档；限价由服务端提交时确定，发送 priceTicks=0，不用本地盘口假装已确定限价。
市价单只显示 IOC/FOK；限价支持 GTC/IOC/FOK/GTX，Post Only 与有效方式联动。
现货不显示只减仓选项，接入层固定 CROSS/NET/reduceOnly=false；暂停或预交易品种不能提交。
手动取最优价时，买入取卖一、卖出取买一；切换产品/交易对仍由独立页面 key 清空表单。

订单 API 现在解析后端 OrderCommandReceipt.result，避免把回执当订单得到 #0。
MATCHING_PENDING/RESULT_UNKNOWN 记录命令、用户和产品，阻止继续下单/撤单；用户通过
“查询委托结果”读取原产品的命令状态。待确认记录存入已有安全设置存储，冷启动按用户恢复；
确认原命令处理结果或查到匹配的订单才清除，不因一次查询错误解锁，也不重发 POST。
已受理但丢失响应的现货恢复见下节；请求未到达服务端时的负确认和完整真实做市/API/WS 交互
仍需继续完善，不能据此声称现货全功能完成。

验证：新增 spot_order_ticket_test.dart 覆盖四种 BBO 请求、真实本机 HTTP 回执解码、
待确认重复提交保护与存储清除、原产品命令查询、暂停交易、320px 深/浅色表单操作。
回执回归已验证：去掉解码时 orderId 从预期 42 变成 0，恢复解码后通过。
后台资金路径沿用 FUSED：仅运行 CoreSpotAssetUnitsTest，覆盖 4 种碎片成交/快照恢复组合，
包含做市方对手单、买卖冻结、手续费和资金守恒、撤单解冻；未启动其他产品或常驻 Java 服务。
本轮没有真机安装或接入真实全套服务，所有发布声明以实际测试范围为限。

查询路径统一为用户入口 `GET /api/v1/gateway/trading/commands/{commandId}`，与后端返回的
commandResultUrl 一致，修正了原先误用后台路由名导致的 404。路径回归已先复现失败再修复，
`flutter analyze` 无问题、131 项测试通过；真实 FUSED 现货服务已核对回执查询、终态订单和余额接口。
本轮没有原生真机安装或客户端界面连接真实服务的验收。

## 现货余额比例与精度（2026-10-19）

现货表单增加可用余额与 25/50/75/100% 按钮。`spot_order.dart` 使用 BigInt，先取比例预算，
再按数量步长和逐步舍入手续费计算买入量；卖出只使用当前 SPOT 账户的基础资产。
同时遵守 instrument 的最小/最大数量与名义价值。BBO 读取选定方向与档位；市价估算使用
`GET /api/v1/gateway/trading/price-protection` 返回的当前滑点参数。最终准入和资金处理仍由 Core 完成。

`ApiClient.instruments` 从 asset-scales 装配基础/报价资产精度，现货手动价格、最优价、加减步长和
数量转换使用该精度；提交价格保留输入文本，避免 double 中转损失超过 JS 安全整数范围的 ticks。
`spotOrderTerms` 校验用户、产品、instrument/changeId；`AppState` 用会话和交易对版本隔离晚到响应。
缺少必要资料时禁用比例按钮，可点击“刷新下单资料”重取目录、费率及保护参数，不假设零手续费。

`flutter analyze` 无问题，139 项测试通过，覆盖 6/18 位精度、64 位数值、手续费逐步舍入、
BBO/市价保护、资料缺失、切换用户和 dispose 后的迟到响应，以及 320px 深浅色表单操作。盘口点击价格、盘口/订单数量和成交均价也改用真实资产精度。
仅现货使用本轮新的价格精度路径，其他产品仍须逐条验收；本轮没有真机安装或真实成交联调。
详情见 [验证记录](docs/validation/spot-order-sizing-20261019.json)。

## 现货响应丢失后的查询恢复（2026-10-19）

`AppState.placeOrder` 发送现货订单前生成随机 clientOrderId，将请求号、用户、产品和 instrumentId
写入现有安全设置存储；写入失败时不调用下单 API。`PendingTradingOrder` 只表示这份待确认身份，
由 AppState 按用户保存，串行写入设置，避免切换账户或并发设置保存覆盖另一用户的未决请求。
已有命令回执记录在加载时迁入同一集合，没有建立第二份订单状态。

传输中断、超时或无效响应保留锁定；本节最初按原产品和 clientOrderId 读取
`GET /api/v1/gateway/trading/by-client-order-id`。响应必须匹配原用户、请求号、交易对和有效订单号；
404、视图不可用或身份不匹配都保留待确认。有 commandId 时可继续查询原回执，但查询请求自身的
NOT_ACCEPTED 不再被当成原订单拒绝。已受理订单可从 realtime 的活动视图或终态投影恢复，不重发 POST。

`ApiClient` 在连接建立后检查凭证是否变化，旧请求不能借新账户刷新后重发；迟到的刷新结果不能
替换新会话。会话切换或 AppState dispose 后，旧订单响应不修改当前界面。

`flutter analyze` 无问题，147 项测试通过。真实本机 HTTP 用例在接收 POST 后直接断开连接，随后
只用一条 GET 恢复已成交订单；另有冷启动、存储失败、异常响应、查询拒绝、资料不匹配、双用户隔离、
旧刷新和 dispose 的用例。320px 深浅主题实际操作验证下单锁定、404 保留和查到订单后解锁，仍只有
一条 POST。详见 [验证记录](docs/validation/spot-order-response-loss-20261019.json)。

尚未补齐请求从未到达服务端时的负确认机制；此时保留待确认。无订单实体的已提交拒单恢复见下节。
本轮只扩展普通现货下单，没有启动 FUSED 实栈、做市或 wallet，也未进行 iOS/Android 真机安装。

## 无订单实体的已提交拒单恢复（2026-10-19）

`AppState.checkPendingTradingCommand` 先读原产品的 `GET /api/v1/gateway/trading/submission`，验证原用户、clientOrderId、instrumentId 与已知 commandId，TERMINAL 才按命令成功/拒绝解除锁定。即使拒单未生成订单、订单视图还未就绪，也直接使用已提交回执。只有明确 RESULT_UNKNOWN 才继续查询 realtime by-client-order-id；未知、404、503 或资料不匹配仍待确认，不重发 POST。仅有 commandId 的历史记录继续查询 commands，后端也已改读 realtime SQL 投影。

依赖后端先完成数据库迁移、realtime 更新与历史回补，再更新 gateway 和客户端；缺失回执仍不能作原请求的负确认。analyze 无问题，148 项测试通过，包括订单视图 503 时从回执恢复拒单、本机 HTTP 收到 POST 后断开连接，以及 320px 深浅色交互。本轮未安装 iOS/Android 真机、未启动完整 FUSED 栈。详见 [验证记录](docs/validation/committed-command-results-20261019.json)。

## 现货撤单的待确认与恢复（2026-10-19）

`AppState.cancelOrder` 发送现货撤单前，将用户、产品和原订单号写入原 pending 集合；设置存储失败不发送。响应中断、错误或资料不完整时保留待确认，冷启动恢复同一身份，只读 `GET /api/v1/gateway/trading/cancellations/{orderId}` 的 realtime 已提交回执。查询核对原订单及已知命令号；未知或不可用不解锁，也不再次发送 POST。迟到响应不修改另一用户或已 dispose 的界面。

订单列表旁增加“查询撤单结果”，未确认期间隐藏重复撤单操作，确认处理结果后解除锁定，成功时刷新账户；拒绝时提醒检查订单状态。依赖先发布新 gateway，且上一轮 realtime 回执迁移和历史回补已完成。请求未到 Core 的负确认、批量/改单等写入仍待继续验收。

analyze 无问题，155 项测试通过；旧实现丢失撤单恢复身份已复现。新增真实本机 HTTP 接收撤单后断开连接，以两次 GET 恢复，覆盖 64 位订单号；320px 深浅色实际交互验证列表撤单、锁定和结果查询。本轮没有 iOS/Android 真机或完整 FUSED 服务栈验收，见 [验证记录](docs/validation/spot-cancel-recovery-20261019.json)。

## 现货订单行改单（2026-10-19）

现货活动限价单增加“改单”，`spot_amend_order_sheet.dart` 编辑新价格、新委托数量，默认原单剩余数量；`spotAmendmentTerms` 按真实资产精度、步长及交易规则做整数检查，不经 double 转换。新委托数量独立于原单已成交数量，保留原有效方式及 Post Only。

`AppState.amendSpotOrder` 在发送前持久保存随机 clientRequestId、新客户订单号、原订单和交易对，`ApiClient.amendOrder` 补齐原先遗漏的必填请求身份。存储失败不发送；即时结果必须含匹配的已撤原单和有效新单，异常或丢响应保留锁定。冷启动后从 realtime 的 `GET /api/v1/gateway/trading/amendments` 查询原请求，未知或不可用不解锁，不重发 POST；订单列表旁提供“查询改单结果”。确认的是处理结果，最终状态仍按 realtime 账户视图展示。

166 项测试通过，analyze 无问题，包括 320px 深浅色表单、冷启动、存储失败、迟到响应/账户切换/dispose、64 位新单号，以及真实本机 HTTP 的必填字段/两张订单解码和丢失响应后的 POST+GET+GET。遗漏 clientRequestId 的回归已先复现失败。先更新 gateway，且此前 realtime 回执迁移、导出及历史回补已完成；本轮未安装 iOS/Android 真机、未启动完整 FUSED 栈，批量和其他产品继续验收。见 [记录](docs/validation/spot-amendment-20261019.json)。

### 现货全部撤单与恢复（2026-10-19）

当前委托面板增加“撤销当前交易对委托／撤销全部现货委托”，沿用“仅当前交易对”筛选，提交前显示明确范围。`AppState.cancelOpenSpotOrders` 从 realtime 一次取得完整固定目标，安全保存订单 ID、每批键和发送断点后以原生 50 笔分批；`ApiClient.cancelOrderBatch` 显式传递必填 batchKey。部分失败显示成功/失败计数，可查看失败订单及原因。

断网、空/不匹配回执与服务不可用保留“确认并继续撤单”；重启恢复时 GET 已发送批次，确认后才提交原计划尚未发送的后续批次，不重发原批、不加入新委托。初始或进度存储失败停止发送，换账户停止旧账户后续批次，结果只对所属账户显示。订单和资金状态仍以 realtime 为准。

依赖后端 SQL 迁移、realtime 更新及必要的旧批次逐项结果回补，然后发布 gateway 与两端。本轮没有安装原生 iOS/Android 或重跑完整 FUSED 服务栈；旧底层直接 cancel-open、批量下单/改单、其他产品 UI 仍待逐项验收。见 [验证记录](docs/validation/spot-bulk-cancellation-20261019.json)。

现货 FUSED 实链路补充：可选 `test/spot_fused_live_test.dart` 使用真实 AppState、HTTP 和 WebSocket，在真实做市下处理 52 笔委托。网关处理首批后丢弃响应、暂停本轮 realtime 产生真实 202；恢复并重建 AppState 后原键保留，总共两次不同批次 POST，51 成功/1 已结束，最终真实盘口存在且私有冻结为零，320px 暗色面板可看失败详情。测试注入内存设置/SessionStore 以在 host Flutter 测试中运行；没有安装 iOS/Android 设备。

实栈用例只在设置 `SPOT_FUSED_LIVE_FIXTURE` 和 `SPOT_FUSED_REALTIME_PID_FILE` 后运行，需要后端 `SixProductLineContractLiveTest` 的四分钟交接窗口，并校验 PID launcher identity。命令为 `flutter test test/spot_fused_live_test.dart --reporter expanded`；普通全量回归默认跳过该用例。后端复现流程见 `docs/realtime-command-results.md`，本仓库 [实测证据](docs/validation/spot-fused-clients-20261019.json)。

### U 本位交割结算中减仓（2026-10-19）

`ApiClient.linearDeliveryInstruments` 与 `AppState.refreshInstruments` 保留结算中交割合约的完整元数据，目录失败不发布半份结果。SETTLING 仅允许直接减仓；提交前核对当前持仓、方向、保证金模式和数量，HEDGE 平仓显式 reduceOnly。320px 深浅色票据显示对应平仓方向，距到期使用 expiryTime。

单笔下单和撤单沿用已有安全设置持久化原请求；保存失败不发送，丢失响应或重启后只 GET realtime 原提交/撤单结果，错误回执不解锁。先发布 price 的 SETTLING 指数源修复与 gateway 的合约公开查询、realtime 杠杆读取修复，并保留此前 realtime 回执迁移与导出。

可选 `test/linear_delivery_fused_live_test.dart` 需要 `LINEAR_DELIVERY_LIVE_FIXTURE` 和 `LINEAR_DELIVERY_REALTIME_PID_FILE`；未设置时普通回归默认跳过。它在后端四分钟交接中接续 Web，使用真实 AppState、HTTP/WS 和测试设置/SessionStore，平剩余一张持仓并检查断响应、暂停投影、重建状态及只读恢复。该 host Flutter 测试不等于安装原生 iOS/Android，也未验证实际到期交割结算或其他产品全部流程。

`ApiClient.instruments` 只返回查询结果，合并目录由 AppState 在校验全部请求后统一发布，异步请求中也不短暂替换为不完整目录；已有回归覆盖合并期间的目录一致性。验证记录见 [U 本位交割实测](docs/validation/linear-delivery-trading-20261019.json)。

U 本位与币本位交割结束后，客户端目录刷新会按已选合约的明确 ID 读取 CLOSED 元数据并保留历史查询；该状态禁止所有新委托。交易页可进入“交割现金流水”，默认沿当前产品线查询既有产品账本 API，固定 DELIVERY_SETTLEMENT 类型。流水展示实际现金变动、合约身份和变动后余额，金额按币种精度使用整数计算。它不包含零现金变化的交割报告。320 宽度的深浅色测试及可选本地 FUSED 真实读取测试分别位于 test/delivery_ledger_test.dart 和 test/linear_delivery_expiry_live_test.dart；后者要求明确的隔离 QA 用户及合约环境变量，原生 iOS/Android 设备尚未在本轮验证。

币本位交割与 U 本位共用交割状态策略和单笔持久请求恢复；目录按当前产品线完整刷新，CLOSED 元数据按明确 ID 保留查询。币本位生命周期面板按报价币种显示每张固定面值，现金记录按 BTC 精度展示实际交割变动。两条交割的政策、方向/保证金/数量保护及 320 深浅色测试均参数化覆盖。可选真实测试仍使用 LINEAR_DELIVERY_LIVE_FIXTURE / LINEAR_DELIVERY_REALTIME_PID_FILE，另以 DELIVERY_LIVE_PRODUCT=INVERSE_DELIVERY 指定产品线；到期读取用 DELIVERY_EXPIRY_PRODUCT 指定，并传入隔离 QA 用户与合约。测试记录见 docs/validation/inverse-delivery-trading-20261020.json，Flutter 主机验收不等于 iOS/Android 真机验收。


### 期权交易与现金行权（2026-10-20）

期权沿用 Web 的全额权利金语义，票据去除杠杆按钮并按真实资产精度展示买入权利金及手续费、卖出权利金扣费后金额；卖方保证金由 Core 风险核定。费用资料绑定用户/产品/合约/配置版本，过期或不匹配不显示猜测金额。BBO 使用所选侧和档位。标的按显式 instrumentId/productLine 匹配，期权链按标的身份及精确到期时刻分组；行权价依 quoteScaleUnits 格式化，不假设 1e8。

移除按价内外猜测 Delta，Greeks/IV 后端定价尚未实现，显示暂无可信报价。期权只允许未到期 TRADING，CLOSED 仍按 ID 保留查询；单笔下单/撤单在发送前持久保存，响应不明只查询原 realtime 回执，重建状态不重发。减仓检查当前持仓方向、保证金模式及数量。`option-exercise` 记录只读 OPTION 产品账本的 OPTION_EXERCISE，呈现真实现金、余额和合约。

实际仅运行 OPTION 单节点 FUSED，Web 买一张、Flutter 平仓，丢真实响应、暂停本轮 realtime 后保持未知，再恢复并重建 AppState 查询原结果；每个意图只有一次 POST。真实六组 CALL/PUT 到期与 320px 深浅主题现金记录验证完成。先部署后端单位换算、realtime 行权分类并执行必要旧数据分类迁移。没有声称 iOS/Android 真机安装、完整 Greeks 定价或生产验收。[验证及清理记录](docs/validation/option-trading-20261020.json)。


### 期权行情与参考估值、公开手续费版本（2026-10-20 后续）

两端已接入 realtime 的期权参考接口 `/api/v1/gateway/candlestick/options/quote`，展示真实权利金、标的指数、同到期远期价及零贴现 Black-76 参考 IV/远期 Delta/Gamma/Vega/每日 Theta。模型与每1单位标的的口径明确显示，缺失/过期/越界不造数；它不替代账户风险或结算。HALT 中有新鲜源数据的未到期合约仍可查询，下单限制保持独立。

期权链现在可直接切换 CALL/PUT，按标的身份、精确到期时刻及币种分组，使用整数行权价并保留同价多合约。Web 补齐320px已登录页头、语言菜单与主题交互。另修复公开有效手续费的版本名：返回 changeId，与公开合约精度版本一致，client 不再依赖被网关删除的 instrumentChangeId；Web 现货费用版本校验同步使用公开 changeId，缺失或旧字段仍拒绝。未放开脱敏、未添加猜测费率。

发布需配套 realtime、gateway 与两端；本轮没有 SQL 或 Core 资金/撮合/协议变更。参考模型仅为明确的零贴现欧式现金模型，不提供完整利率曲线或组合 Greeks；原生设备安装及其他产品本轮实栈不在验收范围。[验证与清理记录](docs/validation/option-market-reference-20261020.json)。


### 期权原子 TP/SL 与原请求恢复（2026-10-20 后续）

client 期权“高级委托 → 条件单”补齐 TP/SL 双腿 OCO，支持选择标记价/最新成交价/指数价，以及各腿触发后市价或限价执行。价格按真实资产 scale/tick 换算，单条条件单也使用永久 instrumentId。OCO 先保存原身份，再一次提交两腿；丢回包、刷新或重建只查询原 realtime 已提交回执，不自动重发。停牌、关闭、方向不符及超出持仓数量均拦截。client 活动条件单展示真实触发源、OCO 标记和执行方式。

Web 同步保存 OPTION OCO 原身份并复用结果确认入口。TP/SL 票据不显示普通开仓权利金，费用标记为“触发成交时计算”。后端新增只读 oco-submission 查询，复用现有回执表及 realtime exporter，不访问在线 Core。本轮无新 SQL 或 Core 交易/资金模型变更，发布需配套 gateway 与两端，并确保此前回执迁移和导出已就绪。

实际仅运行 OPTION 单节点 FUSED：Web 双腿一次提交、丢响应刷新恢复后撤销；client 双腿一次提交、暂停 realtime 后未知、恢复并重建读取原结果，止盈腿触发限价平仓且另一腿撤销。当前及前一次隔离账户持仓/冻结归零、资金差额0。320px 深浅色及停牌费用文案验证通过；其他产品、独立条件单恢复、原生设备和生产发布仍需继续。[验证与清理记录](docs/validation/option-protection-20261020.json)。


### 期权独立条件单与撤销恢复（2026-10-20 后续）

独立条件单在发送前按账户保存原 clientTriggerOrderId、OPTION 产品和 instrumentId，撤销保存原 triggerOrderId。
丢包、超时、响应不匹配或确认结果保存失败，均保留待确认；重建 AppState 后仅 GET realtime 原回执，不重新 POST。
初始存储失败不发送；账户变化不继续发送或显示旧账户结果。多档顺序提交，遇到未知结果停止后续档位；已发档位移出草稿，未发送的保留。
待确认时交易与条件单撤销均禁用，使用已有“查询委托结果”入口确认后再决定后续操作。

配套 gateway 提供 trading-trigger/submission 和 trading-trigger/cancellations/{triggerOrderId}，沿用既有回执投影与导出，无新 SQL。
其他产品及批量条件单撤销仍需逐项验收。可选 test/option_single_trigger_fused_live_test.dart 需要 OPTION_SINGLE_LIVE_FIXTURE，
仅用于隔离 OPTION FUSED 交接；主机 Flutter 验证不等同于原生 iOS/Android 安装。实测与清理见 docs/validation/option-single-trigger-20261020.json。


### U 本位交割条件单与 OCO（2026-10-20）

U 本位交割“高级委托 → 条件单”补齐 TP/SL 双腿 OCO，并与独立条件单、单笔撤销共用现有持久身份和 realtime 结果确认。
双腿仅一次原子 POST；丢回包、重建或确认结果保存失败保留原请求，只 GET，不重发。已发送的双腿移出新草稿，
方向、数量、ISOLATED/CROSS 与 LONG/SHORT/NET 必须匹配当前永久合约 ID 的仓位。支持实际资产精度和 MARK/LAST/INDEX。

条件单需要未到期 TRADING，缺少到期元数据或进入 SETTLING/HALT/CLOSED 时禁止创建。
SETTLING 中的直接减仓和原请求查询继续可用，不能用直接平仓的准入判断放行条件单。
ApiClient 与界面沿用已有产品映射，尚未接入其他产品的持久条件单恢复；没有扩展永续功能。

可选 test/delivery_protection_fused_live_test.dart 使用 DELIVERY_PROTECTION_LIVE_FIXTURE 和 DELIVERY_PROTECTION_PRODUCT=LINEAR_DELIVERY，
配合后端 SIX_LINE_LIVE_DELIVERY_PROTECTION=true，在同一隔离 FUSED 仓位上验证交易中触发减仓和结算中最终直接平仓。
主机 Flutter 的设置/会话适配器不代表原生 secure-storage 或真机安装验收。需配套既有 gateway 回执接口及 realtime 导出，
无新 SQL；实测及清理见 docs/validation/linear-delivery-protection-20261020.json。


### 币本位交割保护委托恢复（2026-10-20）

币本位交割条件单与 OCO 现复用交割/期权的原身份持久恢复：发送前保存账户、产品、永久合约 ID 和双腿身份；
未知响应或确认结果保存失败时只查询 realtime，不自动重发。两类交割的共同测试为 test/delivery_protection_test.dart，
分别验证报价币精度与结算币精度、ISOLATED/LONG、原 64 位撤销身份、重建恢复及 320px 深浅色。

共享实栈用例 test/delivery_protection_fused_live_test.dart 需要 DELIVERY_PROTECTION_LIVE_FIXTURE、
DELIVERY_PROTECTION_PRODUCT=INVERSE_DELIVERY（或 LINEAR_DELIVERY），一次只接入一个隔离 FUSED 产品。
币本位的可用资产/资金对账使用 BTC，触发价仍按报价币精度换算；SETTLING 禁止新条件单，原结果查询和直接减仓保持可用。
本轮无 Core 资金模型或 SQL 变化，不包含永续扩展、原生 secure-storage 或真机安装验收。
实测与清理见 docs/validation/inverse-delivery-protection-20261020.json。

币本位行情由 realtime 修正面值换算与 SETTLING/CLOSED 成交接收；重启后的当前大周期由已关闭分钟聚合恢复。
旧分钟投影需受控重建；本轮只处理隔离 QA 数据，无线上数据操作。只读实栈 test/inverse_delivery_market_live_test.dart 使用 INVERSE_MARKET_LIVE_ROOT，
核对三笔原始成交、BTC 基础币量、报价币成交额及 Core 暂停时的 1m/4h 查询。


### 现货委托确认资料保存失败（2026-10-20）

`AppState._writeSettings` 沿用现有串行设置写入，将已确认的原请求排除出本次持久记录，写入成功后才解除内存锁定。下单、撤单、改单、原结果查询与已完成的批量撤单统一遵循此顺序；成功或明确拒绝后若保存失败，保留原身份并提示查询，不再 POST。保存期间的主题写入不会重新写回已清除的请求；其他用户的记录保留。已完成批量计划在重建后只完成资料清除，不重复撤销任何一批。

本轮只调试现货恢复与交互，共享设置路径另由全量 Flutter 测试覆盖。320px 深浅主题通过实际滚动和点击验证，离屏点击会使测试失败。未启动后端、wallet 或原生设备，未重新进行 FUSED 成交/资金守恒验收；此前实栈记录不能替代本轮新增边界。命令、复现和清理见 [验证记录](docs/validation/spot-confirmation-storage-20261020.json)。


### 现货历史委托与本人成交（2026-10-20）

现货交易页直接进入已有记录页的历史委托或成交记录，并按“仅当前交易对”带入永久 instrumentId。`ApiClient.accountRecords` 的 trade 类别改用 `/api/v1/gateway/trading/trades`，校验本人账户/产品、完整执行和分页，传递时间边界及原游标。记录页按真实 base/quote scale 解释 step/tick，展示本人订单号、成交号、方向、Maker/Taker 及当时费率，不展示对手资料；未知资产精度显示缺失，不造数。价格和数量不再固定 8 位精度，成交类别不显示不适用的币种/状态筛选。

配套 gateway 新路由以及已有 realtime 成交投影须先就绪；验证记录为 docs/validation/spot-private-fills-20261020.json。可选 test/spot_trade_history_fused_live_test.dart 需要显式 SPOT_FILLS_LIVE_FIXTURE（隔离 FUSED 用例生成、位于 `/tmp/surprising-spot-fused-fills-` 下）及 SPOT_FILLS_CORE_PID；只暂停一次已加载的查询并恢复本轮 Core，默认回归跳过实栈连接，不能指向其他运行环境。


### 现货历史委托分页、筛选与展示（2026-10-20）

历史委托继续从 realtime 已提交的订单投影查询。状态 FILLED/CANCELED/REJECTED 在 SQL 分页之前过滤；按更新时间及订单号倒序翻页，响应 sort 修正为 updatedAt.desc，起止日期仍按创建时间且含两端。Web 两处入口保留游标与原账户/产品/筛选，桌面和手机共用只读历史展示；client 固定已应用查询，编辑草稿不会把新条件与旧游标混页。两端保留大订单号、实际 tick/step/资产精度和小数 tick 均价，展示成交量、剩余量及原累计手续费；client 对不在交易目录的历史合约按永久身份取资料。

需配套发布 gateway、Web、client；无新表、迁移、topic 或 Core 交易状态变化。实栈一次只运行 SPOT、FUSED，不启动 wallet。隔离脚本分别为 Web 的 scripts/spot-order-history-fused-live.mjs、client 的 test/spot_order_history_fused_live_test.dart，显式传 SPOT_HISTORY_LIVE_FIXTURE（/tmp/surprising-spot-fused-history- 下、Maven SIX_LINE_LIVE_USER_HISTORY=true 生成）；Web 可用 SPOT_HISTORY_PLAYWRIGHT_MODULE / SPOT_HISTORY_CHROMIUM 指定已有浏览器。脚本只把真实 GET 的 limit 降为 1 以验证分页，不生成金融响应或提交交易。实测与清理见 docs/validation/spot-order-history-20261020.json。


### 现货当前委托的精确价格与价值（2026-10-20）

Web `TradingAccountTables` 与 client `OrderRow` 的现货价格/均价显示复用整数十进制换算，保留大于 JS 安全整数的原 tick 与小数 tick 均价。现货委托价值按 priceTicks × quantitySteps × notionalMultiplierUnits，成交价值按原 executedValueTicks × notionalMultiplierUnits，以真实报价币 scale 展示。原累计手续费直接显示，不使用平均价或最新费率反算；市价单不猜限价价值，缺少乘数/执行累计值时保持缺失。现货明确显示“计价币种”和 Post-only，隐藏不适用的全仓/逐仓、持仓方向与 reduce-only 文案。Web 小屏现货操作列随表格滚动，避免固定按钮遮住长价格和金额。

本轮为展示层修复，无 API、realtime、Core 交易或资金模型变化，无迁移/topic/新服务；未启动后端、wallet 或其他产品实栈。Web 只读展示验证脚本 scripts/spot-order-details-qa.mjs 使用显式 SPOT_DETAILS_QA_ROOT（/tmp/surprising-spot-details- 前缀、owner.json 标识本轮 QA）及可选 SPOT_DETAILS_QA_BASE、SPOT_DETAILS_PLAYWRIGHT_MODULE、SPOT_DETAILS_CHROMIUM。它挂载真正生产组件及显式整数测试数据，不拦截金融 API 响应；不代表本轮真实 FUSED 成交/资金对账。证据与清理见 docs/validation/spot-current-order-details-20261020.json。


### 现货交易面板默认视图与账户隔离（2026-10-20）

client 现货默认打开当前委托，隐藏持仓入口和保证金风险摘要，保留止盈止损/策略、历史委托与成交记录；同一面板切换账户或产品后重新选择适用的默认页签。两端现货登录提示改为账户与委托。

Web 最近订单更新曾在直接切换已登录账户时保留前一账户缓存。现按账户、登录状态、产品及永久 instrumentId 重新挂载面板，清除页签、筛选、订单更新与风险局部状态；仅收录根事件 userId 属于当前账户、channel=orders 且产品匹配的更新，跳过无订单号的空事件。现货不再展示持仓页签，衍生品入口保留。

本轮只调试现货界面与状态隔离，无 API、realtime 或 Core 逻辑改动，无迁移/topic/服务新增；查询继续使用既有 realtime 路径。未启动后端、wallet 或其他产品实栈，不能据此宣称新的 FUSED 成交/资金对账通过。scripts/spot-order-details-qa.mjs 新增账户、退出登录、交易对往返、错误产品事件与页签切换回归，沿用既有 SPOT_DETAILS_QA_ROOT / SPOT_DETAILS_QA_BASE / SPOT_DETAILS_PLAYWRIGHT_MODULE / SPOT_DETAILS_CHROMIUM 参数。受控真实组件验证、原生 widget 覆盖与资源清理见 [验证记录](docs/validation/spot-trading-panel-scope-20261020.json)。

### 现货算法委托查询与精确展示（2026-10-20）

现货账户刷新、打开策略页签、重连后的账户刷新和“刷新策略”按钮均通过既有 `/api/v1/gateway/trading/algo/open` 读取 realtime 提交投影。仅当前交易对时按永久 instrumentId 查询，取消筛选后查询本产品的全部未完成策略；最多取 1000 笔并在达到上限时提示筛选。查询失败、初始化中或数据校验失败有独立错误提示，不显示为成功的空列表，不改用 Core 查询。

`AlgoOrderModel` 保留用户、产品、永久合约及 int64 父子单身份，校验类型、状态和累计数量。列表按真实 tick/step 与币种 scale 精确显示价格、已成交、挂单中和每片数量，不再把挂单量计为成交。目录中不存在的合约按永久 ID 补读资料，只保存在本次策略查询的资料表中，不加入可交易目录；资料失败时明确留空。现货行隐藏保证金/持仓方向文案，取消中与终态确认分开显示。

算法查询、账户刷新和普通委托分页分别维护请求编号；切换账户、产品、合约、筛选或释放状态后，旧响应不会写入当前列表。撤销锁定原用户/产品/父单，阻止并发点击，核验返回身份和状态；已确认响应使此前在途列表查询失效，避免旧列表重新显示刚撤销的父单。取消中可显式继续撤销同一父单。

本轮补齐策略读取、展示和既有父单撤销交互。现货 TWAP/冰山创建入口与原创建请求恢复仍需继续实现，未认定算法委托全生命周期完成。验证使用真实 Dart HTTP 适配器的本地契约样本、生产状态逻辑和 320px 深浅主题 widget；本轮未启动后端或真机，不代表新的 FUSED 成交/资金验收。完整结果及资源清理见 [验证记录](docs/validation/spot-algo-orders-20261020.json)。

## Android 真机预览安装（2026-10-20）

已按用户要求在华为 LIO-AN00（Android 12 / API 31）安装并启动 `1.0.0-preview.20261020`，包名 `com.surprising.surprising_client`。使用现有 debug 签名构建 release APK，仅供本次预览；连接 `ex-api.tokdou.com`。真机首页显示 BTC、ETH、SOL 行情；没有登录或提交交易。当前线上仅有 3 个 U 本位永续交易对，其他产品保持真实空状态。334 项 Flutter 测试通过、10 项需隔离实栈的测试默认跳过，analyze 无问题。

打包需允许 Flutter 完整生成平台文件，不使用 `--no-pub` 复用旧的测试插件注册文件；测试与原生打包顺序执行。构建使用 JDK 21、Gradle 最大堆 1536MiB 与 2 workers。现货算法创建仍属开发中内容，本次安装不代表其完整 FUSED 或真机交易验收，详见 [安装证据](docs/validation/android-device-preview-20261020.json)。

## Android 下单区与产品入口调整（2026-10-20）

根据真机反馈，最优价按钮移到 BBO 行，价格输入使用完整下单区宽度；明确加减按钮的占位，收紧输入框、买卖切换和提交按钮。数量单位移到标签，数字按可用空间调整字号，保留完整输入内容和键盘编辑。移除重复的“交易产品页”入口及专用弹层，顶部产品线切换继续负责产品隔离和重新加载。

`flutter analyze` 无问题，347 项测试通过、10 项隔离实栈测试默认跳过。新增 13 项布局/操作回归覆盖 320/392/430 宽度、深浅主题、正常及 1.3 倍字号、最优价/加减/键盘输入；更新既有顶部六产品切换回归。已将 `1.0.1-preview.20261020` 覆盖安装到华为 Android 12，真机确认完整价格与入口移除，登录状态保留，没有在用户手机提交交易。原始多产品功能目标及现货算法创建模块仍在继续，详见 [验证记录](docs/validation/android-trade-ticket-layout-20261020.json)。

### 个人设置、行情跳转与资产页（2026-10-20）

首页头像进入个人设置，沿用已实现的绑定、安全、设备和认证；所有产品统一从交易进入，保留所选产品，原合约导航位改为 C2C。K线图标进入独立行情页。资产默认总览、账户切换上移、三操作同行、划转独立页面；资金/现货共享余额只计一次。未开启产品只接受后台显式状态，不以失败猜零。353 项测试与 Android 预览验收范围、测试服务器尚未发布的边界见 [验证记录](docs/validation/mobile-navigation-assets-20261020.json)。C2C 完整业务继续开发。


### 生物解锁进入验证（2026-10-20）

已开启生物识别时，冷启动自动调用系统验证，验证成功后才恢复保存的登录。已登录账户从后台返回同样自动验证；锁屏位于导航容器上方，遮住个人页面、交易页面及已打开的弹窗，并阻止点击和焦点进入。系统验证自身的 inactive/resumed 切换不会重复弹出验证，取消或失败保留锁屏和手动重试，也可退出原登录并使用账号密码登录。应用在后台收到的验证结果不能直接解锁。

后台切换沿用当前会话及原交易意图，不额外提交交易或重复刷新登录；登录过期、退出和销毁会使旧验证结果失效。已有支付、提币和安全操作的服务端验证要求保持各自业务规则。此修复只更新客户端，不需要重启服务器；C2C 开发和此前暂缓的服务器发布继续保留。主机测试覆盖 18 项生物识别场景与 320dp 深浅主题、大字号，全量 371 项通过、10 项隔离实栈默认跳过，analyze 无问题。Android 安装及系统验证观察范围见 [验证记录](docs/validation/biometric-unlock-20261020.json)。

## 六产品线原请求恢复（2026-10-21）

普通单笔下单/撤单与条件单原身份恢复统一覆盖六产品，Web 专用衍生品平仓也沿用普通订单的原请求回执。发送前持久化，未知结果阻止重复提交，重启/刷新后查询原用户、产品和请求；存储失败不发送。客户端持仓 OCO 用于五条衍生产品，不向现货余额显示衍生仓位保护表单。

本轮受控浏览器、组件、真实 AppState 和静态检查的证据见 [恢复验证记录](docs/validation/product-recovery-20261021.json)。测试响应为显式契约样本，不代表本轮真实资金、全部产品 UI 或原生设备已验收；服务器发布继续暂缓。全平台剩余范围见后端 `docs/product-completion-20261021.md`。

价格精度补充：全部产品使用实际报价精度和原始价格文本校验、下单，拒绝无精度及不符合步长的价格。BBO、盘口回填与加减价使用整数/BigInt，参考价格换算避免 int64 乘法溢出。六产品真实本机 HTTP 验证 18 位小数的价格整数，320px 深浅色组件覆盖最优价和加减价末位；这些是本机契约与组件验证，不代表本轮真实 Core 成交或手机安装。

### 强平历史的已提交读视图（2026-10-24）

强平列表读取后端当前`liquidationOrderId`、`instrumentId`和整数数量步数，不再依赖不存在的symbol字段或旧orderId别名。页面按当前产品与标的身份查找合约，复用交易数量格式化；资料未就绪时明确提示，不把原始步数当作数量展示。

投影未就绪的503和格式错误向现有账户错误状态传播，不返回伪造空历史；失败保留上次成功记录，平行账户读取完成后仍保留本次强平错误。已就绪且orders为空才显示真实空历史。当前任务只做Flutter bundle/kernel编译及回归场景源码编译，未运行测试、模拟器或iOS/Android交互。
