import SwiftUI
import AVFoundation
import Vision
import CoreImage

struct CardRectangle: Equatable {
    var points: [CGPoint] // top-left, top-right, bottom-right, bottom-left; display coordinates
    var confidence: Float
    var pixelSize: CGSize
    var crop: CropSelection { CropSelection(points: points.map { CropPoint(x: $0.x, y: $0.y) }) }
    var area: CGFloat {
        guard points.count == 4 else { return 0 }
        return abs((0..<4).reduce(CGFloat.zero) { sum, i in
            let a = points[i], b = points[(i+1)%4]
            return sum + a.x*b.y - b.x*a.y
        }) / 2
    }
    var center: CGPoint {
        CGPoint(x:points.map(\.x).reduce(0,+)/4,y:points.map(\.y).reduce(0,+)/4)
    }
    var cardProportions: Bool {
        guard points.count == 4, confidence >= 0.7, crop.valid,
              pixelSize.width > 0, pixelSize.height > 0 else { return false }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot((a.x-b.x)*pixelSize.width, (a.y-b.y)*pixelSize.height) }
        let width = (distance(points[0], points[1]) + distance(points[3], points[2])) / 2
        let height = (distance(points[0], points[3]) + distance(points[1], points[2])) / 2
        return (0.55...0.84).contains(min(width,height) / max(width,height)) && area >= 0.12
    }
    var likelyCard: Bool {
        cardProportions && area <= 0.88 &&
        points.allSatisfy { $0.x > 0.025 && $0.x < 0.975 && $0.y > 0.025 && $0.y < 0.975 }
    }
    func movement(from other: CardRectangle) -> CGFloat {
        guard other.points.count == points.count else { return 1 }
        return zip(points,other.points).map { hypot($0.x-$1.x,$0.y-$1.y) }.max() ?? 1
    }
}

// Use the same selection for the camera, imports and recovered legacy crops.
// Vision's result order is not a size ranking. Ask for all observations so a
// statistics table cannot consume the limit before the actual card is returned.
enum CardBoundaryDetector {
    static func request() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 0; request.minimumConfidence = 0.7
        request.minimumAspectRatio = 0.45; request.maximumAspectRatio = 0.95
        request.minimumSize = 0.2; request.quadratureTolerance = 25
        return request
    }
    static func rectangles(_ observations: [VNRectangleObservation], size: CGSize) -> [CardRectangle] {
        observations.map { r in
            CardRectangle(points:[r.topLeft,r.topRight,r.bottomRight,r.bottomLeft].map {
                CGPoint(x:Double($0.x),y:1.0-Double($0.y))
            },confidence:r.confidence,pixelSize:size)
        }
    }
    static func outermost(_ rectangles: [CardRectangle]) -> CardRectangle? {
        // Reject a clipped outer card instead of silently capturing its inner border.
        guard let outer = rectangles.filter(\.cardProportions).max(by:{ $0.area < $1.area }),
              outer.likelyCard else { return nil }
        return outer
    }
}

// Frame timestamps, not callback count, define the hold. A latch prevents repeats.
struct CaptureGate {
    private var anchor: CardRectangle?
    private var since: TimeInterval?
    private var frames = 0
    private var latched = false
    private(set) var requiresDeparture = false
    private(set) var progress = 0.0
    private var missingSince: TimeInterval?
    mutating func restartHold() { anchor = nil; since = nil; frames = 0; progress = 0 }
    mutating func reset(requireDeparture: Bool = false) {
        restartHold(); latched = false
        requiresDeparture = requireDeparture; missingSince = nil
    }
    mutating func observe(_ rectangle: CardRectangle?, at time: TimeInterval, focused: Bool = true, captureAllowed: Bool = true) -> Bool {
        let candidate = rectangle.flatMap { $0.likelyCard ? $0 : nil }
        if requiresDeparture {
            if candidate == nil {
                if missingSince == nil { missingSince = time }
                // A brief edge-on flip is enough. Keep observing during confirmation.
                if time - (missingSince ?? time) >= 0.15 { requiresDeparture = false }
            } else { missingSince = nil }
            return false
        }
        guard !latched, captureAllowed, let candidate, focused else { restartHold(); return false }
        if let anchor, candidate.movement(from: anchor) < 0.025 { frames += 1 }
        else { anchor = candidate; since = time; frames = 1 }
        progress = min(1,max(0,(time - (since ?? time))/0.8))
        if frames >= 6 && progress >= 1 { latched = true; return true }
        return false
    }
}

struct CapturedFace {
    let original: Data
    let crop: CropSelection
    var preview: Data? = nil
}

