# CFS iPad

《绝地潜兵2》战备呼叫工具的 iPad 客户端：在 iPad 上点选/滑动战备指令，通过局域网 TCP 发送到 PC 端服务器模拟按键。移植自 [WisteFinch/Helldivers2CallForStratagemsOnPhone](https://github.com/WisteFinch/Helldivers2CallForStratagemsOnPhone)（安卓端，MIT 许可），对接其自带的 Rust 服务器（API 6），服务器零改动。

**开发计划、进度与全部技术决策见 [PLAN.md](./PLAN.md)（交接入口，先读它）。**

## 构建与安装

- 本仓库不需要本地 Mac：push 后 GitHub Actions 自动出未签名 IPA（Actions 页面 Artifacts 下载）。
- Windows 上用 [Sideloadly](https://sideloadly.io/) + 免费 Apple ID 签名安装到 iPad，7 天续签（详见 PLAN.md 第 5 节）。

## 许可

MIT，衍生自 WisteFinch 的原项目，保留其版权声明（见 [LICENSE](./LICENSE)）。
