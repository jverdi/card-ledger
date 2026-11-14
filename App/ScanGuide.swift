import SwiftUI
import UIKit

// Native vector artwork: no bitmap assets or camera-image processing.
enum ScanGuidePaths {
    static func cardRect(in bounds:CGRect) -> CGRect {
        let width = min(bounds.width * 0.78,bounds.height * 0.76 / 1.4)
        let size = CGSize(width:width,height:width * 1.4)
        return CGRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height)
    }
    static func outline(in bounds:CGRect) -> UIBezierPath {
        let rect = cardRect(in:bounds)
        return UIBezierPath(roundedRect:rect,cornerRadius:rect.width * 0.035)
    }
    static func player(in bounds:CGRect) -> UIBezierPath {
        let card = cardRect(in:bounds)
        let p = UIBezierPath()
        // Bat barrel over the right shoulder, tapering down to the grip.
        p.move(to:CGPoint(x:0.57,y:0.57))
        p.addLine(to:CGPoint(x:0.76,y:0.17))
        p.addCurve(to:CGPoint(x:0.83,y:0.14),controlPoint1:CGPoint(x:0.78,y:0.125),controlPoint2:CGPoint(x:0.81,y:0.12))
        p.addCurve(to:CGPoint(x:0.84,y:0.19),controlPoint1:CGPoint(x:0.85,y:0.15),controlPoint2:CGPoint(x:0.86,y:0.17))
        p.addLine(to:CGPoint(x:0.62,y:0.59))
        p.move(to:CGPoint(x:0.565,y:0.59)); p.addLine(to:CGPoint(x:0.54,y:0.64)); p.addLine(to:CGPoint(x:0.585,y:0.66)); p.addLine(to:CGPoint(x:0.61,y:0.61))
        // Cap crown, visor and seam.
        p.move(to:CGPoint(x:0.29,y:0.30))
        p.addCurve(to:CGPoint(x:0.54,y:0.265),controlPoint1:CGPoint(x:0.27,y:0.13),controlPoint2:CGPoint(x:0.54,y:0.13))
        p.addCurve(to:CGPoint(x:0.62,y:0.30),controlPoint1:CGPoint(x:0.59,y:0.27),controlPoint2:CGPoint(x:0.65,y:0.285))
        p.addCurve(to:CGPoint(x:0.29,y:0.30),controlPoint1:CGPoint(x:0.53,y:0.32),controlPoint2:CGPoint(x:0.39,y:0.26))
        p.move(to:CGPoint(x:0.425,y:0.175)); p.addCurve(to:CGPoint(x:0.45,y:0.275),controlPoint1:CGPoint(x:0.46,y:0.19),controlPoint2:CGPoint(x:0.46,y:0.23))
        // Face, ear and neck. Three-quarter profile looking toward the bat.
        p.move(to:CGPoint(x:0.32,y:0.31))
        p.addCurve(to:CGPoint(x:0.31,y:0.38),controlPoint1:CGPoint(x:0.26,y:0.30),controlPoint2:CGPoint(x:0.27,y:0.38))
        p.addCurve(to:CGPoint(x:0.43,y:0.455),controlPoint1:CGPoint(x:0.32,y:0.43),controlPoint2:CGPoint(x:0.39,y:0.46))
        p.addCurve(to:CGPoint(x:0.52,y:0.405),controlPoint1:CGPoint(x:0.48,y:0.45),controlPoint2:CGPoint(x:0.52,y:0.44))
        p.addLine(to:CGPoint(x:0.525,y:0.375)); p.addLine(to:CGPoint(x:0.555,y:0.365)); p.addLine(to:CGPoint(x:0.53,y:0.33)); p.addLine(to:CGPoint(x:0.53,y:0.31))
        p.move(to:CGPoint(x:0.475,y:0.332)); p.addLine(to:CGPoint(x:0.50,y:0.334))
        p.move(to:CGPoint(x:0.35,y:0.425)); p.addLine(to:CGPoint(x:0.35,y:0.49))
        p.move(to:CGPoint(x:0.49,y:0.44)); p.addLine(to:CGPoint(x:0.49,y:0.49))
        // Jersey shoulders and bust.
        p.move(to:CGPoint(x:0.35,y:0.49))
        p.addCurve(to:CGPoint(x:0.18,y:0.61),controlPoint1:CGPoint(x:0.28,y:0.51),controlPoint2:CGPoint(x:0.19,y:0.53))
        p.addLine(to:CGPoint(x:0.135,y:0.82)); p.addLine(to:CGPoint(x:0.84,y:0.82)); p.addLine(to:CGPoint(x:0.80,y:0.63))
        p.addCurve(to:CGPoint(x:0.65,y:0.53),controlPoint1:CGPoint(x:0.79,y:0.57),controlPoint2:CGPoint(x:0.71,y:0.54))
        p.move(to:CGPoint(x:0.55,y:0.515)); p.addLine(to:CGPoint(x:0.49,y:0.49))
        // Collar and button placket.
        p.move(to:CGPoint(x:0.32,y:0.505)); p.addLine(to:CGPoint(x:0.40,y:0.57)); p.addLine(to:CGPoint(x:0.43,y:0.53)); p.addLine(to:CGPoint(x:0.47,y:0.57)); p.addLine(to:CGPoint(x:0.52,y:0.505))
        p.move(to:CGPoint(x:0.43,y:0.575)); p.addLine(to:CGPoint(x:0.43,y:0.80))
        // Bent forearm and fingers wrapped around the bat handle.
        p.move(to:CGPoint(x:0.70,y:0.74)); p.addLine(to:CGPoint(x:0.58,y:0.62))
        p.addCurve(to:CGPoint(x:0.56,y:0.55),controlPoint1:CGPoint(x:0.53,y:0.61),controlPoint2:CGPoint(x:0.53,y:0.57))
        p.addCurve(to:CGPoint(x:0.635,y:0.55),controlPoint1:CGPoint(x:0.58,y:0.52),controlPoint2:CGPoint(x:0.63,y:0.52))
        p.addLine(to:CGPoint(x:0.655,y:0.59)); p.addLine(to:CGPoint(x:0.765,y:0.68))
        p.move(to:CGPoint(x:0.56,y:0.565)); p.addLine(to:CGPoint(x:0.61,y:0.585))
        p.move(to:CGPoint(x:0.55,y:0.59)); p.addLine(to:CGPoint(x:0.59,y:0.61))
        p.move(to:CGPoint(x:0.255,y:0.63)); p.addLine(to:CGPoint(x:0.23,y:0.80))
        p.apply(CGAffineTransform(scaleX:card.width,y:card.height))
        p.apply(CGAffineTransform(translationX:card.minX,y:card.minY))
        return p
    }
}
final class ScanGuideInk: UIView {
    var ink: UIColor? { didSet { setNeedsDisplay() } }
    var lineWidth: CGFloat = 2 { didSet { setNeedsDisplay() } }
    override init(frame:CGRect) { super.init(frame:frame); backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tintColorDidChange() { super.tintColorDidChange(); setNeedsDisplay() }
    override func draw(_ rect:CGRect) {
        (ink ?? tintColor ?? .white).setStroke()
        let border = ScanGuidePaths.outline(in:bounds)
        border.lineWidth = lineWidth; border.lineCapStyle = .round
        border.setLineDash([7,6],count:2,phase:0); border.stroke()
        let player = ScanGuidePaths.player(in:bounds)
        player.lineWidth = lineWidth; player.lineJoinStyle = .round; player.lineCapStyle = .round; player.stroke()
    }
}
final class VibrantGuideView: UIView {
    private let contrastInk = ScanGuideInk()
    private let blurEffect: UIBlurEffect
    private let blur: UIVisualEffectView
    private let vibrant: UIVisualEffectView
    private let ink = ScanGuideInk()
    private let effectMask = ScanGuideInk()
    var reduceTransparency = false { didSet { updateEffects() } }
    var increasedContrast = false { didSet { updateEffects() } }
    override init(frame:CGRect) {
        let effect = UIBlurEffect(style:.systemThinMaterialDark)
        blurEffect = effect
        blur = UIVisualEffectView(effect:effect)
        vibrant = UIVisualEffectView(effect:UIVibrancyEffect(blurEffect:effect,style:.label))
        super.init(frame:frame)
        isUserInteractionEnabled = false; isAccessibilityElement = false
        contrastInk.ink = UIColor.black.withAlphaComponent(0.7)
        effectMask.ink = .white
        addSubview(contrastInk); addSubview(blur)
        blur.contentView.addSubview(vibrant); vibrant.contentView.addSubview(ink)
        ink.tintColor = .white
        updateEffects()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateEffects() {
        blur.effect = reduceTransparency ? nil : blurEffect
        vibrant.effect = reduceTransparency ? nil : UIVibrancyEffect(blurEffect:blurEffect,style:.label)
        ink.ink = reduceTransparency ? .white : nil
        ink.lineWidth = increasedContrast ? 3 : 2
        contrastInk.lineWidth = ink.lineWidth + 2
        effectMask.lineWidth = ink.lineWidth + 1
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        for view in [contrastInk,blur,vibrant,ink,effectMask] { view.frame = bounds }
        // Mask the effect itself, never its parent: only the vector strokes blur.
        blur.mask = nil; blur.mask = effectMask
        contrastInk.setNeedsDisplay(); ink.setNeedsDisplay(); effectMask.setNeedsDisplay()
    }
}
struct VibrantCardGuide: UIViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func makeUIView(context:Context) -> VibrantGuideView { VibrantGuideView() }
    func updateUIView(_ view:VibrantGuideView,context:Context) {
        view.reduceTransparency = reduceTransparency
        view.increasedContrast = contrast == .increased
    }
}
