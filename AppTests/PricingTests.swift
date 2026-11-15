import XCTest
@testable import CardLedger

final class PricingTests: XCTestCase {
    let id = "4f21caa1-b387-4081-b8d1-07e7e12a2047"
    var identity: Identity { Identity(player:"Anthony Volpe",year:"2023",manufacturer:"Topps",set:"Chrome Update",number:"USC35",variant:"Base",grade:"PSA 9") }
    var record: PricerCard { PricerCard(id:id,player:"Anthony Volpe",year:2023,set:"Topps Chrome Update",cardNumber:"USC35",sport:"baseball",grade:"PSA 9",price:18.73) }
    func envelope(_ object: Any, next: Int? = nil) throws -> Data {
        var result: [String:Any] = ["ok":true,"apiVersion":"1.0.0","data":object]
        if let next { result["meta"] = ["pagination":["nextOffset":next]] }
        return try JSONSerialization.data(withJSONObject:result)
    }
    func json(_ card: PricerCard) throws -> Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(card)) }
    func client(_ replies: [(Int,Data)]) -> (CardPricerClient, Stub) {
        let stub = Stub(replies:replies)
        return (CardPricerClient(spacing:0,transport:{ try await stub.send($0) }),stub)
    }
    actor Stub {
        var replies: [(Int,Data)]; var requests: [URLRequest] = []
        init(replies:[(Int,Data)]) { self.replies = replies }
        func send(_ request: URLRequest) throws -> (Data,HTTPURLResponse) {
            requests.append(request)
            guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
            let reply = replies.removeFirst()
            return (reply.1,HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:nil,headerFields:["Retry-After":"60"])!)
        }
    }
    func evidence(_ title: String, count: Int = 1) throws -> Data {
        try envelope(["card":["id":id],"comps":["total":count,"recent":count == 0 ? []:[["title":title,"grade":"PSA 9"]]],"confidence":["label":"Low","warnings":[]]])
    }
    func testAnonymousQueryUsesStructuredFactsAndNoCredentials() async throws {
        let (api,stub) = client([(200,try envelope([]))])
        let result = try await api.lookup(identity)
        XCTAssertEqual(result.status,.noMatch)
        let requests = await stub.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host,"cardpricer.co"); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"))
        let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "player" }?.value,"Anthony Volpe")
        XCTAssertEqual(query.first { $0.name == "sport" }?.value,"baseball")
    }
    func testRejectsConflictingIdentityAndGrade() {
        XCTAssertTrue(CardPricerClient.possibleMatch(record,identity))
        var card = record
        card.grade = "PSA 10"; XCTAssertFalse(CardPricerClient.possibleMatch(card,identity))
        card = record; card.year = 2022; XCTAssertFalse(CardPricerClient.possibleMatch(card,identity))
        card = record; card.cardNumber = "105"; XCTAssertFalse(CardPricerClient.possibleMatch(card,identity))
        card = record; card.manufacturer = "Panini"; XCTAssertFalse(CardPricerClient.possibleMatch(card,identity))
        card = record; card.id = "../status"; XCTAssertFalse(CardPricerClient.possibleMatch(card,identity))
    }
    func testRealWorldHiddenParallelRequiresReview() async throws {
        let (api,_) = client([(200,try envelope([json(record)])),(200,try envelope(json(record))),
            (200,try evidence("2023 Topps Chrome Update #USC35 Anthony Volpe - Magenta/Purple Lava Lamp Refractor (PSA 9 MINT)"))])
        let result = try await api.lookup(identity)
        XCTAssertEqual(result.status,.review); XCTAssertNil(result.usableValue); XCTAssertEqual(result.candidates.count,1)
    }
    func testExactCompAllowsAttributedProviderEstimate() async throws {
        let (api,_) = client([(200,try envelope([json(record)])),(200,try envelope(json(record))),
            (200,try evidence("2023 Topps Chrome Update #USC35 Anthony Volpe Base PSA 9 MINT"))])
        let result = try await api.lookup(identity)
        XCTAssertEqual(result.usableValue,18.73); XCTAssertEqual(result.confidence,"Low"); XCTAssertEqual(result.compCount,1)
    }
    func testExplicitConfirmationRecordsMissingEvidence() async throws {
        let (api,_) = client([(200,try envelope(json(record))),(200,try evidence("",count:0))])
        let result = try await api.price(identity,candidate:record,confirmed:true)
        XCTAssertTrue(result.userConfirmedMatch); XCTAssertEqual(result.usableValue,18.73)
        XCTAssertTrue(result.warnings.contains { $0.contains("not a verified sale") })
    }
    func testAmbiguousRecordsRequireSelectionAcrossPages() async throws {
        var second = record; second.id = UUID().uuidString
        let (api,stub) = client([(200,try envelope([json(record)],next:100)),(200,try envelope([json(second)]))])
        let result = try await api.lookup(identity)
        XCTAssertEqual(result.status,.review); XCTAssertEqual(result.candidates.count,2)
        let requests = await stub.requests; XCTAssertEqual(requests.count,2)
        XCTAssertTrue(requests[1].url!.absoluteString.contains("offset=100"))
    }
    func testNonAdvancingPaginationFails() async throws {
        let (api,_) = client([(200,try envelope([],next:0))])
        do { _ = try await api.lookup(identity); XCTFail("Expected invalid response") } catch { XCTAssertTrue(error is PricingError) }
    }
    func testRateLimitCooldownPreventsAnotherRequest() async throws {
        let (api,stub) = client([(429,Data())])
        for _ in 0..<2 {
            do { _ = try await api.lookup(identity); XCTFail("Expected rate limit") }
            catch PricingError.rateLimited {} catch { XCTFail("Unexpected error: \(error)") }
        }
        let requests = await stub.requests; XCTAssertEqual(requests.count,1)
    }
    func testMalformedAndOfflineResponsesFailWithoutEstimate() async throws {
        let scenarios: [[(Int,Data)]] = [[(200,Data("{}".utf8))],[(503,Data())],[]]
        for replies in scenarios {
            let (api,_) = client(replies)
            do { _ = try await api.lookup(identity); XCTFail("Expected failure") } catch {}
        }
    }
    func testIncompleteIdentityDoesNotCallNetwork() async throws {
        let (api,stub) = client([]); let result = try await api.lookup(Identity())
        XCTAssertEqual(result.status,.review)
        let requests = await stub.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testMissingVariantNeverAutoConfirms() {
        var unknown = identity; unknown.variant = ""
        XCTAssertFalse(CardPricerClient.variantConfirmed(record,unknown,comps:[]))
    }
    @MainActor func testPriceAndIndependentReferenceSurviveBackup() throws {
        var card = Card(); card.identity = identity
        card.pricing = CardPricing(status:.priced,value:20)
        card.priceCrossCheck = PriceCrossCheck(value:30,identity:identity)
        let store = CollectionStore(file:URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json"))
        try store.save(card)
        let restored = CollectionStore(file:URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json"))
        try restored.restore(Data(contentsOf:store.export()))
        let saved = try XCTUnwrap(restored.cards.first)
        XCTAssertEqual(saved.collectionValue,20); XCTAssertEqual(saved.priceCrossCheck?.difference(from:20),"50% above CardPricer")
        card.manualValue = 40; XCTAssertEqual(card.collectionValue,40)
        card.replaceOCR("Changed",front:true); XCTAssertNil(card.pricing); XCTAssertNil(card.priceCrossCheck)
    }
    func testLegacyCardWithoutNewPricingFieldsDecodes() throws {
        var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Card())) as! [String:Any]
        object.removeValue(forKey:"pricing"); object.removeValue(forKey:"priceCrossCheck")
        let card = try JSONDecoder().decode(Card.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(card.pricing); XCTAssertNil(card.priceCrossCheck); XCTAssertNil(card.collectionValue)
    }
}
