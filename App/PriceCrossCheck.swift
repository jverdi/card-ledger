import SwiftUI

struct PriceCrossCheck: Codable, Equatable {
    var value: Decimal
    var checkedAt = Date()
    var sourceURL: String?
    var identity: Identity
    func difference(from price: Double?) -> String? {
        guard let price,price.isFinite,price > 0 else { return nil }
        let reference = NSDecimalNumber(decimal:value).doubleValue
        guard reference.isFinite,reference > 0 else { return nil }
        let percent = abs(reference-price)/price*100
        return String(format:"%.0f%% %@ CardPricer",percent,reference >= price ? "above":"below")
    }
    static func searchText(_ i: Identity) -> String {
        [i.year,i.manufacturer,i.set,i.player,"#"+i.number,i.variant,i.grade].filter { !$0.isEmpty }.joined(separator:" ")
    }
    static func sourceURL(_ text: String) -> URL? {
        guard let url = URL(string:text),url.scheme == "https",url.host != nil,url.user == nil,url.password == nil else { return nil }
        return url
    }
}
struct PriceCrossCheckEditor: View {
    let identity: Identity
    let existing: PriceCrossCheck?
    let onSave: (PriceCrossCheck) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var value: Decimal?
    @State private var source = ""
    @State private var verified = false
    @State private var error: String?
    private var valid: Bool {
        guard let value,!value.isNaN,value > 0,verified else { return false }
        return source.isEmpty || PriceCrossCheck.sourceURL(source) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Look up comparable sales") {
                    Text(PriceCrossCheck.searchText(identity)).textSelection(.enabled)
                    Button("Copy search and open 130 Point") {
                        UIPasteboard.general.string = PriceCrossCheck.searchText(identity)
                        openURL(URL(string:"https://130point.com/search")!)
                    }
                    Text("Paste the search into 130 Point. Compare sold items with the same variation and grade, in USD. This check is manual; the app cannot retrieve 130 Point results automatically.").font(.caption)
                }
                Section("Your 130 Point reference") {
                    MoneyField(title:"Reference price (USD)",value:$value).accessibilityIdentifier("pricing.referenceValue")
                    TextField("Sale or results link (optional)",text:$source).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("I checked the exact card, grade and USD price",isOn:$verified).accessibilityIdentifier("pricing.referenceVerified")
                    Text("Saved separately for comparison. It does not replace or average the CardPricer estimate.").font(.caption)
                }
            }.navigationTitle("130 Point cross-check").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") {
                        guard let value else { return }
                        do { try onSave(PriceCrossCheck(value:value,sourceURL:source.isEmpty ? nil:source,identity:identity)); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!valid).accessibilityIdentifier("pricing.referenceSave") }
                }
                .onAppear { value = existing?.value; source = existing?.sourceURL ?? "" }
                .alert("Couldn’t save cross-check",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message:{ Text(error ?? "") }
        }
    }
}
