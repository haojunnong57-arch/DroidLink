//
//  VideoClient.swift
//  DroidLink
//
//  Minimal scrcpy video client: connects to the forwarded video port, speaks
//  the scrcpy stream protocol (codec id, session packets, 12-byte frame
//  headers) and feeds H.264 access units straight into an
//  AVSampleBufferDisplayLayer (hardware decode, zero re-encode).
//

import Foundation
import Network
import AVFoundation
import CoreMedia

final class VideoClient: ObservableObject {

    @Published var state: String = "未连接"
    @Published var videoSize: CGSize = .zero
    @Published var fps: Double = 0
    @Published var connected = false

    var displayLayer: AVSampleBufferDisplayLayer?

    private let queue = DispatchQueue(label: "droidlink.video")
    private var conn: NWConnection?
    private var buffer = Data()
    private var gotCodec = false
    private var format: CMVideoFormatDescription?
    private var sps: [UInt8] = []
    private var pps: [UInt8] = []
    private var frames = 0
    private var lastFPSMark = Date()

    func connect(host: String, port: UInt16) {
        disconnect()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            state = "端口无效"
            return
        }
        state = "连接视频 \(host):\(port)…"
        let c = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            DispatchQueue.main.async {
                switch st {
                case .ready:
                    self.state = "视频已连接"
                    self.connected = true
                case .failed(let err):
                    self.state = "视频断开：\(err.localizedDescription)"
                    self.connected = false
                case .cancelled:
                    self.connected = false
                default:
                    break
                }
            }
        }
        c.start(queue: queue)
        receiveLoop()
    }

    func disconnect() {
        conn?.cancel()
        conn = nil
        buffer.removeAll(keepingCapacity: false)
        gotCodec = false
        format = nil
        sps.removeAll()
        pps.removeAll()
        DispatchQueue.main.async {
            self.connected = false
            self.videoSize = .zero
        }
    }

    private func receiveLoop() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.parse()
            }
            if done || error != nil {
                DispatchQueue.main.async { self.state = "视频流已结束" }
                return
            }
            self.receiveLoop()
        }
    }

    // MARK: - Protocol parsing

    private func parse() {
        if !gotCodec {
            guard buffer.count >= 4 else { return }
            let codec = u32(buffer, buffer.startIndex)
            buffer.removeFirst(4)
            gotCodec = true
            guard codec == 0x6832_3634 else {   // "h264"
                DispatchQueue.main.async { self.state = "需要 H.264，服务器返回其它编码" }
                return
            }
        }

        while buffer.count >= 12 {
            let base = buffer.startIndex
            if (buffer[base] & 0x80) != 0 {
                // Session packet: flags, width, height.
                let w = Int(u32(buffer, base + 4))
                let h = Int(u32(buffer, base + 8))
                buffer.removeFirst(12)
                format = nil
                DispatchQueue.main.async {
                    self.videoSize = CGSize(width: w, height: h)
                    self.displayLayer?.flush()
                }
                continue
            }

            let size = Int(u32(buffer, base + 8))
            guard size > 0, buffer.count >= 12 + size else { return }

            let ptsFlags = u64(buffer, base)
            let payload = buffer.subdata(in: (base + 12) ..< (base + 12 + size))
            buffer.removeFirst(12 + size)

            if (ptsFlags & (1 << 62)) != 0 {
                handleConfig(payload)
            } else {
                handleMedia(payload, pts: ptsFlags & 0x1FFF_FFFF_FFFF_FFFF)
            }
            if buffer.count > 4 << 20 {
                buffer.removeAll(keepingCapacity: false)   // never grow unbounded
                break
            }
        }
    }

    private func handleConfig(_ data: Data) {
        let nals = annexB(data)
        for nal in nals {
            guard let first = nal.first else { continue }
            let type = first & 0x1F
            if type == 7 { sps = nal } else if type == 8 { pps = nal }
        }
        guard !sps.isEmpty, !pps.isEmpty else { return }

        var fd: CMVideoFormatDescription?
        sps.withUnsafeBufferPointer { sBuf in
            pps.withUnsafeBufferPointer { pBuf in
                var pointers: [UnsafePointer<UInt8>] = [sBuf.baseAddress!, pBuf.baseAddress!]
                var sizes: [Int] = [sps.count, pps.count]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &fd
                )
            }
        }
        format = fd
        if let layer = displayLayer {
            layer.flush()
        }
    }

    private func handleMedia(_ payload: Data, pts: UInt64) {
        guard let format else { return }

        let nals = annexB(payload)
        guard !nals.isEmpty else { return }

        var avcc = Data(capacity: payload.count + nals.count * 4)
        for nal in nals {
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { avcc.append(contentsOf: $0) }
            avcc.append(contentsOf: nal)
        }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &block
        ) == noErr, let block else { return }

        avcc.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: block,
                offsetIntoDestination: 0, dataLength: avcc.count
            )
        }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return }

        guard let layer = displayLayer else { return }
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sample)

        frames += 1
        if Date().timeIntervalSince(lastFPSMark) >= 1 {
            let f = Double(frames) / Date().timeIntervalSince(lastFPSMark)
            frames = 0
            lastFPSMark = Date()
            DispatchQueue.main.async { self.fps = f }
        }
    }

    // MARK: - Helpers

    private func annexB(_ data: Data) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var nals: [UInt8] = []
        let bytes = [UInt8](data)
        var i = 0
        while i + 3 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                if !nals.isEmpty { out.append(nals); nals.removeAll(keepingCapacity: true) }
                i += 3
                continue
            }
            nals.append(bytes[i])
            i += 1
        }
        for rest in bytes[i...] { nals.append(rest) }
        if !nals.isEmpty { out.append(nals) }
        return out
    }

    private func u32(_ d: Data, _ o: Int) -> UInt32 {
        (UInt32(d[o]) << 24) | (UInt32(d[o + 1]) << 16) | (UInt32(d[o + 2]) << 8) | UInt32(d[o + 3])
    }

    private func u64(_ d: Data, _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(d[o + i]) }
        return v
    }
}
