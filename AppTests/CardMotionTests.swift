import XCTest
import SwiftUI
@testable import CardLedger

final class CardMotionTests: XCTestCase {
    func testPauseSnapsToVisibleFaceAndRemainsStill() {
        var motion = CardMotion(); motion.resume(at:0)
        XCTAssertEqual(motion.angle(at:1,speed:43),43)
        motion.pause(at:2.5,speed:43)
        XCTAssertEqual(motion.mode,.paused); XCTAssertEqual(motion.baseAngle,180)
        XCTAssertFalse(CardMotion.frontVisible(at:motion.baseAngle))
        XCTAssertEqual(motion.angle(at:500,speed:43),180)
    }
    func testQuickSwipesFlipPausedFacesInBothDirections() {
        var motion = CardMotion(); motion.resume(at:0); motion.pause(at:0,speed:43)
        motion.beginDrag(at:1,speed:43); motion.drag(x:-80,y:0)
        motion.endDrag(x:-80,y:0,velocityX:-900,at:1.2)
        XCTAssertEqual(motion.mode,.paused); XCTAssertEqual(motion.baseAngle,-180)
        motion.beginDrag(at:2,speed:43); motion.drag(x:80,y:0)
        motion.endDrag(x:80,y:0,velocityX:900,at:2.2)
        XCTAssertEqual(motion.mode,.paused); XCTAssertEqual(motion.baseAngle,0)
    }
    func testManualDragResumesWithoutAngularJump() {
        var motion = CardMotion(); motion.resume(at:0)
        motion.beginDrag(at:1,speed:43); motion.drag(x:100,y:100)
        let angle = motion.baseAngle
        XCTAssertEqual(angle,108); XCTAssertEqual(motion.pitch,-12)
        motion.endDrag(x:100,y:100,velocityX:0,at:2)
        XCTAssertEqual(motion.mode,.spinning)
        XCTAssertEqual(motion.angle(at:2,speed:43),angle)
        XCTAssertEqual(motion.angle(at:3,speed:43),angle+43)
    }
    func testLongDragFromPausedResumesEvenWithFastRelease() {
        var motion = CardMotion(); motion.resume(at:0); motion.pause(at:0,speed:43)
        motion.beginDrag(at:1,speed:43); motion.drag(x:200,y:0)
        motion.endDrag(x:200,y:0,velocityX:900,at:2)
        XCTAssertEqual(motion.mode,.spinning); XCTAssertEqual(motion.baseAngle,130)
    }
    func testFastDragOfSpinningCardDoesNotAccidentallyLatchPause() {
        var motion = CardMotion(); motion.resume(at:0)
        motion.beginDrag(at:1,speed:43); motion.drag(x:100,y:0)
        motion.endDrag(x:100,y:0,velocityX:900,at:1.2)
        XCTAssertEqual(motion.mode,.spinning)
    }
    func testCancelledPausedDragAndReduceMotionStayPaused() {
        var motion = CardMotion(); motion.resume(at:0); motion.pause(at:0,speed:43)
        motion.beginDrag(at:1,speed:43); XCTAssertTrue(motion.canInspect)
        motion.drag(x:20,y:1000); XCTAssertEqual(motion.pitch,-25)
        motion.cancelDrag(at:2); XCTAssertEqual(motion.mode,.paused)
        motion.beginDrag(at:3,speed:43); motion.drag(x:50,y:0)
        motion.endDrag(x:50,y:0,velocityX:0,at:4,allowAutoSpin:false)
        XCTAssertEqual(motion.mode,.paused)
    }
    @MainActor func testIdentityHeaderDeduplicatesBrandAndUsesReadableLayout() throws {
        let identity = Identity(player:"JUSTIN JEFFERSON",team:"MINNESOTA VIKINGS",year:"2022",manufacturer:"PANINI - SCORE FOOTBALL",set:"PANINI",number:"18")
        XCTAssertEqual(CardRowText.metadata(identity),"2022 · Panini Score Football")
        for size in [DynamicTypeSize.large,.accessibility3] {
            let view = CardIdentityHeader(identity:identity).padding(24).frame(width:353)
                .background(Color.black).environment(\.dynamicTypeSize,size)
            let renderer = ImageRenderer(content:view); renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image:image); attachment.name = "Refined card identity - " + String(describing:size); attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(image.size.width,353)
        }
    }
}
