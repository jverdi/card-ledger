import SwiftUI

struct CardDetailView: View {
    let cardID: UUID
    @EnvironmentObject private var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Card?
    @State private var removing = false
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
                            VStack(spacing:24) {
                                Spacer(minLength:20)
                                HolographicCard(front:card.thumbnail ?? card.front,back:card.backCorrected ?? card.back)
                                    .frame(width:min(300,max(1,geometry.size.width-48)),height:322)
                                    .accessibilityIdentifier("card.detail.reveal")
                                VStack(spacing:8) {
                                    Text(card.identity.player.isEmpty ? "Unidentified card" : card.identity.player)
                                        .font(.system(size:32,weight:.bold,design:.rounded))
                                        .accessibilityIdentifier("card.detail.player")
                                    if !card.identity.team.isEmpty { Text(card.identity.team).font(.title3).foregroundStyle(.cyan) }
                                    Text([card.identity.manufacturer,card.identity.year,card.identity.set].filter { !$0.isEmpty }.joined(separator:" · "))
                                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                                }.multilineTextAlignment(.center)
                                VStack(spacing:6) {
                                    if let value = card.collectionValue {
                                        Text(value,format:.currency(code:"USD")).font(.title2.bold())
                                        Text(card.valueLabel).font(.caption).foregroundStyle(.white.opacity(0.6))
                                    } else { Text("Not valued").font(.subheadline).foregroundStyle(.white.opacity(0.6)) }
                                }
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
                            Button("Edit",systemImage:"pencil") { editing = card }
                            Button("Remove",systemImage:"trash",role:.destructive) { removing = true }
                        } label: {
                            Image(systemName:"ellipsis").font(.body.bold()).frame(width:44,height:44)
                        }.accessibilityLabel("Card actions").accessibilityIdentifier("card.detail.actions")
                    }
                }
            }
            .sheet(item:$editing) { card in CardEditor(card:card) }
            .confirmationDialog("Remove this card?",isPresented:$removing,titleVisibility:.visible) {
                Button("Remove card",role:.destructive,action:removeCard)
                Button("Cancel",role:.cancel) {}
            } message: { Text("This permanently removes this card and its photos from your collection.") }
            .alert("Couldn’t remove card",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onChange(of:card == nil) { _,missing in if missing { dismiss() } }
        }.preferredColorScheme(.dark).tint(.white)
    }
    private func removeCard() {
        do { try store.delete(cardID); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
