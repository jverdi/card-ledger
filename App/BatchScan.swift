import SwiftUI

/// The durable collection index is also the inbox. Pending pairs never count as
/// owned cards and survive termination; only one recognition/pricing job runs.
@MainActor final class BatchScanCoordinator: ObservableObject {
    @Published private(set) var processingID: UUID?
    @Published var error: String?
    private var worker: Task<Void,Never>?
    var services = ScanServices.live()
    func pendingCount(_ store: CollectionStore) -> Int { store.cards.filter { $0.batchState == "queued" }.count }
    func duplicateCount(_ store: CollectionStore) -> Int { store.cards.filter { $0.batchState == "duplicate" }.count }
    func enqueue(_ card: Card, store: CollectionStore) throws {
        var saved = card; saved.batchState = "queued"
        try store.save(saved) // Do not advance the camera until both originals are on disk.
        resume(store:store)
    }
    func resume(store: CollectionStore) {
        guard worker == nil, error == nil else { return }
        worker = Task {
            defer { processingID = nil; worker = nil }
            while let pending = store.cards.filter({ $0.batchState == "queued" }).min(by: { $0.added < $1.added }) {
                processingID = pending.id
                var service = services; service.minimumReveal = 0; service.revealDuration = 0
                let model = ScanFlowModel(services:service)
                await model.resumeBatch(pending)
                guard !Task.isCancelled else { return }
                var result = model.card
                if pending.front == nil || pending.back == nil || pending.frontCrop == nil || pending.backCrop == nil {
                    result = pending; result.scanNote = "Incomplete saved scan. Review photos."
                }
                // Recheck against the latest collection, including earlier batch results.
                result.batchState = CardDuplicates.matches(for:result,in:store.cards).isEmpty ? nil : "duplicate"
                do { try store.save(result) }
                catch { self.error = "Processing paused. Your captured photos are saved. " + error.localizedDescription; return }
            }
        }
    }
    func retry(store: CollectionStore) { error = nil; resume(store:store) }
}

