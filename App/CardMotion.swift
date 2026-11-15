import Foundation

/// The animation clock is anchored whenever interaction changes, avoiding jumps
/// when automatic rotation resumes after a drag or close inspection.
struct CardMotion {
    enum Mode { case spinning, paused, dragging }
    private(set) var mode: Mode = .spinning
    private(set) var baseAngle = 0.0
    private(set) var pitch = 0.0
    private var began = Date.timeIntervalSinceReferenceDate
    private var dragOrigin = 0.0
    private var dragWasPaused = false
    private var dragBegan = 0.0
    var canInspect: Bool { mode == .paused || (mode == .dragging && dragWasPaused) }
    func angle(at time: TimeInterval, speed: Double) -> Double {
        baseAngle + (mode == .spinning ? max(0,time-began)*speed : 0)
    }
    static func frontVisible(at angle: Double) -> Bool { cos(angle * .pi / 180) >= 0 }
    mutating func pause(at time: TimeInterval, speed: Double) {
        baseAngle = (angle(at:time,speed:speed)/180).rounded()*180
        pitch = 0; mode = .paused
    }
    mutating func resume(at time: TimeInterval) { began = time; pitch = 0; mode = .spinning }
    mutating func flip(direction: Double = 1) {
        baseAngle = (baseAngle/180).rounded()*180 + (direction >= 0 ? 180 : -180)
        pitch = 0; mode = .paused
    }
    mutating func beginDrag(at time: TimeInterval, speed: Double) {
        dragBegan = time
        dragWasPaused = mode == .paused
        dragOrigin = angle(at:time,speed:speed); baseAngle = dragOrigin; mode = .dragging
    }
    mutating func drag(x: Double, y: Double) {
        baseAngle = dragOrigin + x*0.65; pitch = min(25,max(-25,-y*0.12))
    }
    mutating func endDrag(x: Double, y: Double, velocityX: Double, at time: TimeInterval, allowAutoSpin: Bool = true) {
        if dragWasPaused && time-dragBegan < 0.38 && abs(x) >= 35 && abs(x) > abs(y)*1.3 && abs(velocityX) >= 400 {
            baseAngle = dragOrigin; flip(direction:x)
        } else if allowAutoSpin { resume(at:time) }
        else { pause(at:time,speed:0) }
    }
    mutating func cancelDrag(at time: TimeInterval, allowAutoSpin: Bool = true) {
        if dragWasPaused || !allowAutoSpin { pause(at:time,speed:0) } else { resume(at:time) }
    }
}
