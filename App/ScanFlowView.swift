import SwiftUI
import PhotosUI

struct CardCollectionRow: View {
    let card: Card
    var namespace: Namespace.ID?
    var body: some View {
        HStack(spacing: 14) {
            photo.frame(width: 56,height: 78).clipShape(RoundedRectangle(cornerRadius: 7))
                .modifier(CardFlight(id: "photo-" + card.id.uuidString,namespace: namespace))
            VStack(alignment: .leading,spacing: 4) {
                Text(card.identity.player.isEmpty ? "Unidentified card" : card.identity.player).font(.headline).lineLimit(1)
                Text(card.identity.team.isEmpty ? "Tap to review details" : card.identity.team).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text([card.identity.manufacturer,card.identity.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if let note = card.scanNote, card.collectionValue == nil { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }.modifier(CardFlight(id: "identity-" + card.id.uuidString,namespace: namespace))
            Spacer(minLength: 0)
            VStack(alignment: .trailing,spacing: 4) {
                if let value = card.collectionValue { Text(value,format: .currency(code:"USD")).font(.subheadline.bold()); Text(card.valueLabel).font(.caption2).foregroundStyle(.secondary) }
                else { Text("—").font(.headline); Text("Not valued").font(.caption2).foregroundStyle(.secondary) }
            }
        }.padding(.vertical,5).accessibilityElement(children: .combine)
    }
    private var photo: some View { PhotoView(data: card.thumbnail ?? card.front) }
}
struct CardFlight: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace { content.matchedGeometryEffect(id:id,in:namespace) } else { content }
    }
}

struct HolographicCard: View {
    let front: Data?
    let back: Data?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30,paused:reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSince(began)
            let angle = reduceMotion ? 0 : time * 43
            let frontVisible = cos(angle * .pi / 180) >= 0
            ZStack {
                face(front,time:time).opacity(frontVisible ? 1:0)
                face(back,time:time).rotation3DEffect(.degrees(180),axis:(x:0,y:1,z:0)).opacity(frontVisible ? 0:1)
            }
            .rotation3DEffect(.degrees(angle),axis:(x:0,y:1,z:0),perspective:0.45)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : sin(time*0.65)*7),axis:(x:1,y:0,z:0))
            .shadow(color:.cyan.opacity(0.15),radius:28,y:16)
        }.accessibilityLabel("Front and back of your scanned card")
    }
    private func face(_ data: Data?, time: Double) -> some View {
        GeometryReader { geometry in
            PhotoView(data:data).frame(width:geometry.size.width,height:geometry.size.height)
                .background(.black).clipShape(RoundedRectangle(cornerRadius:16))
                .colorEffect(ShaderLibrary.cardFoil(.float2(geometry.size),.float(reduceMotion ? 0:Float(time))),isEnabled:!reduceMotion)
                .overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.45),lineWidth:1))
        }
    }
}

