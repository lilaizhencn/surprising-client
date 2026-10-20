# C2C 本地交易业务验收

入口：`lib/src/c2c_trading_page.dart`。本轮已接入商家质押、广告、报价及订单业务；与原订单聊天共用交易鉴权和行情 WebSocket。

详细业务边界、迁移要求和真实 Core 资金验证见后端 `surprising-ex/docs/c2c-business-live.md`。本项目验证摘要见 [本轮记录](validation/c2c-business-live-20261020.json)。

Web/客户端在响应未知时保留原请求号并查询原回执；后台敏感操作保留权限、审计和双人审批。测试中的身份认证、验证码和站外付款为隔离模拟，不代表真实法币支付验收。本轮未发布服务器或安装新 APK。
