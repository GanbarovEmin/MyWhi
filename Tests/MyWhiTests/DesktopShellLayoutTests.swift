import XCTest
@testable import MyWhi

final class DesktopShellLayoutTests: XCTestCase {

    func testDesktopShellGeometryIsStableAcrossSections() {
        for section in SidebarSection.allCases {
            XCTAssertEqual(DesktopShellLayout.sidebarWidth(for: section), 240)
            XCTAssertEqual(DesktopShellLayout.dividerX(for: section), 240)
            XCTAssertEqual(DesktopShellLayout.detailMinWidth(for: section), 640)
        }
    }

    func testDesktopShellMinimumWindowWidthMatchesPaneContract() {
        XCTAssertEqual(
            DesktopShellLayout.minimumWindowWidth,
            DesktopShellLayout.sidebarWidth + DesktopShellLayout.dividerWidth + DesktopShellLayout.detailMinWidth
        )
        XCTAssertEqual(DesktopShellLayout.minimumWindowWidth, 881)
    }
}