struct ScanFlowView: View {
    @ObservedObject var model: ScanFlowModel
    let namespace: Namespace.ID
    let onCancel: () -> Void
    let onCommit: (Card) -> Void
    @StateObject private var camera = AutoScanCamera()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var loadingPhoto = false
    @State private var discard = false
    @State private var showIdentity = false
    private var compact: Bool { model.stage == .compact || model.stage == .ready }
    var body: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.035,green:0.055,blue:0.11),.black],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
            if model.scanning { captureScreen.transition(.opacity) }
            else { revealScreen.transition(.opacity) }
            VStack {
                HStack {
                    Text(model.scanning ? "ADD TO YOUR COLLECTION" : "CARD LEDGER").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button { if model.stage == .front { close() } else { discard = true } } label: { Image(systemName:"xmark").font(.body.bold()).frame(width:44,height:44).background(.white.opacity(0.1),in:Circle()) }.accessibilityLabel("Cancel scan")
                }
                Spacer()
            }.padding(.horizontal,24).padding(.top,12)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .onAppear { setupCamera() }
            .onDisappear { camera.onCapture = nil; camera.stop(); model.cancel() }
            .onChange(of:model.stage) { _,stage in
                if stage == .back { UIImpactFeedbackGenerator(style:.light).impactOccurred(); camera.armBack() }
                if !model.scanning { camera.stop() }
                if stage == .revealing { withAnimation(reduceMotion ? .easeOut(duration:0.2) : .spring(duration:model.services.revealDuration,bounce:0.22)) { showIdentity = true } }
                if stage == .ready { onCommit(model.card) }
            }
            .onChange(of:scenePhase) { _,phase in
                if phase == .active && model.scanning && !choosingPhoto && !loadingPhoto && !model.importing { camera.start() } else { camera.suspend() }
            }
            .photosPicker(isPresented:$choosingPhoto,selection:$photo,matching:.images)
            .onChange(of:choosingPhoto) { _,open in
                if open { camera.suspend() }
                else if photo == nil { loadingPhoto = false; if model.scanning { camera.start() } }
            }
            .onChange(of:photo) { _,item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type:Data.self) { model.importPhoto(data) }
                    else { model.captureError = "That photo could not be opened. Please choose another."; if model.scanning { camera.start() } }
                    loadingPhoto = false
                }
            }
            .onChange(of:model.importing) { _,busy in if !busy && model.scanning && !choosingPhoto { camera.start() } }
            .confirmationDialog("Discard this scan?",isPresented:$discard,titleVisibility:.visible) { Button("Discard scan",role:.destructive,action:close); Button("Keep scanning",role:.cancel) {} }
    }
    private var captureScreen: some View {
        VStack(spacing:16) {
            Spacer(minLength:70)
            HStack(spacing:8) {
                Capsule().fill(.cyan).frame(width:36,height:4)
                Capsule().fill(model.stage == .back ? .cyan : .white.opacity(0.2)).frame(width:36,height:4)
            }
            Text(model.stage == .front ? "Scan front of card" : "Scan back of card").font(.system(size:30,weight:.bold,design:.rounded)).accessibilityIdentifier("scan.instruction")
            Text(model.stage == .front ? "Hold steady. We’ll capture it automatically." : "Lift the card out of view, flip it, then hold steady.").font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center).padding(.horizontal)
            GeometryReader { proxy in
                let width = min(proxy.size.width,proxy.size.height*9/16)
                let height = width*16/9
                ZStack {
                    LiveCardPreview(camera:camera)
                    RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[8,6])).padding(.horizontal,width*0.14).padding(.vertical,height*0.14)
                    if let rectangle = camera.rectangle {
                        Path { path in path.addLines(rectangle.points.map { CGPoint(x:$0.x*width,y:$0.y*height) }); path.closeSubpath() }.stroke(.cyan,lineWidth:3).shadow(color:.cyan.opacity(0.7),radius:8)
                    }
                }.frame(width:width,height:height).clipShape(RoundedRectangle(cornerRadius:24)).frame(maxWidth:.infinity,maxHeight:.infinity)
            }.padding(.horizontal,20)
            if model.importing { ProgressView("Finding card edges…").tint(.white) }
            if let error = model.captureError ?? camera.message { Text(error).font(.caption).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal) }
            Button { photo = nil; loadingPhoto = true; camera.suspend(); choosingPhoto = true } label: { Label("Use a photo instead",systemImage:"photo.on.rectangle").font(.subheadline) }.disabled(model.importing || loadingPhoto).padding(.bottom,24)
        }
    }
    private var revealScreen: some View {
        VStack(spacing:24) {
            Spacer()
            if compact {
                CardCollectionRow(card:model.card,namespace:namespace).padding(18).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:22)).padding(.horizontal,20)
            } else {
                HolographicCard(front:model.card.thumbnail ?? model.card.front,back:model.card.backCorrected ?? model.card.back)
                    .frame(width:230,height:322).matchedGeometryEffect(id:"photo-"+model.id.uuidString,in:namespace)
                VStack(spacing:8) {
                    Text(model.player).font(.system(size:32,weight:.bold,design:.rounded)).multilineTextAlignment(.center)
                    Text(model.team).font(.title3).foregroundStyle(.cyan)
                    Text([model.card.identity.manufacturer,model.card.identity.year].filter { !$0.isEmpty }.joined(separator:" · ")).font(.caption).foregroundStyle(.white.opacity(0.5))
                }.matchedGeometryEffect(id:"identity-"+model.id.uuidString,in:namespace)
                    .opacity(showIdentity ? 1:0).offset(y:showIdentity ? 0:24).scaleEffect(showIdentity ? 1:0.92).blur(radius:showIdentity ? 0:8)
                VStack(spacing:10) {
                    if model.stage == .identifying { Text("Reading both sides").font(.subheadline).foregroundStyle(.white.opacity(0.6)).accessibilityIdentifier("scan.identifying") }
                    if model.showPriceSpinner { ProgressView().tint(.cyan); Text("Finding comparable sales").font(.caption).foregroundStyle(.white.opacity(0.6)).accessibilityIdentifier("scan.priceLoading") }
                    if showIdentity && !model.pricePending {
                        if let value = model.card.research?.estimate { Text(value,format:.currency(code:"USD")).font(.title2.bold()) }
                        else { Text(model.card.scanNote ?? "Price unavailable").font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center) }
                    }
                }.frame(minHeight:55)
            }
            if let error = model.saveError { Text(error).font(.caption); Button("Retry saving") { onCommit(model.card) }.buttonStyle(.borderedProminent) }
            Spacer()
        }.padding(.horizontal,12)
    }
    private func setupCamera() {
        camera.onCapture = { face in guard model.scanning, !model.importing, !loadingPhoto else { return }; model.receive(face) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_SCAN_FIXTURE"] == "1" {
            Task {
                for name in ["FRONT","BACK"] {
                    try? await Task.sleep(for:.seconds(1))
                    if let face = try? await Imaging.detectCard(ScanFixture.image(label:name)) { model.receive(face) }
                }
            }
            return
        }
        #endif
        camera.start()
    }
    private func close() { model.cancel(); camera.stop(); onCancel() }
}

#if DEBUG
enum ScanFixture {
    static func image(label:String) -> Data {
        UIGraphicsImageRenderer(size:CGSize(width:600,height:900)).image { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x:0,y:0,width:600,height:900))
            UIColor.white.setFill(); context.fill(CGRect(x:110,y:180,width:380,height:532))
            (label as NSString).draw(at:CGPoint(x:145,y:300),withAttributes:[.font:UIFont.boldSystemFont(ofSize:34),.foregroundColor:UIColor.black])
        }.jpegData(compressionQuality:0.9)!
    }
}
#endif
