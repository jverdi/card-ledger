import SwiftUI
import AVFoundation
import Vision
import CoreImage

struct CardRectangle: Equatable {
    var points: [CGPoint] // top-left, top-right, bottom-right, bottom-left; display coordinates
    var confidence: Float
    var pixelSize: CGSize
    var crop: CropSelection { CropSelection(points: points.map { CropPoint(x: $0.x, y: $0.y) }) }
    var likelyCard: Bool {
        guard points.count == 4, confidence >= 0.8, crop.valid,
              points.allSatisfy({ $0.x > 0.025 && $0.x < 0.975 && $0.y > 0.025 && $0.y < 0.975 }) else { return false }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot((a.x-b.x)*pixelSize.width, (a.y-b.y)*pixelSize.height) }
        let width = (distance(points[0], points[1]) + distance(points[3], points[2])) / 2
        let height = (distance(points[0], points[3]) + distance(points[1], points[2])) / 2
        let aspect = min(width,height) / max(width,height)
        let area = abs(zip(points, Array(points.dropFirst()) + [points[0]]).reduce(CGFloat.zero) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }) / 2
        return (0.55...0.84).contains(aspect) && (0.12...0.88).contains(area)
    }
    func movement(from other: CardRectangle) -> CGFloat {
        guard other.points.count == points.count else { return 1 }
        return zip(points,other.points).map { hypot($0.x-$1.x,$0.y-$1.y) }.max() ?? 1
    }
}

// Frame timestamps, not callback count, define the hold. A latch prevents repeated captures.
struct CaptureGate {
    private var anchor: CardRectangle?
    private var since: TimeInterval?
    private var frames = 0
    private var latched = false
    private var requiresDeparture = false
    private var missingSince: TimeInterval?
    mutating func reset(requireDeparture: Bool = false) {
        anchor = nil; since = nil; frames = 0; latched = false
        requiresDeparture = requireDeparture; missingSince = nil
    }
    mutating func observe(_ rectangle: CardRectangle?, at time: TimeInterval, focused: Bool = true) -> Bool {
        let candidate = rectangle.flatMap { $0.likelyCard ? $0 : nil }
        if requiresDeparture {
            if candidate == nil {
                if missingSince == nil { missingSince = time }
                if time - (missingSince ?? time) >= 0.35 { requiresDeparture = false }
            } else { missingSince = nil }
            return false
        }
        guard !latched, let candidate, focused else { anchor = nil; since = nil; frames = 0; return false }
        if let anchor, candidate.movement(from: anchor) < 0.018 {
            frames += 1
        } else { anchor = candidate; since = time; frames = 1 }
        if frames >= 6 && time - (since ?? time) >= 0.8 { latched = true; return true }
        return false
    }
}

struct CapturedFace {
    let original: Data
    let crop: CropSelection
}

final class AutoScanCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var rectangle: CardRectangle?
    @Published var message: String?
    @Published var ready = false
    var onCapture: ((CapturedFace) -> Void)?
    private let queue = DispatchQueue(label: "CardLedger.camera", qos: .userInitiated)
    private let context = CIContext()
    private var device: AVCaptureDevice?
    private var configured = false
    private var enabled = false
    private var wanted = false
    private var awaitingBack = false
    private var generation = 0
    private var gate = CaptureGate()
    private var lastFrame = 0.0

    func start() {
        queue.async { self.wanted = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.configureAndStart() }
                else { self?.publishError("Camera access is off. Enable it in Settings, or use a photo below.") }
            }
        default: publishError("Camera access is off. Enable it in Settings, or use a photo below.")
        }
    }
    private func publishError(_ text: String) { DispatchQueue.main.async { self.message = text } }
    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self, self.wanted else { return }
            do {
                if !self.configured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        self.publishError("A camera is not available. Use a front photo, then a back photo."); return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .hd1920x1080
                    guard self.session.canAddInput(input) else { self.session.commitConfiguration(); return }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); return }
                    self.session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    self.session.commitConfiguration()
                    try device.lockForConfiguration()
                    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    device.unlockForConfiguration()
                    self.device = device; self.configured = true
                }
                self.enabled = true
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.ready = true; self.message = nil }
            } catch { self.publishError("The camera could not start. Use a photo below or try again.") }
        }
    }
    func armBack() { queue.async { self.generation += 1; self.awaitingBack = true; self.gate.reset(requireDeparture: true); self.enabled = true } }
    func suspend() { queue.async { self.generation += 1; self.wanted = false; self.enabled = false; self.gate.reset(requireDeparture: self.awaitingBack); if self.session.isRunning { self.session.stopRunning() } } }
    func stop() { suspend() }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard enabled, now-lastFrame >= 0.10, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 4; request.minimumConfidence = 0.8
        request.minimumAspectRatio = 0.45; request.maximumAspectRatio = 0.95
        request.minimumSize = 0.2; request.quadratureTolerance = 20
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            let candidates = (request.results ?? []).map { r in
                CardRectangle(points: [r.topLeft,r.topRight,r.bottomRight,r.bottomLeft].map { CGPoint(x: $0.x,y: 1-$0.y) }, confidence: r.confidence, pixelSize: size)
            }
            let rectangle = candidates.first(where: { $0.likelyCard })
            let currentGeneration = generation
            DispatchQueue.main.async { [weak self] in self?.rectangle = rectangle }
            if gate.observe(rectangle, at: now, focused: device?.isAdjustingFocus != true), let rectangle {
                guard let cg = context.createCGImage(CIImage(cvPixelBuffer: buffer), from: CGRect(origin: .zero,size:size)),
                      let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.95) else { gate.reset(); return }
                enabled = false
                let face = CapturedFace(original: data, crop: rectangle.crop)
                // Exactly the detected frame and corners are captured; no second moving-frame exposure.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        guard currentGeneration == self.generation else { return }
                        DispatchQueue.main.async { self.onCapture?(face) }
                    }
                }
            }
        } catch { gate.reset() }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
struct LiveCardPreview: UIViewRepresentable {
    let camera: AutoScanCamera
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(); view.preview.session = camera.session
        view.preview.videoGravity = .resizeAspect
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        return view
    }
    func updateUIView(_ view: CameraPreviewView, context: Context) {
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
