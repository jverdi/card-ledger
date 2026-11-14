import XCTest
import UIKit
import Vision
@testable import CardLedger

final class CardBoundaryTests: XCTestCase {
    func rect(_ frame: CGRect, confidence: Float = 0.95) -> CardRectangle {
        CardRectangle(points:[CGPoint(x:frame.minX,y:frame.minY),CGPoint(x:frame.maxX,y:frame.minY),CGPoint(x:frame.maxX,y:frame.maxY),CGPoint(x:frame.minX,y:frame.maxY)],confidence:confidence,pixelSize:CGSize(width:700,height:1000))
    }
    func testLargestBoundaryWinsRegardlessOfConfidenceOrResultOrder() {
        let outer = rect(CGRect(x:0.1,y:0.1,width:0.8,height:0.8),confidence:0.72)
        let table = rect(CGRect(x:0.25,y:0.25,width:0.5,height:0.5),confidence:0.99)
        let border = rect(CGRect(x:0.15,y:0.15,width:0.7,height:0.7))
        for rectangles in [[table,border,outer],[outer,border,table],[border,outer,table]] {
            XCTAssertEqual(CardBoundaryDetector.outermost(rectangles),outer)
        }
        // A bigger square in the background is not a plausible card.
        var square = rect(CGRect(x:0.05,y:0.05,width:0.9,height:0.9)); square.pixelSize = CGSize(width:1000,height:1000)
        XCTAssertEqual(CardBoundaryDetector.outermost([square,table,outer]),outer)
    }
    func testClippedOuterCardDoesNotFallBackToAnInternalTable() {
        let outer = rect(CGRect(x:0,y:0,width:1,height:1))
        let inner = rect(CGRect(x:0.25,y:0.25,width:0.5,height:0.5))
        XCTAssertNil(CardBoundaryDetector.outermost([inner,outer]))
        XCTAssertNil(CardBoundaryDetector.outermost([]))
    }
    func statsBack(landscape: Bool) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size:CGSize(width:800,height:1100),format:format).image { context in
            UIColor(white:0.13,alpha:1).setFill(); context.fill(CGRect(x:0,y:0,width:800,height:1100))
            UIColor(white:0.88,alpha:1).setFill(); context.fill(CGRect(x:150,y:200,width:500,height:700))
            UIColor.black.setStroke()
            let border = UIBezierPath(rect:CGRect(x:170,y:220,width:460,height:660)); border.lineWidth = 3; border.stroke()
            ("PLAYER CAREER STATS" as NSString).draw(at:CGPoint(x:190,y:250),withAttributes:[.font:UIFont.boldSystemFont(ofSize:24),.foregroundColor:UIColor.black])
            let table = UIBezierPath(rect:CGRect(x:200,y:330,width:400,height:470)); table.lineWidth = 4; table.stroke()
            for row in 0..<12 {
                let y = CGFloat(350 + row*36)
                ("2026  NY  162  .315  35  102" as NSString).draw(at:CGPoint(x:214,y:y),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:17,weight:.regular),.foregroundColor:UIColor.black])
                let line = UIBezierPath(); line.move(to:CGPoint(x:200,y:y+26)); line.addLine(to:CGPoint(x:600,y:y+26)); line.lineWidth = 1; line.stroke()
            }
        }
        return Imaging.rotated(image,quarterTurns:landscape ? 1:0).jpegData(compressionQuality:0.95)!
    }
    func testRealVisionKeepsOuterEdgesOfStatsBackInBothOrientations() async throws {
        for landscape in [false,true] {
            let data = statsBack(landscape:landscape)
            let face = try await Imaging.detectCard(data)
            let xs = face.crop.points.map(\.x), ys = face.crop.points.map(\.y)
            // The outer card, not its black border or nested statistics table.
            XCTAssertEqual(xs.min()!,landscape ? 200.0/1100:150.0/800,accuracy:0.014)
            XCTAssertEqual(xs.max()!,landscape ? 900.0/1100:650.0/800,accuracy:0.014)
            XCTAssertEqual(ys.min()!,landscape ? 150.0/800:200.0/1100,accuracy:0.014)
            XCTAssertEqual(ys.max()!,landscape ? 650.0/800:900.0/1100,accuracy:0.014)
            XCTAssertEqual(face.original,data)
            let preview = try XCTUnwrap(UIImage(data:try XCTUnwrap(face.preview)))
            XCTAssertEqual(preview.size.width/preview.size.height,landscape ? 1.4:1/1.4,accuracy:0.035)
            let processed = try await Imaging.process(data)
            XCTAssertEqual(try XCTUnwrap(processed.crop).points.count,4)
            XCTAssertEqual(try XCTUnwrap(processed.crop).points[0].x,face.crop.points[0].x,accuracy:0.014)
        }
    }
}
