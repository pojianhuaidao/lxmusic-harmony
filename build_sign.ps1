# ============================================================
# lxmusic-harmony build & sign (HAP + APP dual, zip bundle)
# Usage (run in project root D:\lxmusic-harmony):
#   powershell -ExecutionPolicy Bypass -File build_sign.ps1 -Build
#   powershell -ExecutionPolicy Bypass -File build_sign.ps1 -SkipBuild
# -Build     : build unsigned HAP first, then sign & assemble (default)
# -SkipBuild : skip build, use the newest unsigned HAP under entry\build
#
# Outputs (output\ folder):
#   lxmusic_<ver>_unsigned.hap   -- unsigned HAP (侧载/自装用)
#   lxmusic_<ver>_release.app    -- signed APP  (AGC 测试分发用，内含 signed HAP)
#   lxmusic_<ver>_release.zip    -- 上述两个版本的封装压缩包（push 到 GitHub Release 用）
# ============================================================
param(
    [switch]$Build = $true,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeyDir = Join-Path $Root "key"
$OutDir = Join-Path $Root "output"
$SignJar = Join-Path $KeyDir "hap-sign-tool.jar"

# ---- 1b. locate app_packing_tool.jar (官方 .app 打包，规避手搓 zip 导致 AGC 996) ----
$AppPackJar = Get-ChildItem "C:\Program Files\Huawei\DevEco Studio\sdk" -Recurse -Filter "app_packing_tool.jar" -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $AppPackJar) {
    $candidates = @(
        "$env:DEVECO_SDK_HOME\toolchains\lib\app_packing_tool.jar",
        "$env:DEVECO_HOME\sdk\default\openharmony\toolchains\lib\app_packing_tool.jar"
    )
    $AppPackJar = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $AppPackJar) { Write-Error "app_packing_tool.jar not found (DevEco SDK toolchains)." }
Write-Host "==> app_packing_tool: $AppPackJar"

# ---- 1. locate toolchain ----
if (-not (Test-Path $SignJar)) { Write-Error "Missing sign tool: $SignJar (see key\KEY.txt)" }

# hvigor 官方 wrapper（IDE 自带；自动处理插件加载，规避 node_modules 空壳/顶层 hvigor 冲突）
$hvigorw = "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
if (-not (Test-Path $hvigorw)) {
    $candidates = @(
        "$env:DEVECO_HOME\tools\hvigor\bin\hvigorw.bat",
        "$Root\hvigorw.bat"
    )
    $hvigorw = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $hvigorw) { Write-Error "hvigorw.bat not found. Install DevEco Studio first." }

$p12 = Join-Path $KeyDir "music.p12"
$cerItem = Get-ChildItem $KeyDir -Filter "*.cer" | Select-Object -First 1
$p7bItem = Get-ChildItem $KeyDir -Filter "*.p7b" | Select-Object -First 1
if (-not $cerItem) { Write-Error "Missing .cer file in $KeyDir (see key\KEY.txt)" }
if (-not $p7bItem) { Write-Error "Missing .p7b file in $KeyDir (see key\KEY.txt)" }
$cer = $cerItem.FullName
$p7b = $p7bItem.FullName
foreach ($f in @($p12, $cer, $p7b)) {
    if (-not (Test-Path $f)) { Write-Error "Missing signing material: $f (see key\KEY.txt)" }
}

$pass = "wuxiujun13627489"
$alias = "lxmusic"

# ---- 2. read version ----
$appJson = Get-Content (Join-Path $Root "AppScope\app.json5") -Raw
$verMatch = [regex]::Match($appJson, '"versionName"\s*:\s*"([^"]+)"')
$ver = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { "unknown" }

# ---- 3. 修正 DEVECO_SDK_HOME（hvigor 依赖它定位 SDK；若指向失效路径会报 00303217） ----
$sdkCandidates = @(
    $env:DEVECO_SDK_HOME,
    "C:\Program Files\Huawei\DevEco Studio\sdk"
) | Where-Object { $_ -and (Test-Path $_) }
$sdkHome = $sdkCandidates | Select-Object -First 1
if (-not $sdkHome) { Write-Error "DevEco SDK not found (DEVECO_SDK_HOME invalid)." }
$env:DEVECO_SDK_HOME = $sdkHome
Write-Host "==> DEVECO_SDK_HOME -> $env:DEVECO_SDK_HOME"

