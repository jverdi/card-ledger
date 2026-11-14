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
            let handler = VNImageRequestHandler(cgImage:cg)
            let foreground = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([foreground])
            for observation in foreground.results ?? [] {
                for instance in observation.allInstances {
                    let mask = try observation.generateScaledMaskForImage(forInstances:IndexSet(integer:instance),from:handler)
                    let ci = CIImage(cvPixelBuffer:mask)
                    let rendered = try XCTUnwrap(CIContext().createCGImage(ci,from:ci.extent,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB()))
                    let attachment = XCTAttachment(image:UIImage(cgImage:rendered)); attachment.name = "\(name) foreground \(instance)"; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
            let face: CapturedFace
            do { face = try await Imaging.detectCard(data) }
            catch { XCTFail("Missing full card: \(name): \(error)"); continue }
            for (actual,expected) in zip(face.crop.points,corners) {
                XCTAssertEqual(actual.x,Double(expected.x)/1152,accuracy:0.018,"\(name) physical corner x")
                XCTAssertEqual(actual.y,Double(expected.y)/1536,accuracy:0.018,"\(name) physical corner y")
            }
            let preview = try XCTUnwrap(UIImage(data:try XCTUnwrap(face.preview)))
            let attachment = XCTAttachment(image:preview); attachment.name = "\(name) detected crop"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
