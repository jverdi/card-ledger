import SwiftUI
import UIKit

struct CardZoomView: View {
    let face: InspectedCardFace
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var closing = false
    @State private var zoom: CGFloat = 1
    @State private var requestedZoom: CGFloat?
    var body: some View {
        GeometryReader { geometry in
            let imageSize = UIImage(data:face.data)?.size ?? CGSize(width:5,height:7)
            let fit = min(geometry.size.width/imageSize.width,geometry.size.height/imageSize.height)
            let entryZoom = min(8,max(1,face.initialZoom*face.origin.width/max(1,imageSize.width*fit)))
            let initialScale = face.origin.width / max(1,imageSize.width*fit*(closing ? 1:entryZoom))
            ZStack {
                Color.black.opacity(entered ? 1:0).ignoresSafeArea()
                ZoomableCardImage(data:face.data,initialZoom:entryZoom,requestedZoom:$requestedZoom,zoom:$zoom,onClose:close)
                    .scaleEffect(entered || reduceMotion ? 1:initialScale)
                    .offset(x:entered || reduceMotion ? 0:face.origin.midX-geometry.frame(in:.global).midX,
                            y:entered || reduceMotion ? 0:face.origin.midY-geometry.frame(in:.global).midY)
                VStack {
                    HStack {
                        VStack(alignment:.leading,spacing:3) {
                            Text(face.name + " of card").font(.headline)
                            Text("Pinch to zoom · Pinch inward past fit to return").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:12)
                        Button(action:close) { Image(systemName:"xmark").frame(width:44,height:44).background(.ultraThinMaterial,in:Circle()) }
                            .accessibilityLabel("Return to rotating card").accessibilityIdentifier("card.zoom.close")
                    }
                    Spacer()
                    HStack(spacing:20) {
                        Button { requestedZoom = max(1,zoom/1.5) } label: { Image(systemName:"minus.magnifyingglass").frame(width:44,height:44) }.accessibilityLabel("Zoom out")
                        Text(zoom,format:.number.precision(.fractionLength(1))).monospacedDigit() + Text("×")
                        Button { requestedZoom = min(8,zoom*1.5) } label: { Image(systemName:"plus.magnifyingglass").frame(width:44,height:44) }.accessibilityLabel("Zoom in")
                    }.font(.subheadline.weight(.medium)).padding(.horizontal,12).background(.ultraThinMaterial,in:Capsule())
                }.padding(.horizontal,20).padding(.vertical,18)
                    .opacity(entered ? 1:0)
            }.foregroundStyle(.white)
                .onAppear { withAnimation(reduceMotion ? nil:.spring(response:0.38,dampingFraction:0.88)) { entered = true } }
        }.preferredColorScheme(.dark)
            .accessibilityAction(.escape,close)
    }
    private func close() {
        guard !closing else { return }; closing = true
        requestedZoom = 1
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for:.milliseconds(300)) }
            withAnimation(reduceMotion ? nil:.easeInOut(duration:0.24)) { entered = false }
            if !reduceMotion { try? await Task.sleep(for:.milliseconds(240)) }
            onClose()
        }
    }
}