# ---- 3b. （已移除）NODE_PATH 兜底不再需要：hvigorw 官方 wrapper 自行解析 IDE 内置插件，
#     项目 node_modules 里的 @ohos/hvigor 反而会触发 00302013 root node 冲突，勿再装回顶层 ----

# ---- 4. locate/build unsigned HAP + signed APP（hvigor assembleApp 官方链路） ----
#     官方 Build App(s) 链路：一次产出 unsigned HAP、signed HAP 与 signed APP。
#     APP 内含 pac.json + entry-default.hap（与 pack.info packages.name 一致）+ 官方签名，
#     是 AGC 测试分发唯一认可的格式（手搓 zip / 旧版 hap-sign-tool 重签会被 AGC 解析失败）。
$unsignedOutHap = Join-Path $Root "entry\build\default\outputs\default\entry-default-unsigned.hap"
$signedApp = Join-Path $Root "build\outputs\default\lxmusic-harmony-default-signed.app"
if (-not $SkipBuild) {
    Write-Host "==> building official HAP + APP (version $ver) ..."
    Push-Location $Root
    try {
        # 先 clean 再全量构建：规避 hvigor 增量缓存把打包判 up-to-date 导致版本号仍是旧包
        & $hvigorw clean --no-daemon
        if ($LASTEXITCODE -ne 0) { Write-Error "hvigor clean failed (exit $LASTEXITCODE). Abort." }
        & $hvigorw --mode project -p product=default -p buildMode=release assembleApp --no-daemon
        if ($LASTEXITCODE -ne 0) { Write-Error "hvigor assembleApp failed (exit $LASTEXITCODE). Abort." }
    } finally {
        Pop-Location
    }
}
if (-not (Test-Path $signedApp)) {
    # 兜底：自动探测 build\outputs\default 下最新的 *-signed.app
    $signedApp = Get-ChildItem (Join-Path $Root "build\outputs\default") -Filter "*-signed.app" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $signedApp) { Write-Error "No signed APP found. Run with -Build first." }
if (-not (Test-Path $unsignedOutHap)) {
    $unsignedOutHap = Get-ChildItem (Join-Path $Root "entry\build") -Recurse -Filter "*unsigned.hap" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $unsignedOutHap) { Write-Error "No unsigned HAP found. Run with -Build first." }
Write-Host "==> unsigned HAP: $unsignedOutHap"
Write-Host "==> signed APP  : $signedApp"

# ---- 5. output paths ----
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$unsignedOut = Join-Path $OutDir "lxmusic_${ver}_unsigned.hap"
$appOut      = Join-Path $OutDir "lxmusic_${ver}_release.app"
$zipOut      = Join-Path $OutDir "lxmusic_${ver}_release.zip"

# ---- 6. copy official artifacts (hvigor 已签好 HAP/APP，直接落盘) ----
Copy-Item $unsignedOutHap $unsignedOut -Force
Copy-Item $signedApp $appOut -Force
Write-Host "==> unsigned copy -> $unsignedOut"
Write-Host "==> signed APP   -> $appOut ($((Get-Item $appOut).Length)B)"

# ---- 9. package zip (unsigned HAP + signed APP) ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
function Add-ZipEntry($zip, $srcPath, $entryName) {
    $entry = $zip.CreateEntry($entryName)
    $stream = $entry.Open()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($srcPath)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Close()
    }
}
Write-Host "==> packaging zip -> $zipOut"
$fs2 = [System.IO.File]::Open($zipOut, [System.IO.FileMode]::Create)
$zip2 = New-Object System.IO.Compression.ZipArchive($fs2, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Add-ZipEntry $zip2 $unsignedOut "lxmusic_${ver}_unsigned.hap"
    Add-ZipEntry $zip2 $appOut      "lxmusic_${ver}_release.app"
} finally {
    $zip2.Dispose()
    $fs2.Dispose()
}

Write-Host ""
Write-Host "Done:"
Write-Host "  unsigned HAP : $unsignedOut"
Write-Host "  signed APP   : $appOut"
Write-Host "  bundle zip   : $zipOut ($((Get-Item $zipOut).Length)B)"
Write-Host "(zip 内两版本：lxmusic_${ver}_unsigned.hap 侧载用 / lxmusic_${ver}_release.app AGC 测试分发用)"
