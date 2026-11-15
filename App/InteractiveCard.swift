import SwiftUI
import UIKit

struct InspectedCardFace: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
    let origin: CGRect
    let initialZoom: CGFloat
}

struct HolographicCard: View {
    let front: Data?
    let back: Data?
    var rotationSpeed: Double = 43
    var onInteractionChanged: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = CardMotion()
    @State private var inspected: InspectedCardFace?
    @State private var pinchScale: CGFloat = 1
    private var now: TimeInterval { Date.timeIntervalSinceReferenceDate }
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval:1.0/30,paused:motion.mode != .spinning || scenePhase != .active)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let angle = motion.angle(at:time,speed:rotationSpeed)
                let isFront = CardMotion.frontVisible(at:angle)
                ZStack {
                    face(front,time:time).opacity(isFront ? 1:0)
                    face(back,time:time).rotation3DEffect(.degrees(180),axis:(x:0,y:1,z:0)).opacity(isFront ? 0:1)
                }
                .rotation3DEffect(.degrees(angle),axis:(x:0,y:1,z:0),perspective:0.45)
                .rotation3DEffect(.degrees(motion.mode == .spinning && !reduceMotion ? sin(time*0.65)*7 : motion.pitch),axis:(x:1,y:0,z:0))
                .scaleEffect(pinchScale)
                .shadow(color:.cyan.opacity(0.13),radius:28,y:16)
            }
            .overlay {
                CardGestureSurface(canInspect:motion.canInspect,onTap:toggle,
                    onPan:{ translation,velocity,state in pan(translation,velocity,state) },
                    onPinch:{ scale,state in pinch(scale,state,frame:geometry.frame(in:.global)) })
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("Card viewer")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Tap to pause or resume. Swipe a paused card to flip. Drag to rotate. Pinch a paused card to inspect.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle() }
            .accessibilityAction(named:Text("Flip card")) {
                withAnimation(.easeInOut(duration:0.35)) {
                    if motion.mode == .spinning { motion.pause(at:now,speed:rotationSpeed) }
                    motion.flip(); onInteractionChanged(true)
                }
            }
            .accessibilityAction(named:Text("Inspect face")) { inspect(frame:geometry.frame(in:.global),zoom:1) }
            .overlay(alignment:.bottom) {
                Text(motion.mode == .paused ? "Swipe to flip · Pinch to enlarge" : motion.mode == .dragging ? "Release to spin" : "Tap to pause · Drag to rotate")
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    .offset(y:22).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onAppear { if reduceMotion { motion.pause(at:now,speed:rotationSpeed) } }
        .onChange(of:reduceMotion) { _,reduce in if reduce { motion.pause(at:now,speed:rotationSpeed) } }
        .background(CardInspectionPresenter(face:$inspected,onClosed:{
            if !reduceMotion { motion.resume(at:now) }
            onInteractionChanged(false)
        }).frame(width:0,height:0))
    }

    private var accessibilityValue: String {
        let side = CardMotion.frontVisible(at:motion.angle(at:now,speed:rotationSpeed)) ? "Front" : "Back"
        return side + (motion.mode == .paused ? ", paused" : motion.mode == .dragging ? ", rotating manually" : ", spinning")
    }
    private func toggle() {
        withAnimation(.easeInOut(duration:0.25)) {
            if motion.mode == .paused && !reduceMotion { motion.resume(at:now); onInteractionChanged(false) }
            else { motion.pause(at:now,speed:rotationSpeed); onInteractionChanged(true) }
        }
    }
    private func pan(_ translation: CGPoint,_ velocity: CGPoint,_ state: UIGestureRecognizer.State) {
        switch state {
        case .began: motion.beginDrag(at:now,speed:rotationSpeed); onInteractionChanged(true)
        case .changed: motion.drag(x:translation.x,y:translation.y)
        case .ended:
            motion.drag(x:translation.x,y:translation.y)
            withAnimation(.easeOut(duration:0.25)) {
                motion.endDrag(x:translation.x,y:translation.y,velocityX:velocity.x,at:now,allowAutoSpin:!reduceMotion)
                onInteractionChanged(motion.mode == .paused)
            }
        case .cancelled,.failed:
            motion.cancelDrag(at:now,allowAutoSpin:!reduceMotion); onInteractionChanged(motion.mode == .paused)
        default: break
        }
    }
    private func pinch(_ scale: CGFloat,_ state: UIGestureRecognizer.State,frame: CGRect) {
        guard motion.canInspect else { return }
        if motion.mode == .dragging { motion.cancelDrag(at:now,allowAutoSpin:false) }
        switch state {
        case .began,.changed: pinchScale = min(1.25,max(0.9,scale)); onInteractionChanged(true)
        case .ended:
            pinchScale = 1
            if scale > 1.08 { inspect(frame:frame,zoom:scale) }
        case .cancelled,.failed: pinchScale = 1
        default: break
        }
    }
    private func inspect(frame: CGRect,zoom: CGFloat) {
        motion.pause(at:now,speed:rotationSpeed)
        let isFront = CardMotion.frontVisible(at:motion.baseAngle)
        guard let data = isFront ? front : back, let image = UIImage(data:data) else { return }
        let scale = min(frame.width/image.size.width,frame.height/image.size.height)
        let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
        let origin = CGRect(x:frame.midX-size.width/2,y:frame.midY-size.height/2,width:size.width,height:size.height)
        onInteractionChanged(true)
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { inspected = InspectedCardFace(data:data,name:isFront ? "Front":"Back",origin:origin,initialZoom:min(8,max(1,zoom))) }
    }
    private func face(_ data: Data?,time: Double) -> some View {
        GeometryReader { geometry in
            let imageSize = data.flatMap { UIImage(data:$0)?.size } ?? CGSize(width:5,height:7)
            let scale = min(geometry.size.width/imageSize.width,geometry.size.height/imageSize.height)
            let size = CGSize(width:imageSize.width*scale,height:imageSize.height*scale)
            PhotoView(data:data).frame(width:size.width,height:size.height)
                .background(.black).clipShape(RoundedRectangle(cornerRadius:14))
                .colorEffect(ShaderLibrary.cardFoil(.float2(size),.float(reduceMotion || motion.mode != .spinning ? 0:Float(time.truncatingRemainder(dividingBy:3600)))),isEnabled:!reduceMotion && motion.mode == .spinning)
                .overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.3),lineWidth:0.75))
                .position(x:geometry.size.width/2,y:geometry.size.height/2)
        }
    }
}

