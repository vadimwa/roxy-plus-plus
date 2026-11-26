import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllerStorage: MainWindowController?

    var controller: MainWindowController {
        if let c = controllerStorage { return c }
        let c = MainWindowController()
        controllerStorage = c
        return c
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.register()
        Prefs.applyAppearance()
        NSApp.mainMenu = MenuBuilder.build(controller: controller)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files passed on the command line: `MacPad file1 file2` (ignores -psn / -Apple* flags)
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if !args.isEmpty {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let urls = args.map { URL(fileURLWithPath: $0, relativeTo: cwd).standardizedFileURL }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { controller.open(urls: urls) }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        controller.open(urls: urls)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controllerStorage?.saveSession()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controllerStorage?.checkExternalChanges()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
