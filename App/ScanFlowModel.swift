import SwiftUI

enum ScanFailure: LocalizedError {
    case noRectangle, timeout
    var errorDescription: String? {
        switch self {
        case .noRectangle: return "No complete card found. Include all four edges with a little space around the card."
        case .timeout: return "This is taking too long. Your photos will be saved for review."
        }
    }
}
struct ScanServices {
    var process: (CapturedFace) async throws -> PhotoResult
    var identify: (String) async throws -> Identity
    var lookup: (Identity) async throws -> Research
    var canLookup: Bool
    var revealDuration: Double = 1.1
    var spinnerDelay: Double = 3
    var minimumReveal: Double = 2
    var collapseDuration: Double = 0.65
    static func live(workerURL: String) -> Self {
        Self(process: { try await Imaging.process($0.original, crop: $0.crop) },
             identify: { try await Recognizer.identify(text: $0) },
             lookup: { try await ResearchClient.lookup($0, base: workerURL) },
             canLookup: ResearchClient.configured(base: workerURL))
    }
}

@MainActor final class ScanFlowModel: ObservableObject, Identifiable {
    enum Stage: Equatable { case front, back, identifying, revealing, compact, ready }
    let id: UUID
    @Published private(set) var card: Card
    @Published private(set) var stage: Stage = .front
    @Published private(set) var showPriceSpinner = false
    @Published private(set) var pricePending = false
    @Published var captureError: String?
    @Published var saveError: String?
    @Published private(set) var importing = false
    private var cancelled = false
    private var front: CapturedFace?
    private var back: CapturedFace?
    private var task: Task<Void, Never>?
    private var spinner: Task<Void, Never>?
    let services: ScanServices
    var scanning: Bool { stage == .front || stage == .back }
    var player: String { card.identity.player.isEmpty ? "Card captured" : card.identity.player }
    var team: String { card.identity.team.isEmpty ? "Ready for your collection" : card.identity.team }

    init(services: ScanServices) { let card = Card(); self.card = card; id = card.id; self.services = services }
    func receive(_ face: CapturedFace) {
        guard !cancelled, scanning, face.crop.valid else { return }
        captureError = nil
        if stage == .front {
            front = face; card.front = face.original; card.frontCrop = face.crop; card.thumbnail = face.preview
            withAnimation(.easeInOut(duration: 0.3)) { stage = .back }
        } else {
            back = face; card.back = face.original; card.backCrop = face.crop; card.backCorrected = face.preview
            stage = .identifying
            task = Task { await analyze() }
        }
    }
    func importPhoto(_ data: Data) {
        guard !cancelled, scanning, !importing else { return }
        importing = true
        task = Task {
            do {
                let face = try await Imaging.detectCard(data)
                try Task.checkCancellation()
                importing = false
                receive(face)
            } catch { importing = false; if !Task.isCancelled { captureError = error.localizedDescription } }
        }
    }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
    private func analyze() async {
        guard let front, let back else { return }
        do {
            async let frontResult = services.process(front)
            async let backResult = services.process(back)
            let (f,b) = try await (frontResult,backResult)
            try Task.checkCancellation()
            card.thumbnail = f.corrected; card.backCorrected = b.corrected
            card.replaceOCR(f.text,front: true); card.replaceOCR(b.text,front: false)
            do {
                let identity = try await services.identify(card.ocr)
                try Task.checkCancellation()
                card.identity = identity
                // Automatic extraction is a candidate, never a false claim of user confirmation.
                card.identity.confirmed = false
            } catch {
                try Task.checkCancellation()
                card.scanNote = "Identity needs review. Both photos are saved."
            }
        } catch {
            guard !Task.isCancelled else { return }
            card.scanNote = "Photo processing needs review. Original photos are saved."
        }
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: services.revealDuration, bounce: 0.2)) { stage = .revealing }
        let revealedAt = Date()
        pricePending = services.canLookup && card.identity.canResearchAutomatically
        if pricePending {
            spinner = Task {
                do {
                    try await pause(services.revealDuration + services.spinnerDelay)
                    if pricePending { withAnimation { showPriceSpinner = true } }
                } catch { }
            }
            do {
                let result = try await services.lookup(card.identity)
                try Task.checkCancellation()
                card.research = result
                if result.estimate == nil { card.scanNote = "No reliable price found. Tap to review." }
            } catch {
                guard !Task.isCancelled else { return }
                card.scanNote = "Price unavailable. Tap to retry in card details."
            }
        } else if card.scanNote == nil {
            card.scanNote = services.canLookup ? "Identity needs review before pricing." : "Price unavailable · connect pricing in Settings."
        }
        pricePending = false; spinner?.cancel(); showPriceSpinner = false
        do {
            try await pause(max(0,services.minimumReveal - Date().timeIntervalSince(revealedAt)))
            try Task.checkCancellation()
            withAnimation(.spring(duration: services.collapseDuration, bounce: 0.12)) { stage = .compact }
            try await pause(services.collapseDuration)
            try Task.checkCancellation()
            stage = .ready
        } catch { }
    }
    func cancel() { cancelled = true; task?.cancel(); spinner?.cancel(); pricePending = false; showPriceSpinner = false }
}

extension Identity {
    var canResearchAutomatically: Bool { [player,year,set,number].allSatisfy { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } }
}
