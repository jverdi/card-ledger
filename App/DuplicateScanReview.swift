import SwiftUI

struct DuplicateScanReview: View {
    let matches: [Card]
    let addDuplicate: () -> Void
    let overwrite: (UUID) -> Void
    let discard: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    init(matches: [Card],addDuplicate: @escaping () -> Void,overwrite: @escaping (UUID) -> Void,discard: @escaping () -> Void) {
        self.matches = matches; self.addDuplicate = addDuplicate; self.overwrite = overwrite; self.discard = discard
        _selected = State(initialValue:matches.count == 1 ? matches[0].id : nil)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Label("Exact match found",systemImage:"rectangle.on.rectangle")
                        .font(.title2.bold()).accessibilityIdentifier("scan.duplicate.title")
                    Text(matches.count == 1 ? "This card is already in your collection." : "You have \(matches.count) matching copies. Select a copy if you want to overwrite it.")
                        .foregroundStyle(.secondary)
                    ForEach(matches) { card in
                        Button { selected = card.id } label: {
                            HStack(spacing:12) {
                                Image(systemName:selected == card.id ? "checkmark.circle.fill":"circle")
                                PhotoView(data:card.thumbnail ?? card.front).frame(width:48,height:68)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(card.identity.player).font(.headline)
                                    Text([card.identity.year,card.identity.manufacturer,card.identity.set,card.identity.number,card.identity.variant,card.identity.grade].filter { !$0.isEmpty }.joined(separator:" · ")).font(.caption)
                                    Text("\(card.status) · Added \(card.added.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                                    if !card.location.isEmpty { Text(card.location).font(.caption) }
                                    if !card.tags.isEmpty { Text(card.tags).font(.caption) }
                                }
                                Spacer(minLength:0)
                            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                                .background(.quaternary,in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain).accessibilityIdentifier("scan.duplicate.match."+card.id.uuidString)
                            .accessibilityAddTraits(selected == card.id ? .isSelected:[])
                    }
                    Text("Overwrite replaces the selected card’s photos and recognition results. Its notes, collection history and manually entered value stay intact.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing:12) {
                        Button("Add duplicate",action:addDuplicate).buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("scan.duplicate.add")
                        Button("Overwrite existing") { if let selected { overwrite(selected) } }
                            .buttonStyle(.bordered).disabled(!matches.contains(where:{ $0.id == selected }))
                            .accessibilityIdentifier("scan.duplicate.overwrite")
                        Button("Discard scan",role:.destructive,action:discard).buttonStyle(.bordered)
                            .accessibilityIdentifier("scan.duplicate.discard")
                    }.controlSize(.large).frame(maxWidth:.infinity)
                }.padding(24)
            }.navigationTitle("Already in your collection").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Back") { dismiss() } } }
        }
    }
}
