# QuotaRoom v2.0.0 — 额度洞察与系统集成

一次功能大版本：把额度预测、预算、提醒、Key 明细和 Android 系统能力补齐。包名不变（`com.starrycognet.quotaroom`），可直接覆盖安装 v1.2.0。

## 额度与预算

- 配额卡新增消耗节奏（已用 % ÷ 已过时间 %）、预计耗尽时间与「将在重置前耗尽」提示。
- 设置页新增每日预算，首页显示预算进度、已用 / 剩余 / 超支金额。
- 额度剩余 ≤20% / ≤10%、每日预算达到 80% 或超支时发送本地通知，按重置窗口 / 自然日去重。

## 用量洞察

- 统计页新增「较上一周期」对比：费用、Token、请求数及涨跌幅。
- 新增「模型 × Key」组合排行，展示 Token、请求数与费用。
- 新增「最贵请求 Top 5」，按单次费用排序，显示模型、时间与 Key。

## 记录与 Key

- 记录页新增搜索（Session / Key / 模型）、7 天 / 30 天 / 全部时间筛选。
- Key 用量卡片可点按直接下钻到该 Key 的使用记录，并显示 7 日 sparkline。
- 列表保留无限滚动，滚动到底自动加载。

## 系统集成

- 新增 Android 桌面小组件：5h / 周 / 月额度、今日费用与 Token、最后更新时间，点按打开 App。
- 新增 WorkManager 后台同步（最短 15 分钟），App 关闭时也会同步、更新小组件并触发提醒。
- 新增应用长按快捷方式：立即同步、查看统计、使用记录。
- 设置页新增「检查更新」，读取 GitHub 最新 Release。

## 数据与外观

- 新增使用记录 / Key 汇总 CSV 导出、SQLite 数据库备份、从备份合并恢复、文本用量摘要分享。
- 新增同步日志（最近 30 条，界面展示最近 5 条），后台同步也会记录。
- 新增 AMOLED 纯黑主题；修复全新安装时同步范围默认值错误。
- 版本 2.0.0。

## 安装

- 安装包：`QuotaRoom-v2.0.0.apk`
- 系统要求：Android 7.0+（minSdk 24）
- 可直接覆盖安装 v1.2.0（包名与签名不变）
- 当前为 debug 签名，适合个人安装；上架或长期分发请配置 release keystore
- SHA-256 见 Release 附件 `SHA256SUMS.txt`

## 构建

本版本由 GitHub Actions 自动构建：`flutter analyze`、`flutter test`、`flutter build apk --release`，APK 与校验文件随 Release 上传。

## 来源

- 上游 GoGauge：<https://github.com/yphyphyph/opencode-go-gauge>（MIT）
- 本仓库：<https://github.com/StarryCognet/quotaroom>
- 社区 Android/Flutter 移植与品牌重构，不是 OpenCode 或上游作者的官方产品。

English: QuotaRoom v2.0.0 adds quota pacing and ETA, daily budget, local alerts, period comparison, model×key and top-expensive insights, record search and key drill-down, an Android home-screen widget, background sync, quick actions, CSV/backup/restore, sync log, update check and AMOLED.
