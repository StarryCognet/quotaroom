# Inno Setup installer

`QuotaRoom.iss` builds the per-user Windows installer. It is invoked by
`tool/package_windows.ps1` with:

```text
ISCC.exe /DMyAppVersion=<version> /DSourceDir=<Release dir> /DOutputDir=<dist dir> QuotaRoom.iss
```

`ChineseSimplified.isl` is the Simplified Chinese translation from the Inno
Setup source tree (`Files/Languages/ChineseSimplified.isl`), maintained by
Zhenghan Yang (Kira) and distributed under the Inno Setup license. It is kept
in-repo because the Inno Setup installer does not ship this translation by
default.

Default install mode is per-user (`PrivilegesRequired=lowest`), so no
administrator prompt is needed. Users can still opt into an all-users install
from the command line/dialog. The uninstaller does not delete the QuotaRoom
database under `%APPDATA%\StarryCognet\QuotaRoom`.
