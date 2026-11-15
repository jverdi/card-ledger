import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Security

@main struct CardLedgerApp: App {
    @StateObject var store: CollectionStore
    init() {
        // Retire credentials from the former private-worker connection.
        UserDefaults.standard.removeObject(forKey:"workerURL")
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"CardLedger.worker"] as CFDictionary)
        #if DEBUG
        if let testStore = ProcessInfo.processInfo.environment["CARD_LEDGER_UI_TEST_STORE"], UUID(uuidString: testStore) != nil {
            let file = URL.applicationSupportDirectory.appending(path:"CardLedgerUITests/"+testStore+"/collection.json")
            let fresh = !FileManager.default.fileExists(atPath:file.path)
            let store = CollectionStore(file:file)
            if fresh && (ProcessInfo.processInfo.environment["CARD_LEDGER_DUPLICATE_FIXTURE"] == "1" || ProcessInfo.processInfo.environment["CARD_LEDGER_PRICING_FIXTURE"] == "1") {
                var card = Card(); card.identity = ScanFixture.identity
                card.front = ScanFixture.image(label:"EXISTING FRONT"); card.back = ScanFixture.image(label:"EXISTING BACK")
                card.notes = "Keep these notes"; card.location = "Binder A"
                if ProcessInfo.processInfo.environment["CARD_LEDGER_DUPLICATE_FIXTURE"] == "1" { card.manualValue = 12.34 }
                try? store.save(card)
            }
            if fresh && ProcessInfo.processInfo.environment["CARD_LEDGER_COLLECTION_FIXTURE"] == "1" {
                var baseball = Card(); baseball.identity = Identity(player:"ANTHONY VOLPE",sport:"baseball",year:"2023",manufacturer:"Topps",set:"Inception")
                var pokemon = Card(); pokemon.identity = Identity(player:"PIKACHU",sport:"POKÉMON",year:"2024/25",manufacturer:"Pokémon",set:"Scarlet & Violet"); pokemon.status = "Sold"
                try? store.save(baseball); try? store.save(pokemon)
            }
            _store = StateObject(wrappedValue:store)
            return
        }
        #endif
        _store = StateObject(wrappedValue: CollectionStore())
    }
    var body: some Scene { WindowGroup { CollectionView().environmentObject(store).tint(.indigo) } }
}
struct CollectionView: View {
    @EnvironmentObject var store: CollectionStore
    @State private var query = ""
    @State private var status = "Owned"
    @State private var sport = "All card types"
    @State private var sort: CollectionSort = .added
    @State private var ascending = false
    @State private var year = "All years"
    @State private var grading = "All grades"
    @State private var tag = ""
    @State private var availability = "All values"
    @State private var viewing: Card?
    @State private var settings = false
    @State private var scan: ScanFlowModel?
    @StateObject private var batch = BatchScanCoordinator()
    @State private var batchScanning = false
    @State private var batchReview = false
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var scanFlight
    @State private var inserted: UUID?
    @State private var filtersExpanded = false
    var visible: [Card] {
        sort.sorted(store.cards.filter { card in
            card.batchState == nil && (status == "All" || card.status == status) && (sport == "All card types" || card.identity.sport == sport) &&
            (year == "All years" || card.identity.year == year) &&
            (grading == "All grades" || (grading == "Raw" ? card.identity.grade.lowercased() == "raw" : card.identity.grade.lowercased() != "raw" && !card.identity.grade.isEmpty)) &&
            (tag.isEmpty || card.tags.localizedCaseInsensitiveContains(tag)) &&
            (availability == "All values" || (availability == "Valued" ? card.collectionValue != nil : card.collectionValue == nil)) &&
            (query.isEmpty || [card.identity.title, card.identity.team, card.identity.sport, card.tags, card.location].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }, ascending:ascending)
    }
    private var hasFilters: Bool {
        (status != "All" && status != "Owned") || sport != "All card types" || year != "All years" || grading != "All grades" || availability != "All values" || !tag.isEmpty || !query.isEmpty
    }
    private var collectionIsEmpty: Bool { !store.cards.contains { $0.batchState == nil } }
    private func clearFilters() {
        status = "All"; sport = "All card types"; year = "All years"; grading = "All grades"
        availability = "All values"; tag = ""; query = ""
    }

    var body: some View {
        ZStack {
            collectionContent.allowsHitTesting(scan == nil).accessibilityHidden(scan != nil)
            if let scan {
                ScanFlowView(model:scan,namespace:scanFlight,onCancel:{ withAnimation { self.scan = nil } },onCommit:finishScan)
                    .transition(.opacity).zIndex(2)
            }
        }
        .onAppear { batch.resume(store:store) }
        .onChange(of:scenePhase) { _,phase in if phase == .active { batch.resume(store:store) } }
        .fullScreenCover(isPresented:$batchScanning) { BatchScanView(coordinator:batch).environmentObject(store) }
        .sheet(isPresented:$batchReview) { BatchReviewView(coordinator:batch).environmentObject(store) }
        .fullScreenCover(item:$viewing) { card in CardDetailView(cardID:card.id).environmentObject(store) }
    }
    private var collectionContent: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    let owned = store.cards.filter { $0.batchState == nil && $0.status == "Owned" }
                    let values = owned.compactMap { $0.collectionValue }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(values.reduce(0, +), format: .currency(code: "USD")).font(.largeTitle.bold())
                        Text("\(values.count) of \(owned.count) owned cards valued · saved estimates").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if store.cards.contains(where: { $0.batchState != nil }) || batch.error != nil {
                    Button { batchReview = true } label: {
                        Label("Batch scans · \(batch.pendingCount(store)) processing · \(batch.duplicateCount(store)) to review",systemImage:"tray.full")
                    }.accessibilityIdentifier("batch.inbox")
                }
                Section {
                    Picker("Status", selection: $status) { ForEach(["Owned", "Sold", "Gifted", "All"], id: \.self) { Text($0) } }
                    Picker("Card type", selection: $sport) { ForEach(["All card types"] + Array(Set(store.cards.filter { $0.batchState == nil }.map { $0.identity.normalized.sport }.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0) } }
                    Picker("Sort", selection: $sort) { ForEach(CollectionSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .onChange(of:sort) { _,value in ascending = value == .name }
                    Picker("Order", selection:$ascending) {
                        Text(sort.directionLabel(ascending:true)).tag(true)
                        Text(sort.directionLabel(ascending:false)).tag(false)
                    }.pickerStyle(.segmented).accessibilityIdentifier("collection.sortDirection")
                    DisclosureGroup("More filters",isExpanded:$filtersExpanded) {
                        Picker("Year", selection: $year) { ForEach(["All years"] + Array(Set(store.cards.filter { $0.batchState == nil }.map { $0.identity.normalized.year }.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0) } }
                        Picker("Grade", selection: $grading) { ForEach(["All grades", "Raw", "Graded"], id: \.self) { Text($0) } }
                        Picker("Value", selection: $availability) { ForEach(["All values", "Valued", "Not valued"], id: \.self) { Text($0) } }
                        TextField("Owner or tag", text: $tag)
                        Button("Clear filters",action:clearFilters)
                    }
                }
                if visible.isEmpty {
                    if !collectionIsEmpty || hasFilters {
                        ContentUnavailableView {
                            Label("No matching cards found",systemImage:"line.3.horizontal.decrease.circle")
                        } description: {
                            Text("Try another search or clear your filters to see all cards.")
                        } actions: {
                            Button("Clear filters",action:clearFilters).accessibilityIdentifier("collection.clearFilters")
                        }.accessibilityIdentifier("collection.noMatches")
                    } else {
                        ContentUnavailableView("Your collection starts here",systemImage:"rectangle.stack",description:Text("Tap + to scan your first card."))
                    }
                }
                ForEach(visible) { card in
                    Button { viewing = card } label: {
                        CardCollectionRow(card:card,namespace:scanFlight).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.primary).id(card.id).accessibilityIdentifier("card.row." + card.id.uuidString).accessibilityHint("Opens card details")
                }
            }.navigationTitle("Card Ledger").searchable(text: $query, prompt: "Player, team, set, tag or location")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Batch scan",systemImage:"rectangle.stack.badge.plus") { batchScanning = true }.accessibilityIdentifier("collection.batch") }
                    ToolbarItem(placement: .topBarTrailing) { Button("Add card", systemImage: "plus", action:startScan).accessibilityIdentifier("collection.add") }
                }
                .onChange(of: inserted) { _,id in if let id { withAnimation(.spring(response:0.65,dampingFraction:0.88)) { proxy.scrollTo(id,anchor:.center) } } }
                .sheet(isPresented: $settings) { SettingsView() }
                .alert("Collection error", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
            }
        }
    }
    private func startScan() {
        filtersExpanded = false; inserted = nil
        query = ""; status = "Owned"; sport = "All card types"; year = "All years"; grading = "All grades"; tag = ""; availability = "All values"; sort = .added; ascending = false
        var services = ScanServices.live()
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_SCAN_FIXTURE"] == "1" {
            services.identify = { _ in ScanFixture.identity }
            services.canLookup = false
            services.minimumReveal = 6 // Give UI automation time to inspect the animated reveal.
        }
        #endif
        withAnimation(.easeInOut(duration:0.25)) { scan = ScanFlowModel(services:services) }
    }
    private func finishScan(_ card: Card) {
        do {
            try withAnimation(.spring(response:0.7,dampingFraction:0.88)) {
                let saved = try store.saveScan(card,replacing:scan?.replacingCardID)
                scan = nil; status = saved.status; inserted = saved.id
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { scan?.saveError = "Your scan is ready, but could not be saved. " + error.localizedDescription }
    }
}
struct PhotoView: View {
    let data: Data?
    var body: some View {
        if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
        else { RoundedRectangle(cornerRadius: 8).fill(.quaternary).overlay(Image(systemName: "photo").foregroundStyle(.secondary)) }
    }
}
struct CardEditor: View {
    @EnvironmentObject var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State var card: Card
    @State private var photo: PhotosPickerItem?
    @State private var side = "Front"
    @State private var camera = false
    @State private var busy = false
    @State private var message: String?
    @State private var work: Task<Void, Never>?
    @State private var cropping = false
    @State private var reviewingPrice = false
    var body: some View { NavigationStack { feedbackContent } }
    private var editorForm: some View {
        Form {
            photosSection
            identitySection
            collectionSection
            manualValueSection
            pricingSection
        }
        .disabled(busy)
        .overlay { if busy { VStack(spacing: 12) { ProgressView("Working…"); Button("Cancel operation") { work?.cancel() } }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
    }
    private var navigationContent: some View {
        editorForm
            .navigationTitle("Card details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: saveCard).disabled(busy).accessibilityIdentifier("card.save") }
            }
    }
    private var mediaContent: some View {
        navigationContent
            .onChange(of: photo) { _, value in importPhoto(value) }
            .onChange(of: card.status) { _, value in card.dispositionDate = value == "Owned" ? nil : Date() }
            .onChange(of: card.identity.details) { _, _ in
                card.identity.confirmed = false
                card.research = nil; card.pricing = nil; card.priceCrossCheck = nil
            }
            .sheet(isPresented: $camera) { Camera(onPhoto: capturedPhoto) }
            .sheet(isPresented: $cropping) { cropEditor }
            .sheet(isPresented:$reviewingPrice) {
                if let pricing = card.pricing { CardPricingReview(identity:card.identity,initial:pricing) { result in card.pricing = result; card.scanNote = result.usableValue == nil ? result.summary:nil } }
            }
            .onDisappear { work?.cancel() }
    }
    private var feedbackContent: some View {
        mediaContent
            .alert("Card Ledger", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
    private func saveCard() {
        do { try store.save(card); dismiss() } catch { message = error.localizedDescription }
    }
    private func capturedPhoto(_ data: Data) {
        let selectedSide = side
        run { try await ingest(data, side: selectedSide) }
    }
    private func importPhoto(_ item: PhotosPickerItem?) {
        let selectedSide = side
        run {
            guard let item, let data = try await item.loadTransferable(type: Data.self) else { return }
            try await ingest(data, side: selectedSide)
        }
    }
    private var photosSection: some View {
                Section("Photographs") {
                    HStack { PhotoView(data: card.thumbnail ?? card.front); PhotoView(data: card.backCorrected ?? card.back) }.frame(height: 220)
                    Picker("Side", selection: $side) { Text("Front").tag("Front"); Text("Back").tag("Back") }.pickerStyle(.segmented)
                    PhotosPicker("Import photo", selection: $photo, matching: .images)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take photo", systemImage: "camera") { camera = true } }
                    if (side == "Front" ? card.frontOrientationUncertain : card.backOrientationUncertain) == true {
                        Text("Orientation uncertain. Rotate this side if needed.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Rotate 90°",systemImage:"rotate.right",action:rotateSelectedSide)
                        .disabled((side == "Front" ? card.front : card.back) == nil).accessibilityIdentifier("card.rotate")
                    Button("Adjust corners and rotation") { cropping = true }.disabled((side == "Front" ? card.front : card.back) == nil)
                    if let original = card.back { DisclosureGroup("Original back · condition photo") { PhotoView(data: original).frame(height: 350) } }
                    if let original = card.front { DisclosureGroup("Original front · condition photo") { PhotoView(data: original).frame(height: 350) } }
                    Button("Read card details with Apple Intelligence") { run { let result = try await Recognizer.identify(text: card.ocr); try Task.checkCancellation(); card.identity = result } }.disabled(card.ocr.isEmpty)
                    if !card.ocr.isEmpty { DisclosureGroup("Extracted text") { Text(card.ocr).textSelection(.enabled) } }
                }
    }
    private func rotateSelectedSide() {
        let selectedSide = side
        guard let original = selectedSide == "Front" ? card.front : card.back else { return }
        let savedCrop = selectedSide == "Front" ? card.frontCrop : card.backCrop
        run {
            let selection: CropSelection
            if let savedCrop { selection = savedCrop }
            else { selection = try await Imaging.process(original).crop ?? CropSelection() }
            let rotated = selection.rotatedClockwise(1)
            let result = try await Imaging.process(original,crop:rotated)
            try Task.checkCancellation()
            if selectedSide == "Front" { card.thumbnail = result.corrected; card.frontCrop = rotated; card.frontOrientationUncertain = false }
            else { card.backCorrected = result.corrected; card.backCrop = rotated; card.backOrientationUncertain = false }
            card.replaceOCR(result.text,front:selectedSide == "Front")
        }
    }
    private var identitySection: some View {
                Section("Confirm identity") {
                    TextField("Player / card name", text: $card.identity.player).accessibilityIdentifier("card.player")
                    TextField("Team printed on card", text: $card.identity.team)
                    TextField("Card type", text: $card.identity.sport)
                    TextField("Year (season start)", text: $card.identity.year).keyboardType(.numbersAndPunctuation)
                    Text("Use the starting year: 2024/25 is saved as 2024.").font(.caption).foregroundStyle(.secondary)
                    if let source = card.identity.sourceYear, source != card.identity.year {
                        Text("Original year / season: " + source).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Manufacturer", text: $card.identity.manufacturer)
                    TextField("Set", text: $card.identity.set)
                    TextField("Card number", text: $card.identity.number)
                    TextField("Parallel / variation (enter Base if verified)", text: $card.identity.variant)
                    TextField("Grade (Raw or e.g. PSA 9)", text: $card.identity.grade)
                    TextField("Certificate number", text: $card.identity.certificate)
                    Toggle("I have verified this exact card", isOn: $card.identity.confirmed)
                }
    }
    private var collectionSection: some View {
                Section("Collection") {
                    TextField("Tags / owner", text: $card.tags)
                    TextField("Binder / box location", text: $card.location)
                    TextField("Condition and notes", text: $card.notes, axis: .vertical)
                    Picker("Status", selection: $card.status) { ForEach(["Owned", "Sold", "Gifted"], id: \.self) { Text($0) } }
                    Toggle("Record purchase date", isOn: Binding(get: { card.acquisitionDate != nil }, set: { card.acquisitionDate = $0 ? Date() : nil }))
                    if card.acquisitionDate != nil { DatePicker("Acquired", selection: Binding(get: { card.acquisitionDate ?? Date() }, set: { card.acquisitionDate = $0 }), displayedComponents: .date) }
                    MoneyField(title: "Purchase cost (USD)", value: $card.acquisitionCost)
                    if card.status != "Owned" {
                        DatePicker("Disposition date", selection: Binding(get: { card.dispositionDate ?? Date() }, set: { card.dispositionDate = $0 }), displayedComponents: .date)
                        MoneyField(title: "Proceeds (USD)", value: $card.dispositionProceeds)
                    }
                }
    }
    private var manualValueSection: some View {
        Section("Your valuation") {
            MoneyField(title: "Your value (USD)", value: $card.manualValue)
                .onChange(of: card.manualValue) { _, value in card.manualValueDate = value == nil ? nil : Date() }
            TextField("Source or reason", text: Binding(get: { card.manualValueSource ?? "" }, set: { card.manualValueSource = $0 }))
            if let date = card.manualValueDate { Text("Updated " + date.formatted(date: .abbreviated, time: .omitted)).font(.caption) }
            Text("Your value takes precedence in collection totals. Clear it to use the saved CardPricer estimate.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var cropEditor: some View {
        if let original = side == "Front" ? card.front : card.back {
            CropEditor(data: original, initial: side == "Front" ? card.frontCrop : card.backCrop) { selection in
                let selectedSide = side
                run {
                    let result = try await Imaging.process(original, crop: selection)
                    try Task.checkCancellation()
                    if selectedSide == "Front" { card.thumbnail = result.corrected; card.frontCrop = selection; card.frontOrientationUncertain = false }
                    else { card.backCorrected = result.corrected; card.backCrop = selection; card.backOrientationUncertain = false }
                    card.replaceOCR(result.text, front: selectedSide == "Front")
                }
            }
        }
    }
    private var pricingSection: some View {
        Section("CardPricer pricing") {
            Text("Card details are sent to CardPricer’s free service. Photos stay on this device.").font(.caption)
            Button("Refresh CardPricer price",systemImage:"arrow.clockwise") { run {
                let result = try await PricingService.lookup(card.identity)
                try Task.checkCancellation()
                card.pricing = result; card.scanNote = result.usableValue == nil ? result.summary:nil
            } }.disabled(!CardPricerClient.complete(card.identity))
            if let price = card.pricing {
                if let value = price.usableValue { Text(value,format:.currency(code:"USD")).font(.title.bold()) }
                CardPricingSummary(pricing:price)
                if !price.candidates.isEmpty { Button("Review price match") { reviewingPrice = true } }
            }
        }
    }
    func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        work = Task { defer { busy = false; work = nil }; do { try await action() } catch { if !Task.isCancelled { message = error.localizedDescription } } }
    }
    func ingest(_ data: Data, side: String) async throws {
        let result = try await Imaging.process(data)
        try Task.checkCancellation()
        if side == "Front" { card.front = result.original; card.thumbnail = result.corrected; card.frontCrop = result.crop; card.frontOrientationUncertain = nil }
        else { card.back = result.original; card.backCorrected = result.corrected; card.backCrop = result.crop; card.backOrientationUncertain = nil }
        card.replaceOCR(result.text, front: side == "Front")
    }
}
struct SettingsView: View {
    @State private var checking = false
    @State private var checkTask: Task<Void,Never>?
    @EnvironmentObject var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var share: URL?
    @State private var importing = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Pricing") {
                    Text("CardPricer · Free access").accessibilityIdentifier("pricing.provider")
                    Text("Prices are looked up automatically after scanning. No account, access token or private server is required. Card details are sent to CardPricer; photos stay on this device.").font(.caption)
                    Link("About CardPricer",destination:CardPricerClient.website)
                    Button("Test connection") {
                        checking = true
                        checkTask = Task { @MainActor in
                            defer { checking = false }
                            do { try await CardPricerClient.shared.checkConnection(); try Task.checkCancellation(); message = "Connected to CardPricer’s free service. Individual card coverage varies." }
                            catch { if !Task.isCancelled { message = error.localizedDescription } }
                        }
                    }.disabled(checking)
                    if checking { ProgressView("Connecting…") }
                }
                Section("Your data") {
                    Text("Photos: " + ByteCountFormatter.string(fromByteCount: Int64(store.storageBytes), countStyle: .file))
                    Text("Build " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")").font(.caption)
                    Button("Export backup with photos") { perform { share = try store.export() } }
                    Button("Export CSV") { perform { share = try store.csv() } }
                    Button("Import backup") { importing = true }
                    Text("Import adds missing cards without overwriting existing copies. Backups contain your photos, saved prices and references; keep them private.").font(.caption)
                    if let share { ShareLink("Share exported file", item: share) }
                }
            }.onDisappear { checkTask?.cancel() }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in perform {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try store.restore(Data(contentsOf: url)); message = "Backup imported."
                } }
                .alert("Card Ledger", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
        }
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { message = error.localizedDescription } }
}

struct MoneyField: View {
    let title: String
    @Binding var value: Decimal?
    @State private var text = ""
    @FocusState private var focused: Bool
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimum = 0; formatter.maximumFractionDigits = 2; formatter.generatesDecimalNumbers = true
        return formatter
    }()
    private func syncText() {
        text = value.flatMap { Self.formatter.string(from:NSDecimalNumber(decimal:$0)) } ?? ""
    }
    var body: some View {
        TextField(title,text:Binding(get:{ text },set:{ input in
            text = input
            value = Self.formatter.number(from:input)?.decimalValue
        }))
        .keyboardType(.decimalPad).focused($focused)
        .onAppear { syncText() }
        .onChange(of:value) { _,_ in if !focused { syncText() } }
        .onChange(of:focused) { _,active in if !active { syncText() } }
        .toolbar {
            ToolbarItemGroup(placement:.keyboard) {
                if focused {
                    Spacer()
                    Button("Done") { focused = false }.accessibilityIdentifier("money.done")
                }
            }
        }
    }
}

