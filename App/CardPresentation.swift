import SwiftUI

struct CardIdentityHeader: View {
    let identity: Identity
    var placeholder = "Unidentified card"
    var playerIdentifier = "card.identity.player"
    private var name: String { identity.player.isEmpty ? placeholder:CardMetadata.title(identity.player) }
    private var details: String {
        [identity.number.isEmpty ? "":"#"+identity.number,
         identity.variant.lowercased() == "base" ? "":CardMetadata.title(identity.variant),
         identity.grade.lowercased() == "raw" ? "":CardMetadata.title(identity.grade)]
            .filter { !$0.isEmpty }.joined(separator:" · ")
    }
    var body: some View {
        VStack(spacing:0) {
            Text(name).font(.title.weight(.semibold)).tracking(-0.35)
                .foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)
                .accessibilityIdentifier(playerIdentifier)
            if !identity.team.isEmpty {
                Text(CardMetadata.title(identity.team)).font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72)).padding(.top,6)
            }
            let product = CardRowText.metadata(identity)
            if !product.isEmpty {
                Text(product).font(.subheadline).foregroundStyle(.white.opacity(0.52)).padding(.top,14)
            }
            if !details.isEmpty {
                Text(details).font(.caption).foregroundStyle(.white.opacity(0.48)).padding(.top,5)
            }
        }.multilineTextAlignment(.center).frame(maxWidth:420)
    }
}

struct CardValueHeading: View {
    let card: Card
    var body: some View {
        if let value = card.collectionValue {
            VStack(alignment:.leading,spacing:5) {
                Text(card.valueLabel).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                Text(value,format:.currency(code:"USD")).font(.title2.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
        } else {
            Label("Price unavailable",systemImage:"tag").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
        }
    }
}
