# 7-Zip SFX module

`7zSD.sfx` is the installer SFX module from the LZMA SDK (7-Zip 26.06).

- Source: https://www.7-zip.org/sdk.html
- LZMA SDK is written and placed in the public domain by Igor Pavlov.
- It is used only to build the optional single-file Windows launcher. The
  launcher extracts the Flutter Windows bundle to a temporary directory and
  runs `QuotaRoom.exe`; application data still lives in
  `%APPDATA%\StarryCognet\QuotaRoom`.
