# Third-party notices / 第三方声明

QuotaRoom **v2.3.0 and later** is distributed under the **GNU General Public
License v3.0**. Versions up to and including **v2.2.0** were released under the
MIT License. The complete GPL-3.0 text is in [LICENSE](LICENSE), and is also
bundled inside the app as `assets/LICENSE`.

QuotaRoom is a community project and is not an official release from the
GoGauge, FlClash or OpenCode authors.

## 1. GoGauge / opencode-go-gauge (MIT)

QuotaRoom is a Flutter port and rebrand of GoGauge. The upstream Python code
and data-model ideas are used under the MIT License:

```
MIT License

Copyright (c) 2026 GoGauge (yphyphyph)
Copyright (c) 2026 QuotaRoom contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Upstream project: <https://github.com/yphyphyph/opencode-go-gauge>

## 2. FlClash / prism_ui (GPL-3.0)

The FlClash-style application frame, navigation dock/sidebar, glyph set and
design-system usage are derived from:

- **FlClash** — <https://github.com/chen08209/FlClash>
  Copyright (c) chen08209 and contributors. GPL-3.0.
- **prism_ui** — <https://github.com/chen08209/prism_ui>
  Copyright (c) chen08209 and contributors. GPL-3.0.

These parts are used and distributed under GPL-3.0. QuotaRoom's combined work
is therefore GPL-3.0.

## 3. Flutter, Dart and pub.dev dependencies

QuotaRoom is built with Flutter and Dart and uses packages including
`prism_ui`, `provider`, `sqflite`, `sqflite_common_ffi`,
`flutter_secure_storage`, `flutter_local_notifications`, `webview_flutter`,
`file_selector`, `share_plus`, `url_launcher`, `package_info_plus`,
`path_provider`, `shared_preferences`, `flutter_svg`, `intl`, `workmanager`,
`home_widget` and `quick_actions`.

Each dependency remains under its own license (MIT, BSD-3-Clause, Apache-2.0
or the license stated on its pub.dev page). Their copyright notices and
license texts are available in the respective packages and on pub.dev.

## 4. Windows packaging

- **7-Zip SFX module** (`windows/sfx/7zSD.sfx`) comes from the LZMA SDK by
  Igor Pavlov and is placed in the public domain. It is used only by the
  optional single-file Windows launcher.
- **Inno Setup** and its Simplified Chinese translation
  (`windows/installer/ChineseSimplified.isl`) are used at build time to produce
  the optional installer and remain under the Inno Setup license.

## 5. Trademarks

OpenCode, OpenCode Go and the model names/logos shown in the app (DeepSeek,
GLM, GPT, Grok, Kimi, Meta, MiMo, MiniMax, Qwen, Hunyuan) belong to their
respective owners. They are used only to identify the services and models being
measured. This project is not affiliated with or endorsed by them.