final class AutoScanCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var rectangle: CardRectangle?
    @Published var message: String?
    @Published var ready = false
    @Published var waitingForFlip = false
    @Published var holdProgress = 0.0
    @Published var guidance = "Position the whole card inside the guide."
    var onCapture: ((CapturedFace) -> Void)?
    private let queue = DispatchQueue(label: "CardLedger.camera", qos: .userInitiated)
    private let context = CIContext()
    private var device: AVCaptureDevice?
    private var configured = false
    private var enabled = false
    private var wanted = false
    private var captureAllowed = true
    private var frontCaptured = false
    private var subjectObserver: NSObjectProtocol?
    private var focusPoint = CGPoint(x:0.5,y:0.5)
    private var focusUpdatedAt = -Double.infinity
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
                    // Virtual cameras allow iOS to switch to a close-focusing macro lens.
                    let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera,.builtInDualWideCamera,.builtInWideAngleCamera]
                    guard let device = types.compactMap({ AVCaptureDevice.default($0,for:.video,position:.back) }).first else {
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
                    // Start at the wide camera's field of view, not the virtual device's ultra-wide 0.5x.
                    let wideZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 1
                    device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor,max(device.minAvailableVideoZoomFactor,CGFloat(wideZoom)))
                    if device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
                        device.setPrimaryConstituentDeviceSwitchingBehavior(.auto,restrictedSwitchingBehaviorConditions:[])
                    }
                    if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = false }
                    device.isSubjectAreaChangeMonitoringEnabled = true
                    device.unlockForConfiguration()
                    self.device = device; self.configured = true
                    self.subjectObserver = NotificationCenter.default.addObserver(forName:AVCaptureDevice.subjectAreaDidChangeNotification,object:device,queue:nil) { [weak self] _ in
                        self?.queue.async { [weak self] in
                            guard let self, self.enabled, CACurrentMediaTime()-self.focusUpdatedAt > 1 else { return }
                            self.refocus(at:self.focusPoint)
                        }
                    }
                }
                self.enabled = true
                self.refocus(at:self.focusPoint)
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.ready = true; self.message = nil }
            } catch { self.publishError("The camera could not start. Use a photo below or try again.") }
        }
    }
    deinit { if let subjectObserver { NotificationCenter.default.removeObserver(subjectObserver) } }
    // The live path starts observing the flip on the captured frame, before SwiftUI updates.
    // Photo imports have no live front to depart from, so don't impose that gate.
    func prepareBack() {
        queue.async {
            self.generation += 1
            if !self.frontCaptured { self.gate.reset(); self.frontCaptured = true }
            self.captureAllowed = false; self.enabled = true
        }
    }
    func armBack() {
        queue.async { self.captureAllowed = true; self.enabled = true; self.gate.restartHold(); self.refocus(at:self.focusPoint) }
    }
    func suspend() {
        queue.async {
            self.generation += 1; self.wanted = false; self.enabled = false
            // Preserve an already-observed flip through app interruptions and the photo picker.
            self.gate.restartHold()
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func stop() { suspend() }
    private func refocus(at point: CGPoint) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            focusPoint = point; focusUpdatedAt = CACurrentMediaTime(); gate.restartHold()
        } catch { publishError("Autofocus could not update. Move the phone slightly farther away and try again.") }
    }
    static func deviceFocusPoint(portraitPoint: CGPoint) -> CGPoint {
        // Video frames are physically rotated 90 degrees; device focus coordinates are landscape.
        CGPoint(x:portraitPoint.y,y:1-portraitPoint.x)
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard enabled, now-lastFrame >= 0.10, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let request = CardBoundaryDetector.request()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            let candidates = CardBoundaryDetector.rectangles(request.results ?? [],size:size)
            let rectangle = CardBoundaryDetector.outermost(candidates)
            if let rectangle {
                let point = Self.deviceFocusPoint(portraitPoint:rectangle.center)
                if hypot(point.x-focusPoint.x,point.y-focusPoint.y) > 0.08 && now-focusUpdatedAt > 0.8 { refocus(at:point) }
            }
            let focused = now-focusUpdatedAt > 0.35 && device?.isAdjustingFocus != true && device?.isAdjustingExposure != true
            let captured = gate.observe(rectangle,at:now,focused:focused,captureAllowed:captureAllowed)
            let waiting = gate.requiresDeparture, progress = gate.progress
            let hint: String
            if waiting { hint = "Flip the card, or briefly move it out of view." }
            else if !focused { hint = "Focusing… If blurry, move the phone a little farther away." }
            else if rectangle == nil { hint = "Show all four edges. Try a contrasting background." }
            else { hint = "Card found. Hold steady…" }
            let currentGeneration = generation
            DispatchQueue.main.async { [weak self] in
                self?.rectangle = rectangle; self?.waitingForFlip = waiting
                self?.holdProgress = progress; self?.guidance = hint
            }
            if captured, let rectangle {
                guard let cg = context.createCGImage(CIImage(cvPixelBuffer: buffer), from: CGRect(origin: .zero,size:size)),
                      let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.95) else { gate.reset(); return }
                if !frontCaptured {
                    frontCaptured = true; captureAllowed = false
                    gate.reset(requireDeparture:true)
                } else { enabled = false }
                let face = CapturedFace(original: data, crop: rectangle.crop, preview: try? Imaging.cropJPEG(cg, crop: rectangle.crop))
                // Exactly the detected frame and corners are captured; no second moving-frame exposure.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        guard currentGeneration == self.generation else { return }
                        DispatchQueue.main.async { self.onCapture?(face) }
                    }
                }
            }
        } catch { gate.restartHold() }
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
