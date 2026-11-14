import XCTest
import UIKit
@testable import CardLedger

final class OrientationTests: XCTestCase {
    private func card(landscape:Bool = false,blank:Bool = false) -> UIImage {
        let size = landscape ? CGSize(width:840,height:600) : CGSize(width:600,height:840)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:size))
            if !blank {
                let lines = ["JORDAN MILLER","CHICAGO BASEBALL","ROOKIE COLLECTION","SEASON 2026"]
                for (index,line) in lines.enumerated() {
                    (line as NSString).draw(at:CGPoint(x:55,y:CGFloat(100+index*80)),withAttributes:[.font:UIFont.systemFont(ofSize:32,weight:.bold),.foregroundColor:UIColor.black])
                }
                UIColor.red.setFill(); context.fill(CGRect(x:24,y:24,width:28,height:28))
            }
        }
    }
    func testPortraitAllFourOrientations() async throws { try await verifyAllRotations(landscape:false) }
    func testLandscapeAllFourOrientationsStayLandscape() async throws { try await verifyAllRotations(landscape:true) }
    private func verifyAllRotations(landscape:Bool) async throws {
        let original = card(landscape:landscape)
        for turns in 0..<4 {
            let data = try XCTUnwrap(Imaging.rotated(original,quarterTurns:turns).pngData())
            let result = try await Imaging.process(data,crop:CropSelection(),automaticallyOrient:true)
            XCTAssertFalse(result.orientationUncertain,"Uncertain for rotation \(turns), landscape \(landscape)")
            XCTAssertEqual(result.crop?.quarterTurns,(4-turns)%4,"Wrong orientation for input \(turns)")
            XCTAssertEqual(result.original,data,"Original evidence changed")
            let output = try XCTUnwrap(UIImage(data:result.corrected))
            XCTAssertEqual(output.size.width/output.size.height,original.size.width/original.size.height,accuracy:0.02)
            XCTAssertTrue(result.text.contains("JORDAN MILLER"))
        }
    }
    func testBlankCardAndAmbiguousEvidenceDoNotGuess() async throws {
        let data = try XCTUnwrap(card(blank:true).pngData())
        let result = try await Imaging.process(data,crop:CropSelection(),automaticallyOrient:true)
        XCTAssertTrue(result.orientationUncertain); XCTAssertEqual(result.crop?.quarterTurns,0)
        XCTAssertEqual(result.original,data)
        let decision = CardOrientation.choose([OrientationEvidence(quarterTurns:0,score:25,characters:30),OrientationEvidence(quarterTurns:2,score:24,characters:30)])
        XCTAssertFalse(decision.confident); XCTAssertEqual(decision.quarterTurns,0)
    }
    func testExplicitManualRotationIsRespectedAndCornersRoundTrip() async throws {
        var crop = CropSelection(points:[CropPoint(x:0.1,y:0.2),CropPoint(x:0.8,y:0.15),CropPoint(x:0.9,y:0.8),CropPoint(x:0.15,y:0.9)])
        let initial = crop
        for _ in 0..<4 { crop = crop.rotatedClockwise(1); XCTAssertTrue(crop.valid) }
        XCTAssertEqual(crop.quarterTurns,0)
        for (a,b) in zip(crop.points,initial.points) { XCTAssertEqual(a.x,b.x,accuracy:0.000001); XCTAssertEqual(a.y,b.y,accuracy:0.000001) }
        let selected = CropSelection().rotatedClockwise(2)
        let result = try await Imaging.process(try XCTUnwrap(card().pngData()),crop:selected)
        XCTAssertEqual(result.crop?.quarterTurns,2)
        XCTAssertFalse(result.orientationUncertain)
    }
    func testRecoveringAnOlderPhotoKeepsItsCropDuringRotation() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = card()
        let photo = UIGraphicsImageRenderer(size:CGSize(width:1000,height:1200),format:format).image { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x:0,y:0,width:1000,height:1200))
            source.draw(in:CGRect(x:200,y:180,width:600,height:840))
        }
        let data = try XCTUnwrap(photo.pngData())
        let recovered = try await Imaging.process(data)
        let crop = try XCTUnwrap(recovered.crop)
        XCTAssertTrue(crop.valid)
        XCTAssertGreaterThan(crop.points[0].x,0.1)
        let rotated = try await Imaging.process(data,crop:crop.rotatedClockwise(1))
        let image = try XCTUnwrap(UIImage(data:rotated.corrected))
        XCTAssertEqual(image.size.width/image.size.height,1.4,accuracy:0.03)
        XCTAssertEqual(rotated.original,data)
    }
    @MainActor func testIndependentFaceRotationSurvivesStoreAndBackup() throws {
        let url = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString).appending(path:"collection.json")
        let store = CollectionStore(file:url)
        var card = Card()
        card.frontCrop = CropSelection().rotatedClockwise(2)
        card.backCrop = CropSelection().rotatedClockwise(3)
        card.frontOrientationUncertain = false; card.backOrientationUncertain = true
        try store.save(card)
        let restored = CollectionStore(file:url)
        XCTAssertEqual(restored.cards.first?.frontCrop?.quarterTurns,2)
        XCTAssertEqual(restored.cards.first?.backCrop?.quarterTurns,3)
        XCTAssertEqual(restored.cards.first?.backOrientationUncertain,true)
        let encoded = try JSONEncoder().encode(restored.cards[0])
        let decoded = try JSONDecoder().decode(Card.self,from:encoded)
        XCTAssertEqual(decoded.frontCrop,card.frontCrop); XCTAssertEqual(decoded.backCrop,card.backCrop)
    }
}
