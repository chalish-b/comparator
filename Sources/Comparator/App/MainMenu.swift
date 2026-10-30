import AppKit

/// The menu bar. Single-key shortcuts are handled by the canvas; they're listed here so they're discoverable.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(imageMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Set", #selector(AppDelegate.newDocument(_:)), "t"))
        menu.addItem(item("Open…", #selector(AppDelegate.openDocument(_:)), "o"))
        menu.addItem(item("Add Images…", #selector(ComparisonWindowController.addImages(_:)), "o", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Single", #selector(CanvasView.showSingle(_:))))
        menu.addItem(item("Split", #selector(CanvasView.toggleSplit(_:)), "s", []))
        menu.addItem(item("Rotate Split", #selector(CanvasView.rotateSplit(_:)), "s", [.shift]))
        menu.addItem(item("Difference", #selector(CanvasView.toggleDifference(_:)), "d", []))
        menu.addItem(.separator())
        menu.addItem(item("Noise View", #selector(CanvasView.toggleNoiseView(_:)), "n", []))
        menu.addItem(item("Increase Noise Radius", #selector(CanvasView.increaseNoiseRadius(_:)), ".", []))
        menu.addItem(item("Decrease Noise Radius", #selector(CanvasView.decreaseNoiseRadius(_:)), ",", []))
        menu.addItem(.separator())
        menu.addItem(item("Increase Gain", #selector(CanvasView.increaseGain(_:)), "]", []))
        menu.addItem(item("Decrease Gain", #selector(CanvasView.decreaseGain(_:)), "[", []))
        menu.addItem(.separator())
        menu.addItem(item("Show Pixels", #selector(CanvasView.togglePixelated(_:)), "p", []))
        menu.addItem(item("Onion Skin Align Overlay", #selector(CanvasView.toggleAlignOverlay(_:)), "o", []))
        menu.addItem(.separator())
        menu.addItem(item("Zoom to Fit", #selector(CanvasView.zoomToFit(_:)), "0", []))
        menu.addItem(item("Actual Pixels", #selector(CanvasView.actualPixels(_:)), "a", []))
        menu.addItem(item("Zoom In", #selector(CanvasView.zoomIn(_:)), "=", []))
        menu.addItem(item("Zoom Out", #selector(CanvasView.zoomOut(_:)), "-", []))
        menu.addItem(.separator())
        menu.addItem(item("Toggle Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command]))
        menu.addItem(item("Show Info", #selector(ComparisonWindowController.toggleInfo(_:)), "i", []))
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func imageMenu() -> NSMenu {
        let menu = NSMenu(title: "Image")
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        menu.addItem(item("Next Image", #selector(CanvasView.nextImage(_:)), down, []))
        menu.addItem(item("Previous Image", #selector(CanvasView.previousImage(_:)), up, []))
        menu.addItem(item("Flip to Last Viewed", #selector(CanvasView.flipImages(_:)), "\t", []))
        menu.addItem(.separator())
        menu.addItem(item("Reset Alignment", #selector(CanvasView.resetAlignment(_:)), "r", [.option]))
        menu.addItem(item("Show in Finder", #selector(CanvasView.showInFinder(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Remove from Set", #selector(CanvasView.removeCurrentImage(_:)), "\u{8}", []))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Keyboard Shortcuts", #selector(CanvasView.toggleHelp(_:)), "h", []))
        return menu
    }
}
