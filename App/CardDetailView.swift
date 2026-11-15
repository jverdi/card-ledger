import SwiftUI

struct CardDetailView: View {
    let cardID: UUID
    @EnvironmentObject private var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Card?
    @State private var removing = false
    @State private var pricing = false
    @State private var crossChecking = false
    @State private var reviewingPrice = false
    @State private var priceTask: Task<Void,Never>?
    @State private var error: String?
    // Resolve from the store so saved edits immediately update both faces and labels.
    private var card: Card? { store.cards.first { $0.id == cardID } }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors:[Color(red:0.035,green:0.055,blue:0.11),.black],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
                if let card {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing:32) {
                                Spacer(minLength:20)
                                HolographicCard(front:card.thumbnail ?? card.front,back:card.backCorrected ?? card.back)
                                    .frame(width:min(300,max(1,geometry.size.width-48)),height:322)
                                    .accessibilityIdentifier("card.detail.reveal")
                                CardIdentityHeader(identity:card.identity,playerIdentifier:"card.detail.player")
                                    .padding(.top,6)
                                pricingPanel(card)
                                Spacer(minLength:24)
                            }.padding(.horizontal,24).frame(maxWidth:.infinity,minHeight:geometry.size.height)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .navigationTitle("Card Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button("Close",systemImage:"xmark") { dismiss() }
                        .accessibilityIdentifier("card.detail.close")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    if let card {
                        Menu {
                            Button("Edit",systemImage:"pencil") { priceTask?.cancel(); editing = card }
                            Button("Remove",systemImage:"trash",role:.destructive) { removing = true }
                        } label: {
                            Image(systemName:"ellipsis").font(.body.bold()).frame(width:44,height:44)
                        }.accessibilityLabel("Card actions").accessibilityIdentifier("card.detail.actions")
                    }
                }
            }
            .sheet(isPresented:$crossChecking) {
                if let card {
                    PriceCrossCheckEditor(identity:card.identity,existing:card.priceCrossCheck) { reference in
                        guard var current = self.card,current.identity.details == card.identity.details else { throw PricingError.changedMatch }
                        current.priceCrossCheck = reference; try store.save(current)
                    }
                }
            }
            .sheet(isPresented:$reviewingPrice) {
                if let card, let result = card.pricing {
                    CardPricingReview(identity:card.identity,initial:result) { price in
                        guard var current = self.card, current.identity.details == card.identity.details else { throw PricingError.changedMatch }
                        current.pricing = price; current.scanNote = price.usableValue == nil ? price.summary:nil
                        try store.save(current)
                    }
                }
            }
            .sheet(item:$editing) { card in CardEditor(card:card) }
            .alert("Remove this card?",isPresented:$removing) {
                Button("Remove card",role:.destructive,action:removeCard)
                Button("Cancel",role:.cancel) {}
            } message: { Text("This permanently removes this card and its photos from your collection.") }
            .alert("Card Ledger",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onDisappear { priceTask?.cancel() }
            .onChange(of:card == nil) { _,missing in if missing { dismiss() } }
        }.preferredColorScheme(.dark).tint(.white)
    }
    private func pricingPanel(_ card:Card) -> some View {
        VStack(alignment:.leading,spacing:16) {
            CardValueHeading(card:card)
            if let result = card.pricing, result.usableValue == nil {
                Text(result.summary).font(.footnote).foregroundStyle(.white.opacity(0.6))
            } else if let note = card.scanNote {
                Text(note).font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            if let result = card.pricing, !result.candidates.isEmpty {
                Button("Review price match") { reviewingPrice = true }
                    .font(.subheadline.weight(.medium)).accessibilityIdentifier("pricing.review")
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:14) { priceActions }
                VStack(alignment:.leading,spacing:12) { priceActions }
            }
            if pricing { ProgressView("Checking CardPricer…").font(.caption) }
            if let reference = card.priceCrossCheck,reference.identity.details == card.identity.details {
                VStack(alignment:.leading,spacing:5) {
                    Text("130 Point reference · " + reference.value.formatted(.currency(code:"USD"))).font(.subheadline)
                    if let difference = reference.difference(from:card.pricing?.usableValue) { Text(difference).font(.caption).foregroundStyle(.orange) }
                    Text("Checked by you " + reference.checkedAt.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary)
                    if let link = reference.sourceURL.flatMap(PriceCrossCheck.sourceURL) { Link("View reference",destination:link).font(.caption) }
                }.accessibilityIdentifier("pricing.crossCheckSummary")
            }
            if let result = card.pricing {
                DisclosureGroup("Price details") { CardPricingSummary(pricing:result).padding(.top,10) }
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
        }.padding(18).frame(maxWidth:420,alignment:.leading)
            .background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.white.opacity(0.06),lineWidth:0.5))
    }
    @ViewBuilder private var priceActions: some View {
        Button("Refresh price",systemImage:"arrow.clockwise",action:refreshPrice)
            .font(.subheadline.weight(.medium)).buttonStyle(.bordered).buttonBorderShape(.capsule)
            .disabled(pricing).accessibilityIdentifier("pricing.refresh")
        Button("Check 130 Point") { crossChecking = true }
            .font(.subheadline).foregroundStyle(.cyan.opacity(0.85)).accessibilityIdentifier("pricing.crossCheck")
    }
    private func refreshPrice() {
        guard let snapshot = card, !pricing else { return }
        pricing = true
        priceTask = Task { @MainActor in
            defer { pricing = false }
            do {
                let result = try await PricingService.lookup(snapshot.identity)
                try Task.checkCancellation()
                guard var current = card, current.identity.details == snapshot.identity.details else { throw PricingError.changedMatch }
                current.pricing = result; current.scanNote = result.usableValue == nil ? result.summary:nil
                try store.save(current)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func removeCard() {
        do { try store.delete(cardID); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

