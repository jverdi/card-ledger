import XCTest
import UIKit
import Vision
import CoreImage
@testable import CardLedger

final class RealCardBoundaryTests: XCTestCase {
    // Independently marked physical corners in the supplied 1152 × 1536 photos.
    // These include the decorative border outside the printed black statistics box.
    let examples: [(String,[CGPoint])] = [
        ("IMG_2345",[CGPoint(x:272,y:405),CGPoint(x:911,y:391),CGPoint(x:923,y:1343),CGPoint(x:260,y:1303)]),
        ("IMG_2346",[CGPoint(x:214,y:379),CGPoint(x:866,y:361),CGPoint(x:896,y:1320),CGPoint(x:209,y:1320)])
    ]
    func testSuppliedBackPhotosIncludeTheDecorativeBorder() async throws {
        for (name,corners) in examples {
            let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:"jpeg"))
            let data = try Data(contentsOf:url)
            let image = try XCTUnwrap(UIImage(data:data))
            let cg = try XCTUnwrap(Imaging.rotated(image,quarterTurns:0).cgImage)
            let rectangles = CardBoundaryDetector.request()
            let document = VNDetectDocumentSegmentationRequest()
            let handler = VNImageRequestHandler(cgImage:cg)
            try handler.perform([rectangles,document])
            let size = CGSize(width:cg.width,height:cg.height)
            for (kind,observations) in [("rectangles",rectangles.results ?? []),("document",document.results ?? [])] {
                let candidates = CardBoundaryDetector.rectangles(observations,size:size)
                print("REAL_CARD_DIAGNOSTIC \(name) \(kind): \(candidates.map { "confidence=\($0.confidence) area=\($0.area) points=\($0.points)" })")
            }
            for radius in [0.0,2.0,4.0] {
                var input = CIImage(cgImage:cg)
                input = input.transformed(by:CGAffineTransform(scaleX:768/CGFloat(cg.height),y:768/CGFloat(cg.height)))
                if radius > 0 { input = input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:radius]).cropped(to:input.extent) }
                let output = try XCTUnwrap(CIContext().createCGImage(input,from:input.extent))
                let broad = VNDetectRectanglesRequest()
                broad.maximumObservations = 0; broad.minimumConfidence = 0.2
                broad.minimumAspectRatio = 0.2; broad.maximumAspectRatio = 1
                broad.minimumSize = 0.15; broad.quadratureTolerance = 40
                try VNImageRequestHandler(cgImage:output).perform([broad])
                print("REAL_CARD_BROAD \(name) radius=\(radius): \(CardBoundaryDetector.rectangles(broad.results ?? [],size:size))")
            }
            guard let face = try? await Imaging.detectCard(data) else { XCTFail("Missing full card: \(name)"); continue }
            for (actual,expected) in zip(face.crop.points,corners) {
                XCTAssertEqual(actual.x,Double(expected.x)/1152,accuracy:0.018,"\(name) physical corner x")
                XCTAssertEqual(actual.y,Double(expected.y)/1536,accuracy:0.018,"\(name) physical corner y")
            }
            let preview = try XCTUnwrap(UIImage(data:try XCTUnwrap(face.preview)))
            let attachment = XCTAttachment(image:preview); attachment.name = "\(name) detected crop"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
