import AVFoundation
import Foundation
import SwiftUI
import UIKit

/// 所有相机页面与 Overlay 共用完整等比显示规则，避免页面间裁剪放大不一致。
enum CameraPreviewLayout {
    static let gravity: AVLayerVideoGravity = .resizeAspect

    static func scale(view: CGSize, image: CGSize) -> CGFloat {
        min(view.width / image.width, view.height / image.height)
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        // VoiceOver 读取页面状态和操作按钮即可；原始相机图层本身没有可操作语义。
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.previewLayer.session = session
        view.previewLayer.videoGravity = CameraPreviewLayout.gravity
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        view.previewLayer.videoGravity = CameraPreviewLayout.gravity
        guard let connection = view.previewLayer.connection else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
