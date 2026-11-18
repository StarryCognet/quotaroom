# QuotaRoom v2.2.0 — Windows 桌面端

同一套 Flutter 代码新增 Windows 桌面版：手机和电脑共用一个本地优先的用量面板。Android 功能与数据格式保持不变，Windows 使用独立的数据目录，不会覆盖手机数据。

## 新增 Windows 桌面端

- 新增 `windows/` runner，可构建免安装的 x64 便携版（`QuotaRoom-v2.2.0-windows-x64.zip`）。
- 桌面端使用 FFI SQLite，数据库位于 `%APPDATA%\StarryCognet\QuotaRoom\quotaroom.db`。
- 会话 Cookie 使用 Windows 凭据管理器 + AES-GCM 加密文件保存。
- 桌面宽屏布局：大于 840px 时左侧导航栏，内容区自适应；支持 `Ctrl+1…5` 切换页面、`Ctrl+R` / `F5` 立即同步。
- Windows Toast 通知：额度低于 20% / 10%、每日预算 80% / 超支时提醒。
- 桌面登录：系统浏览器打开 opencode.ai，粘贴 `__Host-console_session` 完成连接。
- CSV / 数据库备份在桌面端改为「另存为」对话框；用量摘要改为复制到剪贴板。
- 更新检查同时识别 APK 与 Windows 便携版 zip；桌面端点「前往下载」打开对应 Release 附件。

## Android 保持

- 内置 WebView 登录、WorkManager 后台同步、桌面小组件、长按快捷方式继续只存在于 Android。
- APK 包名、签名、数据库路径与 v2.1.1 一致，可直接覆盖升级。
- 移动端布局与功能不受影响。

## 安装

- Android：`QuotaRoom-v2.2.0.apk`，Android 7.0+。
- Windows：下载 `QuotaRoom-v2.2.0-windows-x64.zip`，解压后运行 `QuotaRoom.exe`；更新时解压覆盖原目录。
- SHA-256 见 Release 附件 `SHA256SUMS.txt` / `SHA256SUMS-windows.txt`。

## 从源码构建 Windows

- 安装 Flutter 3.47+、Visual Studio Build Tools（含「使用 C++ 的桌面开发」与 ATL 组件）。
- 开启 Windows 开发者模式，或先运行 `dart run tool/windows_plugin_links.dart` 创建插件链接。
- `flutter build windows --release`，产物位于 `build/windows/x64/runner/Release/`。
