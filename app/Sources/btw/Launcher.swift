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
        alert.informativeText = "Boot btw, or install another Linux from an arm64 ISO. The first boot downloads the btw disk image once."
        alert.addButton(withTitle: "Boot btw")
        alert.addButton(withTitle: "Install from ISO…")
        alert.addButton(withTitle: "Quit")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return bootBTW()
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

    /// Boots the default VM, giving it a copy of the btw factory disk first if
    /// it has nothing installed yet.
    private static func bootBTW() -> [String] {
        do {
            let bundle = try VMBundle(name: "default")
            if bundle.hasPartitionedDisk { return [] }
            try bundle.removeDisk()
            do {
                return ["--from", try FactoryImage.ensure().path]
            } catch FactoryImage.Failure.notPublished {
                guard let local = chooseLocalImage() else { exit(0) }
                return ["--from", try FactoryImage.use(local).path]
            }
        } catch is CancellationError {
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Before the first release exists, the disk image only lives in a Build
    /// run's artifacts, so let the person pick the one they downloaded.
    private static func chooseLocalImage() -> URL? {
        let alert = NSAlert()
        alert.messageText = "No btw release yet"
        alert.informativeText = "There's no published btw disk image to download yet. If you downloaded btw-factory.tar.gz (or btw-factory.img) from a Build run, choose it."
        alert.addButton(withTitle: "Choose…")
        alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let panel = NSOpenPanel()
        panel.title = "Choose the btw disk image"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
