import Foundation
import Security

enum Credentials {
    static func read() -> String {
        var result: CFTypeRef?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CardLedger.worker", kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "CardLedger.worker"]
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }
}
enum ResearchClient {
    static func lookup(_ identity: Identity, base: String) async throws -> Research {
        guard identity.confirmed, let url = URL(string: base), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw ClientError.configuration }
        var request = URLRequest(url: url.appending(path: "research")); request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + Credentials.read(), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(identity)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ClientError.failed }
        return try JSONDecoder().decode(Research.self, from: data)
    }
    enum ClientError: LocalizedError {
        case configuration, failed
        var errorDescription: String? { self == .configuration ? "Confirm the card and configure an HTTPS research worker in Settings." : "Pricing research failed. Your saved card and previous value are unchanged. Check the worker connection and try again." }
    }
}
