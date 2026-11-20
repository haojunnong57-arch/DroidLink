//
//  ConnectView.swift
//  DroidLink
//
//  Connect panel + live screen. All input is forwarded over the scrcpy control
//  socket, so the iPhone never has to know anything about the APK itself.
//

import SwiftUI
import UIKit

struct ConnectView: View {
    @StateObject private var video = VideoClient()
    @StateObject private var control = ControlClient()

    @AppStorage("dl_host") private var host = "192.168.1."
    @AppStorage("dl_video_port") private var videoPort = "27183"
    @AppStorage("dl_control_port") private var controlPort = "27184"


    private var connected: Bool { video.connected && control.connected }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if connected {
                    screenArea
                } else {
                    hero
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Not connected

    private var hero: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white)
                Text("DroidLink")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("把电脑上的 Android 画面串到这台 iPhone")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(spacing: 10) {
                field("电脑 IP", text: $host, keyboard: .decimalPad)
                HStack(spacing: 10) {
                    field("视频端口", text: $videoPort, keyboard: .numberPad)
                    field("控制端口", text: $controlPort, keyboard: .numberPad)
                }
            }
            .padding(.horizontal, 26)

            Button {
                startConnection()
            } label: {
                Text("连接")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.36, green: 0.78, blue: 0.82), in: Capsule())
            }
            .padding(.horizontal, 26)

            VStack(spacing: 4) {
                Text(video.state)
                Text(control.state)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))

            Spacer()

            Text("先在电脑上运行 host 脚本把 scrcpy 服务开好；\n本 App 只做硬解与触控转发，不联网上传任何画面。")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 24)
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }

    // MARK: - Connected

    private var screenArea: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                PlayerView { layer in
                    video.displayLayer = layer
                }
                .overlay(
                    GestureCapture(
                        onDown: { p in sendTouch(0, at: p, size: geo.size) },
                        onMove: { p in sendTouch(2, at: p, size: geo.size) },
                        onUp: { p in sendTouch(1, at: p, size: geo.size) }
                    )
                )
            }
            .ignoresSafeArea()

            HStack(spacing: 12) {
                navButton("chevron.left", keycode: 4)
                navButton("house", keycode: 3)
                navButton("square.stack", keycode: 187)
                Spacer()
                Text("\(Int(video.fps)) fps · \(Int(video.videoSize.width))×\(Int(video.videoSize.height))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    video.disconnect()
                    control.disconnect()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func navButton(_ symbol: String, keycode: Int32) -> some View {
        Button {
            control.tapKey(keycode)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    // MARK: - Wiring

    private func startConnection() {
        guard let vp = UInt16(videoPort), let cp = UInt16(controlPort), !host.isEmpty else { return }
        video.connect(host: host, port: vp)
        control.connect(host: host, port: cp)
    }

    private func sendTouch(_ action: UInt8, at point: CGPoint, size: CGSize) {
        let vw = video.videoSize.width, vh = video.videoSize.height
        guard vw > 0, vh > 0, size.width > 0, size.height > 0 else { return }
        let scale = min(size.width / vw, size.height / vh)
        let drawW = vw * scale, drawH = vh * scale
        let ox = (size.width - drawW) / 2, oy = (size.height - drawH) / 2
        let x = Float((point.x - ox) / scale)
        let y = Float((point.y - oy) / scale)
        if action == 0 {
            control.setScreen(width: Int(vw), height: Int(vh))
            control.touch(action: 0, x: max(0, x), y: max(0, y), pressure: 1.0)
        } else if action == 2 {
            control.touch(action: 2, x: max(0, x), y: max(0, y), pressure: 1.0)
        } else {
            control.touch(action: 1, x: max(0, x), y: max(0, y), pressure: 0)
        }
    }
}

/// Minimal UIKit-free gesture capture: SwiftUI DragGesture cannot report the
/// initial location without a minimum distance, so a zero-distance gesture is
/// used and its first change is treated as a down event.
private struct GestureCapture: View {
    var onDown: (CGPoint) -> Void
    var onMove: (CGPoint) -> Void
    var onUp: (CGPoint) -> Void

    @State private var active = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if !active {
                            active = true
                            onDown(value.location)
                        } else {
                            onMove(value.location)
                        }
                    }
                    .onEnded { value in
                        active = false
                        onUp(value.location)
                    }
            )
    }
}
