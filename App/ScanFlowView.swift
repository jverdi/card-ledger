import SwiftUI
import PhotosUI

enum CardRowText {
    static func name(_ raw: String) -> String { CardMetadata.title(raw) }
    static func brand(_ raw: String) -> String { CardMetadata.manufacturer(raw) }
    static func metadata(_ identity: Identity) -> String {
        let brand = brand(identity.manufacturer)
        let set = name(identity.set)
        let product: String
        if set.isEmpty { product = brand }
        else if brand.isEmpty || set.localizedCaseInsensitiveCompare(brand) == .orderedSame || set.lowercased().hasPrefix(brand.lowercased()+" ") { product = set }
        else if brand.lowercased().hasPrefix(set.lowercased()+" ") { product = brand }
        else { product = brand + " " + set }
        return [identity.year.trimmingCharacters(in:.whitespacesAndNewlines),product.replacingOccurrences(of:" - ",with:" ")].filter { !$0.isEmpty }.joined(separator:" · ")
    }
}

struct CardCollectionRow: View {
    let card: Card
    var namespace: Namespace.ID?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.body) private var thumbnailWidth = 72.0
    private var player: String { card.identity.player.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Unidentified card" : CardRowText.name(card.identity.player) }
    private var team: String { CardRowText.name(card.identity.team) }
    private var metadata: String { CardRowText.metadata(card.identity) }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:14) {
                    thumbnail
                    details
                }
            } else {
                HStack(alignment:.center,spacing:16) {
                    thumbnail
                    details
                }
            }
        }
        .padding(.vertical,10)
        .frame(maxWidth:.infinity,alignment:.leading)
        .contentShape(Rectangle())
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(accessibilitySummary)
    }
    private var thumbnail: some View {
        PhotoView(data:card.thumbnail ?? card.front)
            .frame(width:min(thumbnailWidth,92),height:min(thumbnailWidth,92)*1.4)
            .background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:8))
            .clipShape(RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.primary.opacity(0.08),lineWidth:0.5))
            .shadow(color:.black.opacity(0.12),radius:3,y:2)
            .modifier(CardFlight(id:"photo-"+card.id.uuidString,namespace:namespace))
            .accessibilityHidden(true)
    }
    private var details: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Text(player).font(.headline).foregroundStyle(.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                if !typeSize.isAccessibilitySize {
                    Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            if !team.isEmpty {
                Text(team).font(.subheadline).foregroundStyle(.secondary).padding(.top,3)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal:false,vertical:true)
            }
            if !metadata.isEmpty {
                Text(metadata).font(.caption).foregroundStyle(.secondary).padding(.top,9)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal:false,vertical:true)
            }
            valuation.padding(.top,8)
        }.modifier(CardFlight(id:"identity-"+card.id.uuidString,namespace:namespace))
    }
    @ViewBuilder private var valuation: some View {
        if let value = card.collectionValue {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    amount(value)
                    Text(card.valueLabel).font(.caption).foregroundStyle(.secondary).fixedSize()
                }
                VStack(alignment:.leading,spacing:3) {
                    amount(value)
                    Text(card.valueLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Label("Price unavailable",systemImage:"tag")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func amount(_ value: Double) -> some View {
        Text(value,format:.currency(code:"USD")).font(.subheadline.weight(.semibold))
            // Keep currency digits together at the largest accessibility sizes.
            // Other row text retains its full Dynamic Type size and wraps freely.
            .monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.5)
    }
    private var accessibilitySummary: String {
        let price = card.collectionValue.map { $0.formatted(.currency(code:"USD"))+", "+card.valueLabel } ?? "Price unavailable"
        return [player,team,metadata,price].filter { !$0.isEmpty }.joined(separator:", ")
    }
}

struct CardFlight: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace { content.matchedGeometryEffect(id:id,in:namespace) } else { content }
    }
}

