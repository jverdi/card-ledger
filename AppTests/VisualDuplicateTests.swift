import XCTest
import UIKit
import CoreImage
@testable import CardLedger

@MainActor final class VisualDuplicateTests: XCTestCase {
    /// Original synthetic artwork; no customer collection screenshots in the repo.
    func artwork(seed: Int = 1) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size:CGSize(width:320,height:448),format:format).jpegData(withCompressionQuality:0.95) { c in
            UIColor.white.setFill(); c.fill(CGRect(x:0,y:0,width:320,height:448))
            for i in 0..<80 {
                let n = (i * 7919 + seed * 104729) % 65521
                UIColor(hue:CGFloat(n%997)/997,saturation:0.65,brightness:CGFloat(40+n%60)/100,alpha:1).setFill()
                c.cgContext.fillEllipse(in:CGRect(x:CGFloat((n*13)%280),y:CGFloat((n*29)%408),width:CGFloat(30+n%50),height:CGFloat(30+n%70)))
            }
            ("ROOKIE 27" as NSString).draw(at:CGPoint(x:35,y:380),withAttributes:[.font:UIFont.boldSystemFont(ofSize:25),.foregroundColor:UIColor.black])
        }
    }
    func scan(front: Data, back: Data? = nil) -> Card {
        var card = Card()
        card.identity = Identity(player:"Cam Schlittler",team:"New York Yankees",year:"2022",manufacturer:"Topps",set:"Splayers",number:"",variant:"")
        card.front = front; card.thumbnail = front; card.back = back; card.backCorrected = back
        return card
    }
    func recapture(_ data: Data, turns: Int = 0) throws -> Data {
        let image = try XCTUnwrap(UIImage(data:data))
        let shifted = UIGraphicsImageRenderer(size:image.size).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(origin:.zero,size:image.size))
            image.draw(in:CGRect(x:3,y:4,width:image.size.width-6,height:image.size.height-8))
        }
        let ci = try XCTUnwrap(CIImage(image:shifted)).applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:0.06,kCIInputContrastKey:0.9])
        let cg = try XCTUnwrap(CIContext().createCGImage(ci,from:ci.extent))
        return try XCTUnwrap(Imaging.rotated(UIImage(cgImage:cg),quarterTurns:turns).jpegData(compressionQuality:0.7))
    }
    func testSameArtworkWithNoisySetMissingNumberAndVariantIsPossibleNotExact() throws {
        let original = artwork(), existing = scan(front:original)
        for turn in 0..<4 {
            var scanned = scan(front:try recapture(original,turns:turn)); scanned.identity.set = "Cmp154977"
            XCTAssertFalse(CardDuplicates.exactMatch(scanned,existing))
            XCTAssertGreaterThanOrEqual(CardVisualMatch.similarity(scanned.thumbnail,existing.thumbnail),0.86)
            XCTAssertTrue(CardDuplicates.needsReview(scanned,existing),"Rotation \(turn)")
            XCTAssertEqual(CardDuplicates.matches(for:scanned,in:[existing]).map(\.id),[existing.id])
        }
    }
    func testNameYearTeamAndManufacturerAloneDoNotMakeDifferentArtworkADuplicate() {
        let a = scan(front:artwork(seed:1))
        for seed in 2...6 {
            let b = scan(front:artwork(seed:seed))
            XCTAssertFalse(CardDuplicates.needsReview(a,b),"Distinct artwork \(seed)")
        }
    }
    func testBlankOrInvalidPhotosAreNotVisualEvidence() {
        let white = UIGraphicsImageRenderer(size:CGSize(width:100,height:140)).jpegData(withCompressionQuality:0.8) { c in
            UIColor.white.setFill(); c.fill(CGRect(x:0,y:0,width:100,height:140))
        }
        XCTAssertEqual(CardVisualMatch.similarity(white,white),0)
        XCTAssertFalse(CardDuplicates.needsReview(scan(front:white),scan(front:white)))
        XCTAssertFalse(CardDuplicates.needsReview(scan(front:Data([1])),scan(front:Data([1]))))
        XCTAssertEqual(CardVisualMatch.similarity(nil,white),0)
    }
    func testUncertainNameRequiresBothFacesAndKnownCertificatesRemainDistinct() {
        let original = scan(front:artwork(),back:artwork(seed:7))
        var scanned = original; scanned.id = UUID(); scanned.identity.player = ""
        XCTAssertTrue(CardDuplicates.needsReview(scanned,original))
        scanned.back = artwork(seed:8); scanned.backCorrected = scanned.back
        XCTAssertFalse(CardDuplicates.needsReview(scanned,original))
        var a = original, b = original; a.identity.certificate = "1234"; b.identity.certificate = "5678"
        XCTAssertFalse(CardDuplicates.needsReview(a,b))
        a = original; b = original; a.identity.confirmed = true; b.identity.confirmed = true; b.identity.variant = "Gold"
        XCTAssertFalse(CardDuplicates.needsReview(a,b))
    }
    func testMatchingCatalogWithUnknownVariantPromptsWithoutClaimingExactMatch() {
        var a = scan(front:Data([1])); a.identity.set = "Holiday"; a.identity.number = "27"; a.identity.variant = "Base"
        var b = a; b.id = UUID(); b.identity.variant = ""
        XCTAssertFalse(CardDuplicates.exactMatch(a,b)); XCTAssertTrue(CardDuplicates.needsReview(a,b))
        b.identity.variant = "Gold"
        XCTAssertFalse(CardDuplicates.needsReview(a,b))
    }
    func testSaveRechecksPossibleDuplicateAndExplicitChoicesPreserveHistory() throws {
        let url = URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json")
        let store = CollectionStore(file:url)
        var existing = scan(front:artwork()); existing.notes = "Keep"; existing.manualValue = 12.34
        try store.save(existing)
        var scanned = scan(front:try recapture(existing.thumbnail!)); scanned.identity.set = "Cmp154977"
        XCTAssertThrowsError(try store.saveScan(scanned))
        XCTAssertEqual(store.cards.count,1)
        let overwritten = try store.saveScan(scanned,replacing:existing.id)
        XCTAssertEqual(overwritten.id,existing.id); XCTAssertEqual(overwritten.added,existing.added)
        XCTAssertEqual(overwritten.notes,"Keep"); XCTAssertEqual(overwritten.manualValue,12.34)
        XCTAssertEqual(overwritten.identity.set,"Cmp154977")
        _ = try store.saveScan(scanned,duplicateConfirmed:true)
        XCTAssertEqual(CollectionStore(file:url).cards.count,2)
    }
    func testBatchNoisyRecognitionWaitsForReviewAndCanOverwrite() async throws {
        let url = URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json")
        let store = CollectionStore(file:url)
        var existing = scan(front:artwork(),back:artwork(seed:7)); existing.notes = "Batch history"
        try store.save(existing)
        var scanned = scan(front:try recapture(existing.thumbnail!),back:existing.back)
        scanned.frontCrop = CropSelection(); scanned.backCrop = CropSelection()
        var identity = scanned.identity; identity.set = "Cmp154977"
        let coordinator = BatchScanCoordinator()
        coordinator.services = ScanServices(process:{ PhotoResult(original:$0.original,corrected:$0.original,text:"OCR") },identify:{ _ in identity },lookup:{ _ in throw ScanFailure.timeout },canLookup:false,revealDuration:0,minimumReveal:0)
        try coordinator.enqueue(scanned,store:store)
        for _ in 0..<200 {
            if coordinator.pendingCount(store) == 0 { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertEqual(coordinator.pendingCount(store),0)
        XCTAssertEqual(coordinator.duplicateCount(store),1)
        let pending = try XCTUnwrap(store.cards.first { $0.batchState == "duplicate" })
        XCTAssertEqual(store.cards.filter { $0.batchState == nil }.count,1)
        try store.resolveBatch(pending,replacing:existing.id)
        let reopened = CollectionStore(file:url)
        XCTAssertEqual(reopened.cards.count,1); XCTAssertEqual(reopened.cards[0].id,existing.id)
        XCTAssertEqual(reopened.cards[0].notes,"Batch history"); XCTAssertNil(reopened.cards[0].batchState)
    }
}
