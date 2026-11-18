# QuotaRoom v2.3.0 — FlClash 风格全页面 UI 与过渡动画

这次把 QuotaRoom 的整个界面层换成 FlClash 同源技术栈：prism_ui + 自定义绘制，不再保留 Material 页面或 fl_chart 图表。Android 与 Windows 共用同一套页面。

## 全页面 prism_ui

- 首页、统计、记录（会话 / 明细 / Key）、账号、设置、关于、开源许可全部换成 prism_ui。
- 桌面可折叠侧栏、移动悬浮 dock、squircle 卡片、tinted surface、bento 首页。
- 登录页、Cookie 粘贴表单、账号菜单、确认 / 重命名 / 预算对话框、模型筛选 sheet、更新公告、WebView 登录页全部 prism 化。
- 旧的 Material `AppCard`/`KpiCard`/`PillSelector`/`EmptyState`/`SyncBanner` 等共享组件已重写；旧 `shell.dart`、`login_page.dart`、`home_page.dart`、`quota_card.dart`、Material cookie sheet 已删除。

## 过渡动画

- 页面切换使用 prism_ui 的 `TabBarView` 滑动；记录页三个 Tab 与子 Tab 同样带滑动切换。
- 设置、关于、许可、登录等推入路由使用 slide + fade；应用启动 / 登录成功使用淡入缩放。
- 卡片入场、KPI 数值变化、进度条增长、趋势图 / 柱状图 / 环形图 / sparkline 绘制都有动画。
- AppBar 页面标题随 Tab 切换淡入滑动。

## 悬浮 dock 与图表

- 移动端悬浮 dock 下方不再有独立的空白背景层；内容可以滚动到 dock 下方，只由 dock 本身浮在内容上。
- 趋势图、24 小时柱状图、模型环形图和 sparkline 改为 prism 配色 + CustomPainter，不再依赖 fl_chart，也不再有 Material 图表容器。

## 许可证变更

- **v2.3.0 起，QuotaRoom 按 GPL-3.0 发布**；v2.2.0 及更早版本仍为 MIT。
- 上游 GoGauge 代码保留 MIT 许可，完整文本见 `THIRD_PARTY_NOTICES.md`。
- FlClash / prism_ui 界面组件按 GPL-3.0 使用，版权归 chen08209 and contributors。
- App 内「关于 → 开源许可」可查看 GPL-3.0 全文、MIT 上游声明与第三方 credits。

## Windows 桌面端

- v2.2.0 的 Windows 桌面能力保持不变：FFI SQLite、Windows 凭据管理器 / AES-GCM、浏览器 + Cookie 登录、Toast、桌面另存为、安装版 / 便携版 / 单文件版。
- 本次同时更新了桌面布局与动画；Android 包名、签名与数据格式不变，可直接覆盖升级。

## 安装

- Android：`QuotaRoom-v2.3.0.apk`，Android 7.0+。
- Windows：`QuotaRoom-v2.3.0-windows-x64-setup.exe`（安装版）、`...-windows-x64.zip`（便携版）或 `...-windows-x64-single.exe`（单文件版）。
- SHA-256 见 Release 附件 `SHA256SUMS.txt` / `SHA256SUMS-windows.txt`。

## 从源码构建 Windows

- 安装 Flutter 3.47+、Visual Studio Build Tools（含「使用 C++ 的桌面开发」与 ATL 组件）。
- 开启 Windows 开发者模式，或先运行 `dart run tool/windows_plugin_links.dart` 创建插件链接。
- `flutter build windows --release`，产物位于 `build/windows/x64/runner/Release/`。
