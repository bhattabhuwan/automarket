param(
    [string]$DeviceId = "0015bbc40406",
    [string]$PackageName = "com.example.automarket"
)

$ErrorActionPreference = "Stop"

$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    throw "adb.exe was not found at $adb"
}

flutter build apk --debug

& $adb -s $DeviceId install -t -r "build\app\outputs\flutter-apk\app-debug.apk"
& $adb -s $DeviceId shell am force-stop $PackageName
& $adb -s $DeviceId shell am start `
    -a android.intent.action.MAIN `
    -c android.intent.category.LAUNCHER `
    -f 0x20000000 `
    --ez enable-dart-profiling true `
    --ez enable-checked-mode true `
    --ez verify-entry-points true `
    "$PackageName/$PackageName.MainActivity"

flutter attach -d $DeviceId
