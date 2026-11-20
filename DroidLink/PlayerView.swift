//
//  PlayerView.swift
//  DroidLink
//
//  Hosts the AVSampleBufferDisplayLayer that the video client enqueues into.
//

import SwiftUI
import AVFoundation

final class ScreenView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var screenLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        screenLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct PlayerView: UIViewRepresentable {
    let attach: (AVSampleBufferDisplayLayer) -> Void

    func makeUIView(context: Context) -> ScreenView {
        let v = ScreenView(frame: .zero)
        attach(v.screenLayer)
        return v
    }

    func updateUIView(_ uiView: ScreenView, context: Context) {}
}
