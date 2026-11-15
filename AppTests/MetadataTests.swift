import XCTest
@testable import CardLedger

final class MetadataTests: XCTestCase {
    func testCanonicalMetadataIsIndependentOfPrintedCapitalization() {
        let raw = Identity(player:"  ANTHONY   vOLPE ",team:"NEW YORK YANKEES",sport:"bASEBALL",year:"2024 / 2025",manufacturer:"THE TOPPS COMPANY, INC.",set:"TOPPS CHROME",number:"usc35",variant:"GOLD RC",grade:"psa 9")
        let normalized = raw.normalized
        XCTAssertEqual(normalized.player,"Anthony Volpe"); XCTAssertEqual(normalized.team,"New York Yankees")
        XCTAssertEqual(normalized.sport,"Baseball"); XCTAssertEqual(normalized.year,"2024")
        XCTAssertEqual(normalized.sourceYear,"2024 / 2025"); XCTAssertEqual(normalized.manufacturer,"Topps")
        XCTAssertEqual(normalized.set,"Topps Chrome"); XCTAssertEqual(normalized.number,"USC35")
        XCTAssertEqual(normalized.variant,"Gold RC"); XCTAssertEqual(normalized.grade,"PSA 9")
        XCTAssertEqual(normalized.normalized,normalized)
        XCTAssertEqual(CardMetadata.title("jacob DEGROM"),"Jacob deGrom")
        XCTAssertEqual(CardMetadata.title("DJ LEMAHIEU"),"DJ LeMahieu")
        XCTAssertEqual(CardMetadata.title("ELLY DE LA CRUZ"),"Elly de la Cruz")
        XCTAssertEqual(CardMetadata.title("VLADIMIR GUERRERO JR."),"Vladimir Guerrero Jr.")
        XCTAssertEqual(Identity(sport:"pokemon").normalized.sport,"Pokémon")
        XCTAssertEqual(Identity(sport:"POKÉMON").normalized.sport,"Pokémon")
        XCTAssertEqual(Set(["Baseball","BASEBALL","baseball"].map { Identity(sport:$0).normalized.sport }).count,1)
    }
    func testYearsUseSeasonStartAndDoNotInventMissingYears() {
        for year in ["2024", "2024/25", "2024/2025", "2024–25", "2024-2025"] { XCTAssertEqual(CardMetadata.year(year),"2024") }
        XCTAssertEqual(CardMetadata.year("1999/00"),"1999")
        for year in ["", "unknown", "24", "2024/26", "2024//2025", "2022, 2023", "© 2023", "2024-"] { XCTAssertEqual(CardMetadata.year(year),"",year) }
        let invalid = Identity(year:"Unknown season").normalized
        XCTAssertEqual(invalid.sourceYear,"Unknown season"); XCTAssertEqual(invalid.year,"")
    }
    func card(_ name:String, year:String = "", value:Decimal? = nil, added:Double = 0) -> Card {
        var card = Card(); card.identity.player = name; card.identity.year = year
        card.manualValue = value; card.added = Date(timeIntervalSince1970:added); return card
    }
    func testSurnameSortBothDirectionsWithSuffixesAndParticles() {
        let cards = [card("Aaron Judge"),card("Zach Allen"),card("Vladimir Guerrero Jr."),card("Elly de la Cruz"),card("Ichiro"),card("")]
        XCTAssertEqual(CollectionSort.name.sorted(cards,ascending:true).map { $0.identity.player },["Zach Allen","Elly de la Cruz","Vladimir Guerrero Jr.","Ichiro","Aaron Judge",""])
        XCTAssertEqual(CollectionSort.name.sorted(cards,ascending:false).map { $0.identity.player },["Aaron Judge","Ichiro","Vladimir Guerrero Jr.","Elly de la Cruz","Zach Allen",""])
    }
    func testNumericSortsAndDateAddedKeepUnknownValuesLast() {
        let a = card("A",year:"1999",value:2,added:3), b = card("B",year:"2024/25",value:10,added:1), c = card("C",added:2)
        let cards = [c,b,a]
        for sort in [CollectionSort.year,.value] {
            XCTAssertEqual(sort.sorted(cards,ascending:true).map(\.id),[a.id,b.id,c.id])
            XCTAssertEqual(sort.sorted(cards,ascending:false).map(\.id),[b.id,a.id,c.id])
        }
        XCTAssertEqual(CollectionSort.added.sorted(cards,ascending:true).map(\.id),[b.id,c.id,a.id])
        XCTAssertEqual(CollectionSort.added.sorted(cards,ascending:false).map(\.id),[a.id,c.id,b.id])
    }
    @MainActor func testLegacyMetadataMigratesWithoutLosingHistoryPhotosOrPricing() throws {
        let path = URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json")
        try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
        var card = card("ANTHONY VOLPE",year:"2024/25",value:12,added:123)
        card.identity.sport = "baseball"; card.front = Data([1,2,3]); card.notes = "My ORIGINAL Notes"
        card.priceCrossCheck = PriceCrossCheck(value:20,identity:card.identity)
        try JSONEncoder().encode(Archive(cards:[card])).write(to:path)
        let store = CollectionStore(file:path)
        XCTAssertNil(store.error)
        let saved = try XCTUnwrap(store.cards.first)
        XCTAssertEqual(saved.identity.player,"Anthony Volpe"); XCTAssertEqual(saved.identity.year,"2024")
        XCTAssertEqual(saved.identity.sourceYear,"2024/25"); XCTAssertEqual(saved.identity.sport,"Baseball")
        XCTAssertEqual(saved.priceCrossCheck?.identity.details,saved.identity.details)
        XCTAssertEqual(saved.photoData,card.photoData); XCTAssertEqual(saved.notes,card.notes)
        XCTAssertEqual(saved.manualValue,card.manualValue); XCTAssertEqual(saved.added,card.added); XCTAssertEqual(saved.id,card.id)
        XCTAssertEqual(CollectionStore(file:path).cards.first?.identity,saved.identity)
        let restored = CollectionStore(file:URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json"))
        try restored.restore(JSONEncoder().encode(Archive(cards:[card])))
        XCTAssertEqual(restored.cards.first?.identity,saved.identity)
        XCTAssertEqual(try JSONDecoder().decode(Archive.self,from:Data(contentsOf:path)).cards.first?.identity,saved.identity)
    }
    func testSeasonAndCaseDifferencesStillDetectDuplicates() {
        var a = Card(); a.identity = Identity(player:"Anthony Volpe",year:"2024",manufacturer:"Topps",set:"Chrome",number:"1",variant:"Base")
        var b = a; b.id = UUID(); b.identity.player = "ANTHONY VOLPE"; b.identity.year = "2024/25"; b.identity.manufacturer = "THE TOPPS COMPANY, INC."
        XCTAssertTrue(CardDuplicates.exactMatch(a,b))
        XCTAssertEqual(a.identity.details,b.identity.details)
    }
}
