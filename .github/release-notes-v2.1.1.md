# QuotaRoom v2.1.1 — 更新彩带效果修正

修正 v2.1.0 更新公告中彩带动效被弹窗转场遮住、出现时间过短的问题。

## 本次调整

- 彩带改为弹窗完全出现后开始播放，避免动画在转场期间提前结束。
- 持续时间从 1.9 秒延长到 3 秒，粒子从标题下方朝下喷洒，覆盖弹窗主体。
- 粒子数量、尺寸和停留时间增加，暗色 / AMOLED 下同样可见。
- 更新下载、安装权限引导、系统安装器与覆盖升级流程保持不变。

## 安装

- 安装包：`QuotaRoom-v2.1.1.apk`
- 系统要求：Android 7.0+（minSdk 24）
- 从 v2.1.0 / v2.0.0 可直接覆盖升级
- SHA-256 见 Release 附件 `SHA256SUMS.txt`

## 验证

- `flutter analyze`：无问题
- `flutter test`：42/42 通过
- v2.0.0 → 更新弹窗 → 下载 → 授权 → 系统安装器 → v2.1.0 升级链路已在 Android 模拟器实测
- v2.1.1 由 GitHub Actions 使用固定 release keystore 构建

## 来源

- 上游 GoGauge：<https://github.com/yphyphyph/opencode-go-gauge>（MIT）
- 本仓库：<https://github.com/StarryCognet/quotaroom>
- 社区 Android/Flutter 移植与品牌重构，不是 OpenCode 或上游作者的官方产品。

English: QuotaRoom v2.1.1 fixes the confetti announcement timing so the burst starts after the dialog transition and lasts three seconds.
