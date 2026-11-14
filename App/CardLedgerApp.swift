import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@main struct CardLedgerApp: App {
    @StateObject var store: CollectionStore
    init() {
        #if DEBUG
        if let testStore = ProcessInfo.processInfo.environment["CARD_LEDGER_UI_TEST_STORE"], UUID(uuidString: testStore) != nil {
            _store = StateObject(wrappedValue: CollectionStore(file: URL.applicationSupportDirectory.appending(path: "CardLedgerUITests/" + testStore + "/collection.json")))
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
    @State private var sport = "All sports"
    @State private var sort = "Newest"
    @State private var year = "All years"
    @State private var grading = "All grades"
    @State private var tag = ""
    @State private var availability = "All values"
    @State private var editing: Card?
    @State private var settings = false
    @State private var scan: ScanFlowModel?
    @Namespace private var scanFlight
    @State private var inserted: UUID?
    @State private var filtersExpanded = false
    var visible: [Card] {
        store.cards.filter { card in
            (status == "All" || card.status == status) && (sport == "All sports" || card.identity.sport == sport) &&
            (year == "All years" || card.identity.year == year) &&
            (grading == "All grades" || (grading == "Raw" ? card.identity.grade.lowercased() == "raw" : card.identity.grade.lowercased() != "raw" && !card.identity.grade.isEmpty)) &&
            (tag.isEmpty || card.tags.localizedCaseInsensitiveContains(tag)) &&
            (availability == "All values" || (availability == "Valued" ? card.collectionValue != nil : card.collectionValue == nil)) &&
            (query.isEmpty || [card.identity.title, card.identity.team, card.identity.sport, card.tags, card.location].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }.sorted {
            switch sort {
            case "Name": return $0.identity.player.localizedStandardCompare($1.identity.player) == .orderedAscending
            case "Value": return ($0.collectionValue ?? -1) > ($1.collectionValue ?? -1)
            case "Year": return $0.identity.year.localizedStandardCompare($1.identity.year) == .orderedDescending
            default: return $0.added > $1.added
            }
        }
    }
    var body: some View {
        ZStack {
            collectionContent.allowsHitTesting(scan == nil).accessibilityHidden(scan != nil)
            if let scan {
                ScanFlowView(model:scan,namespace:scanFlight,onCancel:{ withAnimation { self.scan = nil } },onCommit:finishScan)
                    .transition(.opacity).zIndex(2)
            }
        }
    }
    private var collectionContent: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    let owned = store.cards.filter { $0.status == "Owned" }
                    let values = owned.compactMap { $0.collectionValue }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(values.reduce(0, +), format: .currency(code: "USD")).font(.largeTitle.bold())
                        Text("\(values.count) of \(owned.count) owned cards valued · saved estimates").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    Picker("Status", selection: $status) { ForEach(["Owned", "Sold", "Gifted", "All"], id: \.self) { Text($0) } }
                    Picker("Sport", selection: $sport) { ForEach(["All sports"] + Array(Set(store.cards.map { $0.identity.sport })).sorted(), id: \.self) { Text($0) } }
                    Picker("Sort", selection: $sort) { ForEach(["Newest", "Name", "Year", "Value"], id: \.self) { Text($0) } }
                    DisclosureGroup("More filters",isExpanded:$filtersExpanded) {
                        Picker("Year", selection: $year) { ForEach(["All years"] + Array(Set(store.cards.map { $0.identity.year }.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0) } }
                        Picker("Grade", selection: $grading) { ForEach(["All grades", "Raw", "Graded"], id: \.self) { Text($0) } }
                        Picker("Value", selection: $availability) { ForEach(["All values", "Valued", "Not valued"], id: \.self) { Text($0) } }
                        TextField("Owner or tag", text: $tag)
                        Button("Reset filters") { status = "Owned"; sport = "All sports"; year = "All years"; grading = "All grades"; availability = "All values"; tag = ""; query = "" }
                    }
                }
                if visible.isEmpty { ContentUnavailableView("Your collection starts here", systemImage: "rectangle.stack", description: Text("Tap + to photograph or add a card.")) }
                ForEach(visible) { card in
                    Button { editing = card } label: {
                        CardCollectionRow(card:card,namespace:scanFlight)
                    }.foregroundStyle(.primary).id(card.id).accessibilityIdentifier("card.row." + card.id.uuidString)
                }
            }.navigationTitle("Card Ledger").searchable(text: $query, prompt: "Player, team, set, tag or location")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Add card", systemImage: "plus", action:startScan).accessibilityIdentifier("collection.add") }
                }
                .onChange(of: inserted) { _,id in if let id { withAnimation(.spring(response:0.65,dampingFraction:0.88)) { proxy.scrollTo(id,anchor:.center) } } }
                .sheet(item: $editing) { card in CardEditor(card: card) }
                .sheet(isPresented: $settings) { SettingsView() }
                .alert("Collection error", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
            }
        }
    }
    private func startScan() {
        filtersExpanded = false
        query = ""; status = "Owned"; sport = "All sports"; year = "All years"; grading = "All grades"; tag = ""; availability = "All values"; sort = "Newest"
        var services = ScanServices.live(workerURL:UserDefaults.standard.string(forKey:"workerURL") ?? "")
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_SCAN_FIXTURE"] == "1" {
            services.identify = { _ in Identity(player:"UI Rookie",team:"Brooklyn",year:"2026",manufacturer:"Test Brand",set:"Test Set",number:"1",variant:"Base",grade:"Raw") }
            services.canLookup = false
        }
        #endif
        withAnimation(.easeInOut(duration:0.25)) { scan = ScanFlowModel(services:services) }
    }
    private func finishScan(_ card: Card) {
        do {
            try withAnimation(.spring(response:0.7,dampingFraction:0.88)) {
                try store.save(card); scan = nil; inserted = card.id
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
    @AppStorage("workerURL") private var workerURL = ""
    @State var card: Card
    @State private var photo: PhotosPickerItem?
    @State private var side = "Front"
    @State private var camera = false
    @State private var busy = false
    @State private var message: String?
    @State private var deleting = false
    @State private var work: Task<Void, Never>?
    @State private var cropping = false
    var body: some View { NavigationStack { feedbackContent } }
    private var editorForm: some View {
        Form {
            photosSection
            identitySection
            collectionSection
            manualValueSection
            researchSection
            deleteSection
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
                card.research = nil
            }
            .sheet(isPresented: $camera) { Camera(onPhoto: capturedPhoto) }
            .sheet(isPresented: $cropping) { cropEditor }
            .onDisappear { work?.cancel() }
    }
    private var feedbackContent: some View {
        mediaContent
            .alert("Card Ledger", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .confirmationDialog("Permanently delete this card and its photos?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteCard)
            }
    }
    private func saveCard() {
        do { try store.save(card); dismiss() } catch { message = error.localizedDescription }
    }
    private func deleteCard() {
        do { try store.delete(card.id); dismiss() } catch { message = error.localizedDescription }
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
                    Button("Adjust corners and rotation") { cropping = true }.disabled((side == "Front" ? card.front : card.back) == nil)
                    if let original = card.back { DisclosureGroup("Original back · condition photo") { PhotoView(data: original).frame(height: 350) } }
                    if let original = card.front { DisclosureGroup("Original front · condition photo") { PhotoView(data: original).frame(height: 350) } }
                    Button("Read card details with Apple Intelligence") { run { let result = try await Recognizer.identify(text: card.ocr); try Task.checkCancellation(); card.identity = result } }.disabled(card.ocr.isEmpty)
                    if !card.ocr.isEmpty { DisclosureGroup("Extracted text") { Text(card.ocr).textSelection(.enabled) } }
                }
    }
    private var identitySection: some View {
                Section("Confirm identity") {
                    TextField("Player / card name", text: $card.identity.player).accessibilityIdentifier("card.player")
                    TextField("Team printed on card", text: $card.identity.team)
                    TextField("Sport", text: $card.identity.sport)
                    TextField("Year / season", text: $card.identity.year)
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
            Text("Your value takes precedence in collection totals. Clear it to use the saved sold-comps estimate.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var cropEditor: some View {
        if let original = side == "Front" ? card.front : card.back {
            CropEditor(data: original, initial: side == "Front" ? card.frontCrop : card.backCrop) { selection in
                let selectedSide = side
                run {
                    let result = try await Imaging.process(original, crop: selection)
                    try Task.checkCancellation()
                    if selectedSide == "Front" { card.thumbnail = result.corrected; card.frontCrop = selection }
                    else { card.backCorrected = result.corrected; card.backCrop = selection }
                    card.replaceOCR(result.text, front: selectedSide == "Front")
                }
            }
        }
    }
    private var researchSection: some View {
                Section("Market research") {
                    Text("Research sends the confirmed card details to your private worker. Photos stay on this device.").font(.caption)
                    Button("Look up current value", systemImage: "magnifyingglass") { run {
                        let result = try await ResearchClient.lookup(card.identity, base: workerURL)
                        try Task.checkCancellation()
                        card.research = result
                        try store.save(card)
                    } }.disabled(!card.identity.confirmed)
                    if let r = card.research {
                        Text(r.valuation_basis.replacingOccurrences(of: "_", with: " ")).font(.headline)
                        if let value = r.estimate { Text(value, format: .currency(code: "USD")).font(.title.bold()) }
                        Text("\(r.sample_count) qualifying sales · \(r.searched_at)").font(.caption)
                        ForEach(r.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        ForEach(r.observations) { o in
                            if let url = URL(string: o.source_url), ["https", "http"].contains(url.scheme ?? "") {
                                Link(destination: url) {
                                    VStack(alignment: .leading) {
                                        Text(o.source_name + " · " + o.evidence_type.replacingOccurrences(of: "_", with: " "))
                                        Text(o.observed_card_description).font(.caption)
                                        if let amount = o.amount { Text(amount, format: .currency(code: o.currency ?? "USD")) }
                                        if let reason = o.exclusion_reason { Text(reason).font(.caption) }
                                    }
                                }
                            }
                        }
                    }
                }
    }
    private var deleteSection: some View {
                Section { Button("Delete card permanently", role: .destructive) { deleting = true } }
    }
    func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        work = Task { defer { busy = false; work = nil }; do { try await action() } catch { if !Task.isCancelled { message = error.localizedDescription } } }
    }
    func ingest(_ data: Data, side: String) async throws {
        let result = try await Imaging.process(data)
        try Task.checkCancellation()
        if side == "Front" { card.front = result.original; card.thumbnail = result.corrected; card.frontCrop = nil }
        else { card.back = result.original; card.backCorrected = result.corrected; card.backCrop = nil }
        card.replaceOCR(result.text, front: side == "Front")
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workerURL") private var workerURL = ""
    @State private var token = Credentials.read()
    @State private var share: URL?
    @State private var importing = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Private pricing worker") {
                    TextField("https://your-worker.example", text: $workerURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Device access token", text: $token)
                    Button("Save connection") { perform { try Credentials.save(token); message = "Connection settings saved." } }
                    Text("Use your private Codex worker. Your Codex credentials are never stored in the app.").font(.caption)
                }
                Section("Your data") {
                    Text("Photos: " + ByteCountFormatter.string(fromByteCount: Int64(store.storageBytes), countStyle: .file))
                    Text("Build " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")").font(.caption)
                    Button("Export backup with photos") { perform { share = try store.export() } }
                    Button("Export CSV") { perform { share = try store.csv() } }
                    Button("Import backup") { importing = true }
                    Text("Import adds missing cards without overwriting existing copies. Backups contain your photos and cached research; keep them private.").font(.caption)
                    if let share { ShareLink("Share exported file", item: share) }
                }
            }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
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
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimum = 0; formatter.maximumFractionDigits = 2; formatter.generatesDecimalNumbers = true
        return formatter
    }()
    var body: some View { TextField(title, value: $value, formatter: Self.formatter).keyboardType(.decimalPad) }
}
