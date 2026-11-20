# DroidLink — 在 iPhone 上流畅使用 Android / APK

iPhone 无法本地执行 ARM 版 Android 的 APK（iOS 不允许 JIT、不允许加载外部 ELF/SO，也没有 Android 内核）。所以“流畅”只有一条工程上站得住的路线：**Android 跑在宿主机上，iPhone 只做 H.264 硬解 + 触控回传**。

DroidLink 就是这条路线的最小客户端：

- 直连 `scrcpy-server` 的 video / control 端口；
- H.264 交给 `AVSampleBufferDisplayLayer` 硬件解码，60fps 不额外耗 CPU；
- 触摸、滚动、返回/主页/多任务全部走 scrcpy 控制协议，延迟在局域网内通常 30–60ms；
- 不经过任何中转服务器，不上传画面。

## 组成

| 部分 | 开源来源 | 作用 |
|---|---|---|
| scrcpy-server（宿主机侧） | Genymobile/scrcpy (Apache-2.0) | 抓 Android 屏幕、编码 H.264、接收控制事件 |
| Android 运行环境 | 真机 / Android Studio 模拟器 / redroid（容器化 Android） | 真正运行 APK 的地方 |
| DroidLink（iOS） | 本仓库 | 解码显示 + 手势回传 |

## 用法

1. 电脑（Windows / macOS / Linux）与 iPhone 连同一个 Wi-Fi。
2. 宿主机上装好 `adb`，Android 真机开 USB 调试（或模拟器已启动）。
3. 运行宿主脚本：

```powershell
# Windows，管理员 PowerShell（端口映射需要提权）
cd host
.\start-host.ps1
```

脚本会：推送 `scrcpy-server.jar` → 建立 `27183`（视频）/`27184`（控制）转发 → 启动服务 → 把两个端口映射到局域网。
4. iPhone 上打开 DroidLink，填电脑 IP，端口默认 27183 / 27184，点连接。

## 限制（如实说明）

- 必须有 Android 宿主，iPhone 本身不执行 APK。
- 未签名 IPA，需重签后安装。
- 目前只处理 H.264 视频与触控/按键，暂不含音频、剪贴板、实体键盘。
- 同一时间只支持一台 iPhone（宿主脚本用单连接中继）。

## 想完全在本机跑 APK

这属于另一条技术路线（UML/翻译层虚拟化），可参考开源项目：

- `imxieyi/Kernarium` 与基于它的 Andarium（本地 LineageOS Android 17，可装 APK；已被 App Store 下架，只能侧载）
- `Leviidev/Husk`（翻译层直跑 Android 原生 .so，需要 JIT，一次跑一个应用）

它们的共同代价是 CPU 语义翻译 + GPU 转译，发热和掉帧明显，和“流畅”不是一个量级。
