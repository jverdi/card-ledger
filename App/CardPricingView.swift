import SwiftUI

struct CardPricingSummary: View {
    let pricing: CardPricing
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Link("Prices by CardPricer",destination:CardPricerClient.website).font(.caption)
            if pricing.usableValue == nil { Text(pricing.summary).font(.subheadline) }
            if let confidence = pricing.confidence { Text("Provider confidence: " + confidence).font(.caption).foregroundStyle(.secondary) }
            if let count = pricing.compCount { Text("\(count) provider-reported comparables").font(.caption).foregroundStyle(.secondary) }
            if let updated = pricing.updatedAt, let date = CardPricerClient.date(updated) {
                Text("Price updated " + date.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary)
            } else { Text("Price update date unavailable").font(.caption).foregroundStyle(.secondary) }
            Text("Checked " + pricing.checkedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(pricing.warnings.enumerated()),id:\.offset) { _,warning in Text(warning).font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("pricing.summary")
    }
}

/// Review never changes the card identity. It explicitly confirms a provider record
/// and fetches fresh detail/provenance before accepting its estimate.
struct CardPricingReview: View {
    let identity: Identity
    let initial: CardPricing
    let onSave: (CardPricing) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PricerCard?
    @State private var busy = false
    @State private var error: String?
    @State private var work: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Confirm the exact card").font(.headline)
                    Text("Compare the set, card number, parallel, autograph and grade with your card. A catalog match alone may omit a variation.").font(.subheadline)
                    Text(identity.title + " · " + identity.variant + " · " + identity.grade).font(.caption)
                }
                ForEach(initial.candidates) { candidate in
                    Section {
                        Text(candidate.title).font(.headline)
                        if let value = candidate.price, value.isFinite, value > 0 {
                            Text(value,format:.currency(code:"USD"))
                        } else { Text("No current price") }
                        Text("Variation: " + (candidate.variant ?? "Not specified by CardPricer")).font(.caption)
                        Link("Open CardPricer",destination:CardPricerClient.website)
                        Button("This is my exact card") { selected = candidate }.accessibilityIdentifier("pricing.confirmMatch")
                    }
                }
                if initial.candidates.isEmpty { Text("Edit the identifying details, then refresh the price.") }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView("Checking CardPricer…").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)) } }
            .navigationTitle("Review price match").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { work?.cancel(); dismiss() }.accessibilityIdentifier("pricing.close") }
            .alert("Use this CardPricer match?",isPresented:Binding(get:{ selected != nil },set:{ if !$0 { selected = nil } })) {
                Button("Confirm match") { if let candidate = selected { accept(candidate) }; selected = nil }
                Button("Cancel",role:.cancel) { selected = nil }
            } message: { Text("Only confirm if the set, variation and grade match your card. CardPricer’s estimate may have limited sales evidence.") }
            .alert("Price unavailable",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message:{ Text(error ?? "") }
            .onDisappear { work?.cancel() }
        }.tint(.indigo)
    }
    private func accept(_ candidate: PricerCard) {
        busy = true
        work = Task { @MainActor in
            defer { busy = false }
            do {
                let price = try await PricingService.confirm(identity,candidate:candidate)
                try Task.checkCancellation(); try onSave(price); dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

@MainActor enum PricingService {
    static func lookup(_ identity: Identity) async throws -> CardPricing {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_PRICING_FIXTURE"] == "1" { return CardPricing(status:.review,warnings:["Verify the variation."],candidates:[fixture]) }
        #endif
        return try await CardPricerClient.shared.lookup(identity)
    }
    static func confirm(_ identity: Identity,candidate: PricerCard) async throws -> CardPricing {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CARD_LEDGER_PRICING_FIXTURE"] == "1" {
            return CardPricing(status:.priced,cardID:candidate.id,value:22.5,updatedAt:"2026-11-14T12:00:00Z",confidence:"Low",compCount:1,warnings:["Limited sales evidence."],userConfirmedMatch:true)
        }
        #endif
        return try await CardPricerClient.shared.price(identity,candidate:candidate,confirmed:true)
    }
    #if DEBUG
    static var fixture: PricerCard { PricerCard(id:"9bc03c44-7c3c-454d-bd65-756aa156445c",player:"UI Rookie",year:2026,set:"Test Set",cardNumber:"1",sport:"Baseball",manufacturer:"Test Brand",grade:"Raw",price:22.5) }
    #endif
}
