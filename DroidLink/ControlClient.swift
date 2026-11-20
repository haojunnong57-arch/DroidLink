//
//  ControlClient.swift
//  DroidLink
//
//  scrcpy control channel: raw send-only TCP socket. Every message is a fixed
//  layout defined by ControlMessageReader.java on the server.
//

import Foundation
import Network

final class ControlClient: ObservableObject {

    @Published var state: String = "未连接"
    @Published var connected = false

    private let queue = DispatchQueue(label: "droidlink.control")
    private var conn: NWConnection?
    private var width: UInt16 = 1080
    private var height: UInt16 = 1920

    func setScreen(width: Int, height: Int) {
        self.width = UInt16(max(1, min(65535, width)))
        self.height = UInt16(max(1, min(65535, height)))
    }

    func connect(host: String, port: UInt16) {
        disconnect()
        guard let p = NWEndpoint.Port(rawValue: port) else {
            state = "端口无效"
            return
        }
        state = "连接控制 \(host):\(port)…"
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            DispatchQueue.main.async {
                switch st {
                case .ready:
                    self.state = "控制已连接"
                    self.connected = true
                case .failed(let err):
                    self.state = "控制断开：\(err.localizedDescription)"
                    self.connected = false
                default:
                    break
                }
            }
        }
        c.start(queue: queue)
        // The server only sends clipboard packets; drain them so the socket
        // does not stall.
        drain()
    }

    private func drain() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, done, error in
            guard let self, !done, error == nil else { return }
            self.drain()
        }
    }

    func disconnect() {
        conn?.cancel()
        conn = nil
        DispatchQueue.main.async { self.connected = false }
    }

    private func send(_ data: Data) {
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Input

    /// action: 0 down, 1 up, 2 move
    func touch(action: UInt8, x: Float, y: Float, pressure: Float) {
        var d = Data(capacity: 32)
        d.append(2)                                  // TYPE_INJECT_TOUCH_EVENT
        d.append(action)
        d.append(contentsOf: withUnsafeBytes(of: UInt64(0xFFFF_FFFF_FFFF_FFFE).bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: Int32(x).bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: Int32(y).bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Array($0) })
        let p16 = UInt16(max(0, min(1, pressure)) * 65535)
        d.append(contentsOf: withUnsafeBytes(of: p16.bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })   // actionButton
        d.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })   // buttons
        send(d)
    }

    func scroll(x: Float, y: Float, vScroll: Float, hScroll: Float = 0) {
        var d = Data(capacity: 21)
        d.append(3)                                  // TYPE_INJECT_SCROLL_EVENT
        d.append(contentsOf: withUnsafeBytes(of: Int32(x).bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: Int32(y).bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Array($0) })
        let v = Int16(max(-16, min(16, vScroll)) * 2048)
        let h = Int16(max(-16, min(16, hScroll)) * 2048)
        d.append(contentsOf: withUnsafeBytes(of: v.bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: h.bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })
        send(d)
    }

    /// action: 0 down, 1 up
    func key(_ keycode: Int32, action: UInt8 = 0) {
        var d = Data(capacity: 14)
        d.append(0)                                  // TYPE_INJECT_KEYCODE
        d.append(action)
        d.append(contentsOf: withUnsafeBytes(of: keycode.bigEndian) { Array($0) })
        d.append(contentsOf: withUnsafeBytes(of: Int32(0).bigEndian) { Array($0) })   // repeat
        d.append(contentsOf: withUnsafeBytes(of: Int32(0).bigEndian) { Array($0) })   // metaState
        send(d)
    }

    func tapKey(_ keycode: Int32) {
        key(keycode, action: 0)
        key(keycode, action: 1)
    }
}
