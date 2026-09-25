import AppKit

/// Rozměry výřezu (notche) a okna, které ho překrývá.
struct NotchGeometry {
    let screen: NSScreen
    let notchSize: CGSize
    /// Velikost okna – dost velká, aby se do ní vešel rozbalený stav.
    let windowSize = CGSize(width: 880, height: 230)
    let expandedSize = CGSize(width: 740, height: 152)

    static func detect() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(screen: screen, notchSize: CGSize(width: width, height: top))
        }
        // Mac bez notche – simulujeme malý ostrůvek pod horní hranou.
        return NotchGeometry(screen: screen, notchSize: CGSize(width: 200, height: 32))
    }

    /// Frame okna v souřadnicích obrazovky (origin vlevo dole).
    var windowFrame: CGRect {
        let f = screen.frame
        return CGRect(x: f.midX - windowSize.width / 2,
                      y: f.maxY - windowSize.height,
                      width: windowSize.width,
                      height: windowSize.height)
    }

    /// Obdélník sbaleného notche v souřadnicích obrazovky.
    var collapsedRect: CGRect {
        let f = screen.frame
        return CGRect(x: f.midX - notchSize.width / 2, y: f.maxY - notchSize.height,
                      width: notchSize.width, height: notchSize.height)
    }

    var expandedRect: CGRect {
        let f = screen.frame
        return CGRect(x: f.midX - expandedSize.width / 2, y: f.maxY - expandedSize.height,
                      width: expandedSize.width, height: expandedSize.height)
    }
}