struct BatchScanView: View {
    @EnvironmentObject private var store: CollectionStore
    @ObservedObject var coordinator: BatchScanCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = AutoScanCamera()
    private enum Stage { case front, flip, back, reveal, failed }
    @State private var stage: Stage = .front
    @State private var pair = Card()
    @State private var captured = 0
    @State private var saveError: String?
    @State private var transition: Task<Void,Never>?
    @State private var review = false
    @State private var finishPartial = false
    private var backPressure: Bool { coordinator.pendingCount(store) >= 20 || coordinator.error != nil }
    var body: some View {
        ZStack {
            Color(red:0.025,green:0.045,blue:0.09).ignoresSafeArea()
            VStack(spacing:18) {
                HStack {
                    Label("BATCH SCAN",systemImage:"rectangle.stack").font(.caption.bold())
                    Spacer()
                    Button("Done") { if stage == .flip || stage == .back || stage == .failed { finishPartial = true } else { dismiss() } }
                        .accessibilityIdentifier("batch.done")
                }.padding(.top,12)
                Text(title).font(.system(size:30,weight:.bold,design:.rounded)).multilineTextAlignment(.center).accessibilityIdentifier("batch.instruction")
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                ZStack {
                    GeometryReader { proxy in
                        let width = min(proxy.size.width,proxy.size.height*9/16)
                        let height = width*16/9
                        ZStack {
                            LiveCardPreview(camera:camera)
                            VibrantCardGuide().allowsHitTesting(false)
                            if let rectangle = camera.rectangle {
                                Path { path in path.addLines(rectangle.points.map { CGPoint(x:$0.x*width,y:$0.y*height) }); path.closeSubpath() }.stroke(.cyan,lineWidth:3)
                            }
                        }.frame(width:width,height:height).clipShape(RoundedRectangle(cornerRadius:20)).frame(maxWidth:.infinity,maxHeight:.infinity)
                    }.opacity(stage == .reveal || stage == .failed ? 0 : 1)
                    if stage == .flip {
                        VStack(spacing:18) {
                            Image(systemName:"checkmark.circle.fill").font(.system(size:64)).foregroundStyle(.green)
                            Text("Front captured!").font(.title.bold())
                            Text("Flip your card").font(.title2)
                        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black.opacity(0.85))
                    }
                    if stage == .reveal || stage == .failed {
                        VStack(spacing:16) {
                            HolographicCard(front:pair.thumbnail ?? pair.front,back:pair.backCorrected ?? pair.back,rotationSpeed:180).frame(height:300)
                                .accessibilityIdentifier("batch.reveal")
                            Label(stage == .failed ? "Photos not yet saved" : "Both sides saved",systemImage:stage == .failed ? "exclamationmark.triangle":"checkmark.circle.fill")
                                .foregroundStyle(stage == .failed ? .orange:.green)
                        }
                    }
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.orange)
                    Button("Retry saving",action:savePair).buttonStyle(.borderedProminent)
                } else if let message = camera.message { Text(message).font(.caption).foregroundStyle(.orange) }
                else if stage == .front || stage == .back {
                    ProgressView(value:camera.holdProgress).tint(.cyan)
                    Text(backPressure ? "Processing queue is full or paused. Your photos are safe; scanning resumes when ready." : camera.guidance)
                        .font(.subheadline).multilineTextAlignment(.center).frame(minHeight:42)
                }
                Text("\(captured) captured · \(coordinator.pendingCount(store)) processing · \(coordinator.duplicateCount(store)) duplicates to review")
                    .font(.caption).accessibilityIdentifier("batch.count")
                Button("Review batch") { review = true }.disabled(stage == .failed || stage == .flip || stage == .back).padding(.bottom,12)
            }.padding(.horizontal,22)
        }.foregroundStyle(.white).tint(.cyan).preferredColorScheme(.dark)
            .onAppear { camera.continuous = true; camera.onCapture = receive; coordinator.resume(store:store); UIApplication.shared.isIdleTimerDisabled = true; startCamera() }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["CARD_LEDGER_BATCH_FIXTURE"] == "1" {
                    coordinator.services = ScanServices(process:{ PhotoResult(original:$0.original,corrected:$0.original,text:"Fixture") },identify:{ _ in ScanFixture.identity },lookup:{ _ in throw ScanFailure.timeout },canLookup:false)
                    for _ in 0..<2 {
                        do {
                            try await Task.sleep(for:.seconds(2))
                            receive(CapturedFace(original:ScanFixture.image(label:"FRONT"),crop:CropSelection()))
                            try await Task.sleep(for:.seconds(2))
                            receive(CapturedFace(original:ScanFixture.image(label:"BACK"),crop:CropSelection()))
                            try await Task.sleep(for:.seconds(3))
                        } catch { return }
                    }
                }
                #endif
            }
            .onDisappear { transition?.cancel(); camera.onCapture = nil; camera.stop(); UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of:scenePhase) { _,phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active
                if phase == .active && !review { startCamera() } else { camera.suspend() }
            }
            .onChange(of:backPressure) { _,blocked in
                if stage == .front { if blocked { camera.pauseCapture() } else { camera.armNextFront() } }
            }
            .sheet(isPresented:$review) { BatchReviewView(coordinator:coordinator).environmentObject(store) }
            .onChange(of:review) { _,open in if open { camera.suspend() } else if scenePhase == .active { startCamera() } }
            .onChange(of:finishPartial) { _,open in if open { camera.suspend() } else if scenePhase == .active { startCamera() } }
            .confirmationDialog(stage == .failed ? "Unsaved photos will be discarded." : "Discard the unfinished card? Saved pairs will keep processing.",isPresented:$finishPartial,titleVisibility:.visible) {
                Button("Discard unfinished card and finish",role:.destructive) { dismiss() }
                Button("Keep scanning",role:.cancel) { }
            }
    }
    private var title: String {
        switch stage {
        case .front: return "Scan front of card"
        case .flip: return "Front captured!"
        case .back: return "Scan back of card"
        case .reveal: return "Ready for the next card"
        case .failed: return "Save needs attention"
        }
    }
    private var subtitle: String {
        switch stage {
        case .front: return "Place a card under the camera. Keep all four edges visible."
        case .flip, .back: return "Flip it over. The back captures automatically."
        case .reveal: return "Slide in the next card. Identification and pricing continue in the background."
        case .failed: return "Keep this screen open and retry to save both photos."
        }
    }
    private func startCamera() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_BATCH_FIXTURE"] == "1" { return }
        #endif
        camera.start()
        if stage == .front && backPressure { camera.pauseCapture() }
    }
    private func receive(_ face: CapturedFace) {
        guard scenePhase == .active, !review else { return }
        if stage == .front {
            guard !backPressure else { return }
            pair = Card(); pair.front = face.original; pair.frontCrop = face.crop; pair.thumbnail = face.preview
            stage = .flip; camera.prepareBack()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification:.announcement,argument:"Front captured. Flip your card.")
            transition = Task {
                do { try await Task.sleep(for:.seconds(0.9)); try Task.checkCancellation(); stage = .back; camera.armBack() } catch { }
            }
        } else if stage == .back {
            pair.back = face.original; pair.backCrop = face.crop; pair.backCorrected = face.preview
            savePair()
        }
    }
    private func savePair() {
        do {
            try coordinator.enqueue(pair,store:store)
            saveError = nil; captured += 1; stage = .reveal
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification:.announcement,argument:"Both sides saved. Next card.")
            transition = Task {
                do {
                    try await Task.sleep(for:.seconds(1.8)); try Task.checkCancellation()
                    pair = Card(); stage = .front
                    if !backPressure { camera.armNextFront() }
                } catch { }
            }
        } catch { stage = .failed; saveError = error.localizedDescription }
    }
}

struct BatchReviewView: View {
    @EnvironmentObject private var store: CollectionStore
    @ObservedObject var coordinator: BatchScanCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Card?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(coordinator.pendingCount(store)) cards waiting for identification and pricing.")
                    Text("You can keep scanning or return to the collection. Saved pairs resume processing when the app is open.").font(.caption).foregroundStyle(.secondary)
                    if let message = coordinator.error { Text(message); Button("Retry processing") { coordinator.retry(store:store) } }
                }
                Section("Duplicates need your choice") {
                    let duplicates = store.cards.filter { $0.batchState == "duplicate" }
                    if duplicates.isEmpty { Text("No duplicates awaiting review.") }
                    ForEach(duplicates) { card in
                        Button { selected = card } label: { CardCollectionRow(card:card) }.accessibilityIdentifier("batch.duplicate."+card.id.uuidString)
                    }
                }
            }.navigationTitle("Batch scans")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item:$selected) { card in
                    DuplicateScanReview(matches:CardDuplicates.matches(for:card,in:store.cards),addDuplicate:{ resolve(card) },overwrite:{ resolve(card,replacing:$0) },discard:{
                        do { try store.delete(card.id); selected = nil } catch { self.error = error.localizedDescription }
                    })
                    .alert("Could not save choice",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                }
        }.tint(.indigo)
    }
    private func resolve(_ card: Card,replacing id: UUID? = nil) {
        do { try store.resolveBatch(card,replacing:id); selected = nil }
        catch { self.error = error.localizedDescription }
    }
}
