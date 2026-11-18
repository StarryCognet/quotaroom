# QuotaRoom v2.1.0 — 应用内更新与彩带公告

新增应用内更新流程：发现新版本时弹出带彩带效果的更新公告，直接下载 APK 并拉起 Android 系统安装器。

## 应用内更新

- 启动 App 后自动检查 GitHub 最新 Release（最多每 24 小时一次，不阻塞进入首页）。
- 设置页「检查更新」保留手动检查，发现新版本时打开更新公告。
- 更新弹窗展示版本号、安装包大小和本次 Release 的更新内容。
- 点击「下载并安装」后显示实时下载进度，下载完成自动拉起系统 Package Installer。
- Android 首次安装需要允许 QuotaRoom「安装未知应用」；弹窗会引导前往系统设置，返回后可重试。
- 更新公告带一次性彩带动效；点「稍后再说」后同一版本不会在启动时反复弹出。
- 下载的 APK 会校验 ZIP 头和文件大小，失败时自动清理临时文件。

## 兼容与升级

- v2.0.0 使用同一固定 release keystore 签名，可直接覆盖升级。
- 仍然从本仓库的 GitHub Release 获取 APK，不经过第三方服务器。
- 版本 2.1.0（versionCode 6）。

## 安装

- 安装包：`QuotaRoom-v2.1.0.apk`
- 系统要求：Android 7.0+（minSdk 24）
- SHA-256 见 Release 附件 `SHA256SUMS.txt`

## 构建

GitHub Actions 自动执行 `flutter analyze`、`flutter test`、`flutter build apk --release`，并使用仓库 Secrets 中的固定 release keystore 签名。

## 来源

- 上游 GoGauge：<https://github.com/yphyphyph/opencode-go-gauge>（MIT）
- 本仓库：<https://github.com/StarryCognet/quotaroom>
- 社区 Android/Flutter 移植与品牌重构，不是 OpenCode 或上游作者的官方产品。

English: QuotaRoom v2.1.0 adds an in-app update flow with a confetti announcement dialog, release notes, APK download progress, and automatic launch of Android's package installer, plus a daily startup update check.