private struct ZoomableCardImage: UIViewRepresentable {
    let data: Data
    let initialZoom: CGFloat
    @Binding var requestedZoom: CGFloat?
    @Binding var zoom: CGFloat
    let onClose: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> CardZoomScrollView {
        let scroll = CardZoomScrollView()
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8; scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never; scroll.backgroundColor = .clear
        scroll.accessibilityIdentifier = "card.zoom.canvas"
        scroll.accessibilityLabel = "Flat card face, pinch to zoom and drag to pan"
        let image = UIImageView(image:UIImage(data:data)); image.contentMode = .scaleAspectFit
        image.accessibilityIdentifier = "card.zoom.image"; image.isAccessibilityElement = false
        scroll.addSubview(image); context.coordinator.image = image; scroll.delegate = context.coordinator
        scroll.onLayout = { [weak coordinator = context.coordinator,weak scroll] in
            if let scroll { coordinator?.layout(scroll) }
        }
        scroll.pinchGestureRecognizer?.addTarget(context.coordinator,action:#selector(Coordinator.pinched(_:)))
        let doubleTap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        return scroll
    }
    func updateUIView(_ scroll:CardZoomScrollView,context:Context) {
        context.coordinator.parent = self
        if let requestedZoom {
            scroll.setZoomScale(requestedZoom,animated:true)
            DispatchQueue.main.async { self.requestedZoom = nil }
        }
    }
    final class Coordinator: NSObject,UIScrollViewDelegate {
        var parent: ZoomableCardImage
        var image: UIImageView?
        var lastSize = CGSize.zero
        var pinchBeganAt: CGFloat = 1
        init(_ parent:ZoomableCardImage) { self.parent = parent }
        func layout(_ scroll:UIScrollView) {
            guard scroll.bounds.size != lastSize,scroll.bounds.width > 0,scroll.bounds.height > 0,let image,let size = image.image?.size else { return }
            let first = lastSize == .zero, previous = scroll.zoomScale
            lastSize = scroll.bounds.size; scroll.setZoomScale(1,animated:false)
            let fit = min(lastSize.width/size.width,lastSize.height/size.height)
            image.frame = CGRect(origin:.zero,size:CGSize(width:size.width*fit,height:size.height*fit))
            scroll.contentSize = image.bounds.size
            scroll.setZoomScale(first ? parent.initialZoom:previous,animated:false)
            center(scroll)
            if first { scroll.contentOffset = CGPoint(x:max(-scroll.contentInset.left,(scroll.contentSize.width-scroll.bounds.width)/2),y:max(-scroll.contentInset.top,(scroll.contentSize.height-scroll.bounds.height)/2)) }
            DispatchQueue.main.async { self.parent.zoom = scroll.zoomScale }
        }
        func viewForZooming(in scrollView:UIScrollView) -> UIView? { image }
        func scrollViewDidZoom(_ scrollView:UIScrollView) {
            center(scrollView)
            scrollView.accessibilityValue = String(format:"%.0f percent",scrollView.zoomScale*100)
            DispatchQueue.main.async { self.parent.zoom = scrollView.zoomScale }
        }
        func center(_ scroll:UIScrollView) {
            let x = max(0,(scroll.bounds.width-scroll.contentSize.width)/2)
            let y = max(0,(scroll.bounds.height-scroll.contentSize.height)/2)
            scroll.contentInset = UIEdgeInsets(top:y,left:x,bottom:y,right:x)
        }
        @objc func pinched(_ gesture:UIPinchGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if gesture.state == .began { pinchBeganAt = scroll.zoomScale }
            if gesture.state == .ended && pinchBeganAt*gesture.scale < 0.82 { parent.onClose() }
        }
        @objc func doubleTapped(_ gesture:UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            scroll.setZoomScale(scroll.zoomScale > 1.1 ? 1:2.5,animated:true)
        }
    }
}
private final class CardZoomScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
}

/// An over-full-screen presentation keeps the scan and its background work alive.
/// A normal fullScreenCover can trigger the scanner's onDisappear cancellation.
struct CardInspectionPresenter: UIViewControllerRepresentable {
    @Binding var face: InspectedCardFace?
    var onClosed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context:Context) -> UIViewController {
        let controller = UIViewController(); controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }
    func updateUIViewController(_ controller:UIViewController,context:Context) {
        context.coordinator.parent = self
        context.coordinator.update(controller)
    }
    static func dismantleUIViewController(_ controller:UIViewController,coordinator:Coordinator) {
        controller.presentedViewController?.dismiss(animated:false)
    }
    final class Coordinator: NSObject {
        var parent: CardInspectionPresenter
        private var presentedID: UUID?
        private var closing = false
        init(_ parent:CardInspectionPresenter) { self.parent = parent }
        func update(_ controller:UIViewController) {
            if let face = parent.face, presentedID == nil {
                guard controller.view.window != nil else {
                    DispatchQueue.main.async { [weak self,weak controller] in if let controller { self?.update(controller) } }
                    return
                }
                presentedID = face.id
                let host = UIHostingController(rootView:CardZoomView(face:face,onClose:{ [weak self] in self?.parent.face = nil }))
                host.view.backgroundColor = .clear; host.overrideUserInterfaceStyle = .dark
                host.modalPresentationStyle = .overFullScreen
                controller.present(host,animated:false)
            } else if parent.face == nil, presentedID != nil, !closing {
                closing = true
                controller.dismiss(animated:false) { [weak self] in
                    guard let self else { return }
                    self.presentedID = nil; self.closing = false; self.parent.onClosed()
                }
            }
        }
    }
}
