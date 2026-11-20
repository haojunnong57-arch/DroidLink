# start-host.ps1 — 让 iPhone 连上这台电脑上的 Android
# 需要：Windows 管理员 PowerShell、adb 在 PATH、Android 设备已授权 USB 调试
$ErrorActionPreference = "Stop"

$Version = "3.3.1"
$Jar     = "scrcpy-server-v$Version"
$VideoPort   = 27183
$ControlPort = 27184

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Host "找不到 adb，请先安装 Android platform-tools 并加入 PATH。" -ForegroundColor Red
    exit 1
}

Write-Host "检查设备…"
adb devices

if (-not (Test-Path $Jar)) {
    Write-Host "下载 scrcpy-server $Version …"
    curl.exe -fL -o $Jar "https://github.com/Genymobile/scrcpy/releases/download/v$Version/$Jar"
}

Write-Host "推送 server…"
adb push $Jar /data/local/tmp/scrcpy-server.jar | Out-Host

Write-Host "建立端口转发…"
adb forward tcp:$VideoPort localabstract:scrcpy
adb forward tcp:$ControlPort localabstract:scrcpy

Write-Host "启动 scrcpy-server（后台）…"
Start-Job -Name scrcpy-server -ScriptBlock {
    param($V)
    adb shell "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server $V tunnel_forward=true audio=false control=true cleanup=false max_size=1920 max_fps=60 video_codec=h264 video_bit_rate=8000000"
} -ArgumentList $Version | Out-Host

Write-Host "把端口暴露到局域网（需要管理员权限）…"
netsh interface portproxy delete v4tov4 listenport=$VideoPort listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy delete v4tov4 listenport=$ControlPort listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenport=$VideoPort listenaddress=0.0.0.0 connectport=$VideoPort connectaddress=127.0.0.1
netsh interface portproxy add v4tov4 listenport=$ControlPort listenaddress=0.0.0.0 connectport=$ControlPort connectaddress=127.0.0.1

Write-Host ""
Write-Host "本机地址：" -NoColor
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } |
    Select-Object IPAddress, InterfaceAlias | Format-Table | Out-Host

Write-Host "在 iPhone 上打开 DroidLink，IP 填上面的地址，端口 $VideoPort / $ControlPort。"
Write-Host "关闭时执行：adb forward --remove-all; Remove-Job -Name scrcpy-server"
