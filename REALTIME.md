# 实时订阅 / Realtime subscriptions

公共和私有数据使用两个 WebSocket。私有连接先发送 authenticate，收到 authenticated 后才发送订阅。更新令牌、重连和退出登录会丢弃旧连接状态；旧连接回调不能更新新会话。令牌不出现在 URL。

Public and private data use separate connections. Private subscriptions wait for authentication; session changes and reconnects reset the baseline. Tokens are not included in URLs.

首页和行情默认展示 U 本位永续，行情页可筛选其他产品；交易页按六产品各自的 symbol 订阅成交、深度、K 线，衍生品同时订阅 mark/index，永续订阅 funding。订阅集合变化时退订旧项。现货 bookTicker 提供资产折算，六产品实际持仓驱动额外 mark 订阅。价格缓存按 productLine + symbol 隔离。

Home and markets default to U-margined perpetual instruments; the market page can filter other products. Trading streams are isolated by product and symbol, and subscriptions are reconciled when selection changes. Spot book tickers support conversion; actual positions drive extra mark subscriptions.

登录后订阅六产品的 accountState/orders/triggerOrders/positions/positionRisk/executionReports。取消 matches。每个产品有独立 PrivateView；先按 version 合并绝对值事件，再刷新 UI，不因 UI 节流而丢掉私有状态。snapshot 的版本栅栏保留较新增量；终态墓碑防止旧事件复活。周期完整快照修复丢包，超过 15 秒或非 READY 不展示当前资产估值。

Six product views merge versioned absolute entity updates before notifying the UI. Snapshot fences preserve newer updates and terminal tombstones; periodic snapshots repair gaps. Expired or unavailable snapshots hide current valuation. Private push events do not cause REST balance, position or open-order queries; wallet, ledger, algo and liquidation history remain separate explicit queries.

OPEN 订单保留，其他终态移除；触发单保留 PENDING/TRIGGERING；零持仓移除、零余额保留。新 depth 的 levels 是完整盘口替换快照，包括空盘口。迟到的 REST 行情响应不能覆盖更晚的推送。

Open orders and active triggers remain; terminal entities and zero positions are removed, while zero balances remain explicit. Depth levels replace the complete bounded book. Late REST results cannot overwrite newer streamed market data.

资产总览汇总六产品，不再只统计当前交易产品。权益为余额 available + locked 加浮动价值：线性合约加入未实现盈亏；期权加入已支付权利金之后的带方向市值；不再次加入 realizedPnl。反向合约需要明确的 settleScaleUnits 才本地计算，否则使用 Core positionRisk 推送的盈亏。缺少 instrument 版本、标记价或风险数据时显示同步中。整数计算避免中间浮点误差。

Assets cover all six products. Equity adds floating value to cash without double-counting realized PnL. Options use signed market value. Local inverse valuation requires explicit settlement scaling; otherwise Core risk PnL is authoritative. Missing inputs prevent a current valuation display.

验证：`flutter analyze`、`flutter test`，包含真实本地 WebSocket 的认证和退订测试。协议测试不能替代部署环境中完整推送链路联调。

Validation includes analyzer, unit/widget tests and a local WebSocket handshake test; it does not replace deployment integration testing.

## Web parity (2026-09-30)

当前 REST 和 WS 以 `instrumentId` 为合约标识。App 保留 symbol 作为展示字段，通过 instrument 元数据按产品映射请求、订阅和返回事件；订阅键包含 instrumentId，防止同 channel 不同合约相互覆盖。首页和行情默认展示 U 本位永续，与当前 Web 一致；行情列表成交订阅独立于交易页的 depth/candles/mark/index/funding 订阅，产品切换会替换后者。

最近成交使用 `/api/v1/gateway/candlestick/trades/recent` 快照并合并 WS trades，按 tradeId 去重、sequence 降序保留 50 条。空深度仍替换盘口，较晚返回的历史行情不覆盖更新的成交价。行情不再显示模拟涨跌幅、成交量、资金费率或倒计时。

## 产品切换和私有数据复核（2026-09-30）

交易页顶部六产品 Tab 可横向滚动。产品和合约选择作为一次操作更新，立即清空旧盘口、K 线和成交，替换公共订阅，再重新加载分页 instrument 元数据和当前产品的数据。异步返回按选择版本隔离；无合约的产品保留空页面，不能借用其他产品的下单参数。切换 K 线周期立即退订旧周期并清空旧图。

持仓和 positionRisk 以 `instrumentId + positionSide` 匹配，与后端一致；marginMode 不是实体身份。保证金模式变化替换原持仓，零持仓同时移除风险。accountState 未携带 positionMode 时保留已知持仓模式。撤单和撤销条件单的迟到响应不能改写新产品的列表；平仓其他合约保持当前行情选择不变。退出登录清空所有产品私有快照及估值。

线上公共复核脚本：`dart run tool/public_realtime_smoke.dart`。本次已验证三个已配置永续合约的真实订阅/退订确认、K 线周期切换和重连。其他五产品目前没有线上可交易 instrument，完整产品数据隔离使用本地协议回归覆盖。线上非空持仓及真实订单执行/触发事件仍须独立验证。

专用账号只读复核：登录、私有认证、36 个订阅确认成功；U 本位永续返回 READY 的周期快照，持仓/活动委托/活动条件单均为零，与 REST 一致。其他产品为 INITIALIZING，账户 REST 返回 404，App 不把它们视为已同步的空账户，因此跨产品资产总览仍可能显示同步中。空闲账号本次未产生私有增量事件；非空持仓、成交、撤单和条件单触发由协议回归覆盖，未提交真实交易。断线重连后重新认证、36 个订阅和永续新快照恢复成功。复核工具 `dart run tool/private_realtime_smoke.dart` 在终端隐藏输入账号密码，不保存凭据。
