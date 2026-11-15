import XCTest
import SwiftUI
import UIKit
@testable import CardLedger

@MainActor final class CardRowLayoutTests: XCTestCase {
    func testPresentationKeepsOriginalIdentityAndDoesNotRepeatBrand() {
        let identity = Identity(player:"ANTHONY VOLPE",team:"NEW YORK YANKEES",year:"2022",manufacturer:"THE TOPPS COMPANY, INC.",set:"TOPPS INCEPTION")
        XCTAssertEqual(CardRowText.name(identity.player),"Anthony Volpe")
        XCTAssertEqual(CardRowText.metadata(identity),"2022 · Topps Inception")
        XCTAssertEqual(identity.player,"ANTHONY VOLPE")
        XCTAssertEqual(identity.manufacturer,"THE TOPPS COMPANY, INC.")
        XCTAssertEqual(CardRowText.name("DJ LEMAHIEU"),"DJ Lemahieu")
        XCTAssertEqual(CardRowText.name("Jacob deGrom"),"Jacob deGrom")
        XCTAssertEqual(CardRowText.metadata(Identity(year:"2026")),"2026")
        XCTAssertEqual(CardRowText.metadata(Identity()),"")
    }
    func testRowsRenderInBothAppearancesAndGrowForAccessibility() throws {
        var card = Card()
        card.identity = Identity(player:"ANTHONY VOLPE",team:"NEW YORK YANKEES",year:"2022",manufacturer:"THE TOPPS COMPANY, INC.",set:"INCEPTION",number:"105")
        card.scanNote = "No matching card on CardPricer"
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"IMG_2345",withExtension:"jpeg"))
        let image = try XCTUnwrap(UIImage(data:Data(contentsOf:url))?.cgImage)
        let crop = CropSelection(points:[CropPoint(x:272.0/1152,y:405.0/1536),CropPoint(x:911.0/1152,y:391.0/1536),CropPoint(x:923.0/1152,y:1343.0/1536),CropPoint(x:260.0/1152,y:1303.0/1536)])
        card.thumbnail = try Imaging.cropJPEG(image,crop:crop)
        let regular = try snapshot(card,width:361,size:.large,scheme:.dark,name:"Row - dark - unavailable")
        _ = try snapshot(card,width:361,size:.large,scheme:.light,name:"Row - light - unavailable")
        card.manualValue = 12345.67
        _ = try snapshot(card,width:288,size:.large,scheme:.dark,name:"Row - narrow - valued")
        card.identity.player = "A very long player name that must remain readable"
        card.identity.team = "A team name that needs room to wrap"
        let accessible = try snapshot(card,width:288,size:.accessibility5,scheme:.dark,name:"Row - largest accessibility text")
        XCTAssertGreaterThan(accessible.size.height,regular.size.height*2)
        XCTAssertEqual(accessible.size.width,288,accuracy:1)
    }
    private func snapshot(_ card: Card,width:CGFloat,size:DynamicTypeSize,scheme:ColorScheme,name:String) throws -> UIImage {
        let view = CardCollectionRow(card:card).padding(.horizontal,16)
            .frame(width:width).background(Color(uiColor:.secondarySystemGroupedBackground))
            .environment(\.dynamicTypeSize,size).environment(\.colorScheme,scheme)
        let renderer = ImageRenderer(content:view); renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image:image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return image
    }
}