struct ScanFlowView: View {
    @EnvironmentObject private var store: CollectionStore
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
    @State private var duplicateReview = false
    private var duplicates: [Card] { CardDuplicates.matches(for:model.card,in:store.cards) }
    @State private var showIdentity = false
    private var compact: Bool { model.stage == .compact || model.stage == .ready }
    var body: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.035,green:0.055,blue:0.11),.black],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
            if model.capturing { captureScreen.accessibilityHidden(model.stage == .frontCaptured).transition(.opacity) }
            else { revealScreen.transition(.opacity) }
            if model.stage == .frontCaptured { frontConfirmation.transition(.opacity) }
            VStack {
                HStack {
                    Text(model.capturing ? "ADD TO YOUR COLLECTION" : "CARD LEDGER").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button { if model.stage == .front { close() } else { discard = true } } label: { Image(systemName:"xmark").font(.body.bold()).frame(width:44,height:44).background(.white.opacity(0.1),in:Circle()) }.accessibilityLabel("Cancel scan")
                }
                Spacer()
            }.padding(.horizontal,24).padding(.top,12)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .onAppear { setupCamera() }
            .onDisappear { camera.onCapture = nil; camera.stop(); model.cancel() }
            .onChange(of:model.stage) { previousStage,stage in
                if stage == .frontCaptured {
                    camera.prepareBack()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIAccessibility.post(notification:.announcement,argument:"Front captured. Turn your card over.")
                }
                // Confirm the accepted back immediately, before recognition or pricing.
                // Restrict this to capture so resuming/retrying processing never buzzes.
                if previousStage == .back && stage == .identifying {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                if stage == .back {
                    camera.armBack()
                    if scenePhase == .active && !choosingPhoto && !loadingPhoto { startCamera() }
                }
                if !model.capturing { camera.stop() }
                if stage == .revealing { withAnimation(reduceMotion ? .easeOut(duration:0.2) : .spring(duration:model.services.revealDuration,bounce:0.22)) { showIdentity = true } }
                if stage == .ready { onCommit(model.card) }
            }
            .onChange(of:scenePhase) { _,phase in
                if phase == .active && model.capturing && !choosingPhoto && !loadingPhoto && !model.importing { startCamera() } else { camera.suspend() }
            }
            .photosPicker(isPresented:$choosingPhoto,selection:$photo,matching:.images)
            .onChange(of:choosingPhoto) { _,open in
                if open { camera.suspend() }
                else if photo == nil { loadingPhoto = false; if model.scanning { startCamera() } }
            }
            .onChange(of:photo) { _,item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type:Data.self) { model.importPhoto(data) }
                    else { model.captureError = "That photo could not be opened. Please choose another."; if model.scanning { startCamera() } }
                    loadingPhoto = false
                }
            }
            .onChange(of:model.importing) { _,busy in if !busy && model.scanning && !choosingPhoto { startCamera() } }
            .sheet(isPresented:$duplicateReview) {
                DuplicateScanReview(scanned:model.card,matches:duplicates,
                    addDuplicate:{ duplicateReview = false; model.continueToCollection(duplicateConfirmed:true) },
                    overwrite:{ id in duplicateReview = false; model.continueToCollection(replacing:id) },
                    discard:{ duplicateReview = false; close() })
            }
            .confirmationDialog("Discard this scan?",isPresented:$discard,titleVisibility:.visible) { Button("Discard scan",role:.destructive,action:close); Button("Keep scanning",role:.cancel) {} }
    }
    private var captureScreen: some View {
        VStack(spacing:16) {
            Spacer(minLength:70)
            HStack(spacing:8) {
                Capsule().fill(.cyan).frame(width:36,height:4)
                Capsule().fill(model.stage == .back ? .cyan : .white.opacity(0.2)).frame(width:36,height:4)
            }
            if model.stage == .back {
                HStack(spacing:8) {
                    PhotoView(data:model.card.thumbnail ?? model.card.front).frame(width:30,height:42).clipShape(RoundedRectangle(cornerRadius:3))
                    Label("Front captured",systemImage:"checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    Text("· 2 of 2").font(.caption).foregroundStyle(.secondary)
                }.accessibilityIdentifier("scan.frontSaved")
            }
            Text(model.stage == .back ? "Scan back of card" : "Scan front of card").font(.system(size:30,weight:.bold,design:.rounded)).accessibilityIdentifier("scan.instruction")
            Text(model.stage == .back ? "Turn the card over. We’ll capture the back automatically." : "Hold steady. We’ll capture it automatically.").font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center).padding(.horizontal)
            GeometryReader { proxy in
                let width = min(proxy.size.width,proxy.size.height*9/16)
                let height = width*16/9
                ZStack {
                    LiveCardPreview(camera:camera).clipShape(RoundedRectangle(cornerRadius:24))
                    VibrantCardGuide().accessibilityHidden(true).allowsHitTesting(false)
                    if let rectangle = camera.rectangle {
                        Path { path in path.addLines(rectangle.points.map { CGPoint(x:$0.x*width,y:$0.y*height) }); path.closeSubpath() }.stroke(.cyan,lineWidth:3).shadow(color:.cyan.opacity(0.7),radius:8)
                    }
                }.frame(width:width,height:height).frame(maxWidth:.infinity,maxHeight:.infinity)
            }.padding(.horizontal,20)
            if model.importing { ProgressView("Finding card edges…").tint(.white) }
            else {
                HStack(spacing:12) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.2),lineWidth:3)
                        Circle().trim(from:0,to:camera.holdProgress).stroke(.cyan,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))
                        Image(systemName:camera.waitingForFlip ? "arrow.triangle.2.circlepath":"viewfinder").font(.caption)
                    }.frame(width:32,height:32).accessibilityHidden(true)
                    Text(camera.guidance).font(.subheadline).multilineTextAlignment(.leading).accessibilityIdentifier("scan.cameraStatus")
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,28).frame(minHeight:44)
            }
            if let error = model.captureError ?? camera.message { Text(error).font(.caption).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal) }
            Button { photo = nil; loadingPhoto = true; camera.suspend(); choosingPhoto = true } label: { Label("Use a photo instead",systemImage:"photo.on.rectangle").font(.subheadline) }.disabled(model.importing || loadingPhoto).padding(.bottom,24)
        }
    }
    private var frontConfirmation: some View {
        VStack(spacing:22) {
            Spacer()
            Image(systemName:"checkmark.circle.fill").font(.system(size:64,weight:.semibold)).foregroundStyle(.green)
            Text("Front captured!").font(.system(size:34,weight:.bold,design:.rounded)).accessibilityIdentifier("scan.frontConfirmation")
            PhotoView(data:model.card.thumbnail ?? model.card.front)
                .frame(width:140,height:196).clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(.green.opacity(0.8),lineWidth:2))
                .shadow(color:.green.opacity(0.2),radius:24)
            Label("Turn your card over",systemImage:"arrow.triangle.2.circlepath").font(.title3.weight(.semibold))
            Text("The back scans automatically.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer()
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(red:0.025,green:0.075,blue:0.065).ignoresSafeArea())
    }
    private var revealScreen: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing:24) {
            Spacer()
            if compact {
                CardCollectionRow(card:model.card,namespace:namespace).padding(18).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:22)).padding(.horizontal,20)
            } else {
                HolographicCard(front:model.card.thumbnail ?? model.card.front,back:model.card.backCorrected ?? model.card.back,accessibilityID:"scan.cardReveal")
                    .frame(maxWidth:300).frame(height:322).matchedGeometryEffect(id:"photo-"+model.id.uuidString,in:namespace)
                CardIdentityHeader(identity:model.card.identity,placeholder:model.player)
                    .padding(.top,8).matchedGeometryEffect(id:"identity-"+model.id.uuidString,in:namespace)
                    .opacity(showIdentity ? 1:0).offset(y:showIdentity ? 0:24).scaleEffect(showIdentity ? 1:0.92).blur(radius:showIdentity ? 0:8)
                VStack(spacing:10) {
                    if model.stage == .identifying { Text("Reading both sides").font(.subheadline).foregroundStyle(.white.opacity(0.6)).accessibilityIdentifier("scan.identifying") }
                    if showIdentity && !model.pricePending {
                        if let value = model.card.pricing?.usableValue {
                            Text(value,format:.currency(code:"USD")).font(.title2.bold())
                            Link("CardPricer estimate",destination:CardPricerClient.website).font(.caption)
                        }
                        else { Text(model.card.scanNote ?? "Price unavailable").font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center) }
                    }
                    // Keep the notice and action slots in the layout throughout
                    // processing. Inserting them at completion recenters this
                    // stack and can move Continue during the user's first tap.
                    Label(duplicates.allSatisfy { CardDuplicates.exactMatch(model.card,$0) } ? "Already in your collection" : "Possible duplicate found",systemImage:"rectangle.on.rectangle")
                        .font(.subheadline).foregroundStyle(.orange).accessibilityIdentifier("scan.duplicate.notice")
                        .opacity(model.canContinue && !duplicates.isEmpty ? 1:0)
                        .accessibilityHidden(!model.canContinue || duplicates.isEmpty)
                    ZStack {
                        Button("Continue") {
                            #if DEBUG
                            print("Scan Continue activated; duplicate matches: \(duplicates.count)")
                            #endif
                            if duplicates.isEmpty { model.continueToCollection() }
                            else { duplicateReview = true }
                        }
                            .font(.headline).buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                            .controlSize(.large).accessibilityIdentifier("scan.continue")
                            .opacity(model.canContinue ? 1:0).disabled(!model.canContinue)
                            .accessibilityHidden(!model.canContinue)
                        VStack(spacing:6) {
                            ProgressView().tint(.cyan)
                            Text("Checking CardPricer").font(.caption).foregroundStyle(.white.opacity(0.6)).accessibilityIdentifier("scan.priceLoading")
                        }.opacity(model.showPriceSpinner ? 1:0).accessibilityHidden(!model.showPriceSpinner).allowsHitTesting(false)
                    }
                }.frame(minHeight:55)
            }
            if let error = model.saveError { Text(error).font(.caption); Button("Retry saving") { onCommit(model.card) }.buttonStyle(.borderedProminent); Button("Review save options",action:model.reviewSaveOptions) }
            Spacer()
        }.padding(.horizontal,12).frame(maxWidth:.infinity,minHeight:geometry.size.height)
        }.scrollIndicators(.hidden)
        }
    }
    private func startCamera() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_SCAN_FIXTURE"] == "1" { return }
        #endif
        camera.start()
    }
    private func setupCamera() {
        camera.onCapture = { face in guard model.scanning, !model.importing, !loadingPhoto else { return }; model.receive(face) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_SCAN_FIXTURE"] == "1" {
            Task {
                for name in ["FRONT","BACK"] {
                    try? await Task.sleep(for:.seconds(6))
                    if let face = try? await Imaging.detectCard(ScanFixture.image(label:name)) { model.receive(face) }
                }
            }
            return
        }
        #endif
        startCamera()
    }
    private func close() { model.cancel(); camera.stop(); onCancel() }
}

#if DEBUG
enum ScanFixture {
    static var identity: Identity {
        if ProcessInfo.processInfo.environment["CARD_LEDGER_NOISY_DUPLICATE_FIXTURE"] == "1" {
            return Identity(player:"Cam Schlittler",team:"New York Yankees",year:"2022",manufacturer:"Topps",set:"Cmp154977",number:"",variant:"")
        }
        return Identity(player:"UI Rookie",team:"Brooklyn",year:"2026",manufacturer:"Test Brand",set:"Test Set",number:"1",variant:"Base",grade:"Raw") }
    static func image(label:String) -> Data {
        UIGraphicsImageRenderer(size:CGSize(width:600,height:900)).image { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x:0,y:0,width:600,height:900))
            UIColor.white.setFill(); context.fill(CGRect(x:110,y:180,width:380,height:532))
            (label as NSString).draw(at:CGPoint(x:145,y:300),withAttributes:[.font:UIFont.boldSystemFont(ofSize:34),.foregroundColor:UIColor.black])
        }.jpegData(compressionQuality:0.9)!
    }
}
#endif

