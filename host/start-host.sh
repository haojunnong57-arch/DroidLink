#!/usr/bin/env bash
# start-host.sh — 让 iPhone 连上这台电脑上的 Android（macOS / Linux）
set -euo pipefail

VERSION="${SCRCPY_VERSION:-3.3.1}"
JAR="scrcpy-server-v${VERSION}"
VIDEO_PORT=27183
CONTROL_PORT=27184
IP="${HOST_IP:-$(ipconfig getifaddr en0 2>/dev/null || hostname -I | awk '{print $1}')}"

command -v adb >/dev/null || { echo "请先安装 adb (Android platform-tools)"; exit 1; }

adb devices

if [ ! -f "$JAR" ]; then
  echo "下载 scrcpy-server $VERSION …"
  curl -fL -o "$JAR" "https://github.com/Genymobile/scrcpy/releases/download/v${VERSION}/${JAR}"
fi

adb push "$JAR" /data/local/tmp/scrcpy-server.jar
adb forward "tcp:${VIDEO_PORT}" localabstract:scrcpy
adb forward "tcp:${CONTROL_PORT}" localabstract:scrcpy

echo "启动 scrcpy-server …"
adb shell "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server ${VERSION} tunnel_forward=true audio=false control=true cleanup=false max_size=1920 max_fps=60 video_codec=h264 video_bit_rate=8000000" &

# adb forward 只监听 127.0.0.1，需要把端口转到局域网
if command -v socat >/dev/null; then
  echo "用 socat 暴露端口到局域网 …"
  socat "TCP-LISTEN:${VIDEO_PORT},fork,reuseaddr" "TCP:127.0.0.1:${VIDEO_PORT}" &
  socat "TCP-LISTEN:${CONTROL_PORT},fork,reuseaddr" "TCP:127.0.0.1:${CONTROL_PORT}" &
  echo "iPhone 上填 ${IP}，端口 ${VIDEO_PORT} / ${CONTROL_PORT}"
  echo "（socat 会监听所有网卡，注意仅在同一可信 Wi‑Fi 下使用）"
else
  echo "未安装 socat，只有本机能连。装一个再试：brew install socat / apt install socat"
  echo "iPhone 仍可尝试 ${IP}:${VIDEO_PORT}（多数系统下会失败）"
fi

wait
