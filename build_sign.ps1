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
$SignJar = Join-Path $Root "tools\sign\hap-sign-tool.jar"

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
if (-not (Test-Path $SignJar)) {
    $SignJar = Join-Path $KeyDir "hap-sign-tool.jar"
}
if (-not (Test-Path $SignJar)) { Write-Error "Missing sign tool: $SignJar (see key\KEY.txt)" }

$hvigorJs = "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js"
if (-not (Test-Path $hvigorJs)) {
    $candidates = @(
        "$env:DEVECO_HOME\tools\hvigor\hvigor\bin\hvigor.js",
        "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js"
    )
    $hvigorJs = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $hvigorJs) { Write-Error "hvigor.js not found. Install DevEco Studio first." }

$p12 = Join-Path $KeyDir "lxmusic.p12"
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

# ---- 3. locate/build unsigned HAP ----
$hapCandidates = @()
if (-not $SkipBuild) {
    Write-Host "==> building unsigned HAP (version $ver) ..."
    Push-Location $Root
    try {
        node $hvigorJs --mode module -p product=default assembleHap --no-daemon
    } finally {
        Pop-Location
    }
}
$hapCandidates = Get-ChildItem (Join-Path $Root "entry\build") -Recurse -Filter "*unsigned.hap" |
    Sort-Object LastWriteTime -Descending
if (-not $hapCandidates) {
    # 兜底：排除 signed 命名的 hap
    $hapCandidates = Get-ChildItem (Join-Path $Root "entry\build") -Recurse -Filter "*.hap" |
        Where-Object { $_.Name -notmatch "-signed\.hap$" } |
        Sort-Object LastWriteTime -Descending
}
if (-not $hapCandidates) { Write-Error "No unsigned HAP found. Run with -Build first." }
$inHap = $hapCandidates[0].FullName
Write-Host "==> unsigned HAP: $inHap"

# ---- 4. locate pack.info ----
$packInfo = Join-Path $Root "entry\build\default\outputs\default\pack.info"
if (-not (Test-Path $packInfo)) {
    $packInfo = Get-ChildItem (Join-Path $Root "entry\build") -Recurse -Filter "pack.info" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $packInfo) { Write-Error "pack.info not found. Run with -Build first." }
Write-Host "==> pack.info: $packInfo"

# ---- 5. output paths ----
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$unsignedOut = Join-Path $OutDir "lxmusic_${ver}_unsigned.hap"
$signedHap   = Join-Path $OutDir "entry-default-signed.hap"
$appOut      = Join-Path $OutDir "lxmusic_${ver}_release.app"
$zipOut      = Join-Path $OutDir "lxmusic_${ver}_release.zip"

# ---- 6. copy unsigned version ----
Copy-Item $inHap $unsignedOut -Force
Write-Host "==> unsigned copy -> $unsignedOut"

# ---- 7. sign HAP ----
Write-Host "==> signing -> $signedHap"
java -jar $SignJar sign-app `
    -mode localSign `
    -keyAlias $alias -keyPwd $pass `
    -appCertFile $cer -profileFile $p7b `
    -keystoreFile $p12 -keystorePwd $pass `
    -signAlg "SHA256withECDSA" `
    -inFile $inHap -outFile $signedHap

# ---- 8. assemble .app (官方 app_packing_tool 打包，再对外层签名) ----
#     手搓 zip 组装会被 AGC 报 996 解析失败，必须用官方 app_packing_tool.jar --mode app。
$appRaw = Join-Path $OutDir "lxmusic_${ver}_app_raw.app"
Write-Host "==> assembling raw APP (app_packing_tool) -> $appRaw"
java -jar $AppPackJar `
    --mode app `
    --hap-path $signedHap `
    --pack-info-path $packInfo `
    --out-path $appRaw
if (-not (Test-Path $appRaw)) { Write-Error "app_packing_tool failed, no output: $appRaw" }
Write-Host "==> raw APP size: $((Get-Item $appRaw).Length)B"

# 8.2 对 .app 做外层签名（sign-app 同样适用 app 整包）
Write-Host "==> outer-signing APP -> $appOut"
java -jar $SignJar sign-app `
    -mode localSign `
    -keyAlias $alias -keyPwd $pass `
    -appCertFile $cer -profileFile $p7b `
    -keystoreFile $p12 -keystorePwd $pass `
    -signAlg "SHA256withECDSA" `
    -inFile $appRaw -outFile $appOut
Remove-Item $appRaw -Force
Write-Host "==> signed APP size: $((Get-Item $appOut).Length)B"

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
