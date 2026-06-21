import CoreGraphics

enum DesktopShellLayout {
    static let sidebarWidth: CGFloat = 240
    static let dividerWidth: CGFloat = 1
    static let detailMinWidth: CGFloat = 640
    static let minimumWindowHeight: CGFloat = 600

    static var minimumWindowWidth: CGFloat {
        sidebarWidth + dividerWidth + detailMinWidth
    }

    static func sidebarWidth(for section: SidebarSection) -> CGFloat {
        sidebarWidth
    }

    static func dividerX(for section: SidebarSection) -> CGFloat {
        sidebarWidth
    }

    static func detailMinWidth(for section: SidebarSection) -> CGFloat {
        detailMinWidth
    }
}