/// UIKit arbitration keeps one-finger drags on the card distinct from the
/// surrounding page's scrolling, and two-finger inspection distinct from drag.
private struct CardGestureSurface: UIViewRepresentable {
    var canInspect: Bool
    var onTap: () -> Void
    var onPan: (CGPoint,CGPoint,UIGestureRecognizer.State) -> Void
    var onPinch: (CGFloat,UIGestureRecognizer.State) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:))); pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap)); tap.require(toFail:pan)
        let pinch = UIPinchGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pinch(_:))); pinch.delegate = context.coordinator
        view.addGestureRecognizer(pan); view.addGestureRecognizer(tap); view.addGestureRecognizer(pinch)
        context.coordinator.panRecognizer = pan
        return view
    }
    func updateUIView(_ view:UIView,context:Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async { [weak view,weak coordinator = context.coordinator] in
            guard let view,let coordinator,let pan = coordinator.panRecognizer else { return }
            var ancestor = view.superview
            while let current = ancestor {
                if let scroll = current as? UIScrollView, coordinator.parentScroll !== scroll {
                    scroll.panGestureRecognizer.require(toFail:pan); coordinator.parentScroll = scroll; break
                }
                ancestor = current.superview
            }
        }
    }
    final class Coordinator: NSObject,UIGestureRecognizerDelegate {
        var parent: CardGestureSurface
        weak var panRecognizer: UIPanGestureRecognizer?
        weak var parentScroll: UIScrollView?
        init(_ parent:CardGestureSurface) { self.parent = parent }
        @objc func tap() { parent.onTap() }
        @objc func pan(_ gesture:UIPanGestureRecognizer) { parent.onPan(gesture.translation(in:gesture.view),gesture.velocity(in:gesture.view),gesture.state) }
        @objc func pinch(_ gesture:UIPinchGestureRecognizer) { parent.onPinch(gesture.scale,gesture.state) }
        func gestureRecognizerShouldBegin(_ gesture:UIGestureRecognizer) -> Bool { parent.canInspect }
    }
}
