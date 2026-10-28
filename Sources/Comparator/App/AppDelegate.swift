import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [ComparisonWindowController] = []
    /// Finder can deliver one multi-file open in several batches; batches arriving
    /// close together go into the same set.
    private var lastOpen: (controller: ComparisonWindowController, time: Date)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if controllers.isEmpty {
            makeController().showWindow(nil)
        }
        NSApp.activate()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        let scheme = OpenRequest.scheme(ofAppAt: Bundle.main.bundleURL)
        for url in urls where url.scheme == scheme {
            if let request = OpenRequest(url: url) { open(request) }
        }
        open(ImageFiles.expand(urls.filter(\.isFileURL)))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { makeController().showWindow(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Sets

    func makeController() -> ComparisonWindowController {
        let controller = ComparisonWindowController()
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        return controller
    }

    /// Opens images as a new set, reusing an empty window if there is one.
    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let last = lastOpen,
           Date().timeIntervalSince(last.time) < 0.5,
           controllers.contains(where: { $0 === last.controller }) {
            last.controller.imageSet.add(urls)
            lastOpen = (last.controller, Date())
            return
        }

        let controller = emptyOrNewController()
        controller.imageSet.add(urls)
        controller.showWindow(nil)
        lastOpen = (controller, Date())
    }

    /// Opens a request from the command line as a new set.
    private func open(_ request: OpenRequest) {
        let controller = emptyOrNewController()
        controller.apply(request)
        controller.showWindow(nil)
        lastOpen = nil
    }

    private func emptyOrNewController() -> ComparisonWindowController {
        let keyController = NSApp.keyWindow?.windowController as? ComparisonWindowController
        let candidates = [keyController].compactMap { $0 } + controllers
        return candidates.first { $0.imageSet.items.isEmpty } ?? makeController()
    }

    @objc func newDocument(_ sender: Any?) {
        makeController().showWindow(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel.forImages()
        guard panel.runModal() == .OK else { return }
        open(ImageFiles.expand(panel.urls))
    }
}
