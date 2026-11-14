import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@main struct CardLedgerApp: App {
    @StateObject var store = CollectionStore()
    var body: some Scene { WindowGroup { CollectionView().environmentObject(store).tint(.indigo) } }
}
struct CollectionView: View {
    @EnvironmentObject var store: CollectionStore
    @State private var query = ""
    @State private var status = "Owned"
    @State private var sport = "All sports"
    @State private var sort = "Newest"
    @State private var editing: Card?
    @State private var settings = false
    var visible: [Card] {
        store.cards.filter { card in
            (status == "All" || card.status == status) && (sport == "All sports" || card.identity.sport == sport) &&
            (query.isEmpty || [card.identity.title, card.identity.team, card.identity.sport, card.tags, card.location].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }.sorted {
            switch sort {
            case "Name": return $0.identity.player.localizedStandardCompare($1.identity.player) == .orderedAscending
            case "Value": return ($0.research?.estimate ?? -1) > ($1.research?.estimate ?? -1)
            default: return $0.added > $1.added
            }
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    let owned = store.cards.filter { $0.status == "Owned" }
                    let values = owned.compactMap { $0.research?.estimate }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(values.reduce(0, +), format: .currency(code: "USD")).font(.largeTitle.bold())
                        Text("\(values.count) of \(owned.count) owned cards valued · saved estimates").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    Picker("Status", selection: $status) { ForEach(["Owned", "Sold", "Gifted", "All"], id: \.self) { Text($0) } }
                    Picker("Sport", selection: $sport) { ForEach(["All sports"] + Array(Set(store.cards.map { $0.identity.sport })).sorted(), id: \.self) { Text($0) } }
                    Picker("Sort", selection: $sort) { ForEach(["Newest", "Name", "Value"], id: \.self) { Text($0) } }
                }
                if visible.isEmpty { ContentUnavailableView("Your collection starts here", systemImage: "rectangle.stack", description: Text("Tap + to photograph or add a card.")) }
                ForEach(visible) { card in
                    Button { editing = card } label: {
                        HStack(spacing: 12) {
                            PhotoView(data: card.thumbnail ?? card.front).frame(width: 58, height: 80).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.identity.title.isEmpty ? "Unidentified card" : card.identity.title).font(.headline)
                                Text("\(card.identity.grade) · \(card.identity.variant)").font(.caption).foregroundStyle(.secondary)
                                if let value = card.research?.estimate { Text(value, format: .currency(code: "USD")) }
                                else { Text("Not valued").foregroundStyle(.secondary) }
                            }
                        }
                    }.foregroundStyle(.primary)
                }
            }.navigationTitle("Card Ledger").searchable(text: $query, prompt: "Player, team, set, tag or location")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Add card", systemImage: "plus") { editing = Card() } }
                }
                .sheet(item: $editing) { card in CardEditor(card: card) }
                .sheet(isPresented: $settings) { SettingsView() }
                .alert("Collection error", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        }
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
    var body: some View {
        NavigationStack {
            Form {
                Section("Photographs") {
                    HStack { PhotoView(data: card.thumbnail ?? card.front); PhotoView(data: card.back) }.frame(height: 220)
                    Picker("Side", selection: $side) { Text("Front").tag("Front"); Text("Back").tag("Back") }.pickerStyle(.segmented)
                    PhotosPicker("Import photo", selection: $photo, matching: .images)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take photo", systemImage: "camera") { camera = true } }
                    if let original = card.front { DisclosureGroup("Original front · condition photo") { PhotoView(data: original).frame(height: 350) } }
                    Button("Read card details with Apple Intelligence") { run { card.identity = try await Recognizer.identify(text: card.ocr) } }.disabled(card.ocr.isEmpty)
                    if !card.ocr.isEmpty { DisclosureGroup("Extracted text") { Text(card.ocr).textSelection(.enabled) } }
                }
                Section("Confirm identity") {
                    TextField("Player / card name", text: $card.identity.player)
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
                Section("Collection") {
                    TextField("Tags / owner", text: $card.tags)
                    TextField("Binder / box location", text: $card.location)
                    TextField("Condition and notes", text: $card.notes, axis: .vertical)
                    Picker("Status", selection: $card.status) { ForEach(["Owned", "Sold", "Gifted"], id: \.self) { Text($0) } }
                }
                Section("Market research") {
                    Text("Research sends the confirmed card details to your private worker. Photos stay on this device.").font(.caption)
                    Button("Look up current value", systemImage: "magnifyingglass") { run {
                        let result = try await ResearchClient.lookup(card.identity, base: workerURL)
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
                Section { Button("Delete card permanently", role: .destructive) { deleting = true } }
            }.disabled(busy).overlay { if busy { ProgressView("Working…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
                .navigationTitle("Card details").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try store.save(card); dismiss() } catch { message = error.localizedDescription } }.disabled(busy) }
                }
                .onChange(of: photo) { _, value in
                    let selectedSide = side
                    run { if let data = try await value?.loadTransferable(type: Data.self) { try await ingest(data, side: selectedSide) } }
                }
                .onChange(of: card.status) { _, value in card.dispositionDate = value == "Owned" ? nil : Date() }
                .onChange(of: card.identity.details) { _, _ in
                    card.identity.confirmed = false
                    card.research = nil
                }
                .sheet(isPresented: $camera) { Camera { data in let selectedSide = side; run { try await ingest(data, side: selectedSide) } } }
                .alert("Card Ledger", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
                .confirmationDialog("Permanently delete this card and its photos?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { do { try store.delete(card.id); dismiss() } catch { message = error.localizedDescription } } }
        }
    }
    func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { try await action() } catch { message = error.localizedDescription } }
    }
    func ingest(_ data: Data, side: String) async throws {
        let result = try await Imaging.process(data)
        if side == "Front" { card.front = result.original; card.thumbnail = result.corrected } else { card.back = result.original }
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
