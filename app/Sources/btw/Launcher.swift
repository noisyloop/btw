import AppKit
import UniformTypeIdentifiers

/// Minimal first screen for the .app until the real UI lands (see docs/PLAN.md, M3).
enum Launcher {
    /// True when running from btw.app rather than the bare command-line binary.
    static var isApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func showError(_ message: String) {
        guard Thread.isMainThread else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "btw couldn't start the VM"
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }

    /// Returns extra `btw run` arguments, or exits if the user cancels.
    static func chooseBoot() -> [String] {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "btw"
        alert.informativeText = "Boot your btw VM, or install one from an arm64 ISO."
        alert.addButton(withTitle: "Boot VM")
        alert.addButton(withTitle: "Install from ISO…")
        alert.addButton(withTitle: "Quit")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return []
        case .alertSecondButtonReturn:
            let panel = NSOpenPanel()
            panel.title = "Choose an arm64 Linux ISO"
            panel.allowedContentTypes = [.diskImage]
            panel.allowsOtherFileTypes = true
            guard panel.runModal() == .OK, let url = panel.url else { exit(0) }
            return ["--iso", url.path]
        default:
            exit(0)
        }
    }
}
