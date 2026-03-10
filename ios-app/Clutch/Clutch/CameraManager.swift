import AVFoundation
import Foundation
import UIKit

/// Manages the phone camera for video frame capture.
/// Captures one JPEG frame every 500 ms and delivers it via `onFrame`.
final class CameraManager: NSObject {

    var onFrame: ((Data) -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "clutch.camera", qos: .userInitiated)
    private var lastFrameTime: Date = .distantPast
    private let frameInterval: TimeInterval = 0.5

    // MARK: - Start / Stop

    func requestAccessAndStart() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return false }
        } else if status != .authorized {
            return false
        }
        await withCheckedContinuation { continuation in
            queue.async {
                self.setupSession()
                continuation.resume()
            }
        }
        return true
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Private

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }
        onFrame?(jpegData)
    }
}
