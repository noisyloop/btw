import AppKit
import Foundation
import Virtualization

enum Terminal {
    private static var saved: termios?

    static func makeRaw() {
        guard isatty(STDIN_FILENO) == 1 else { return }
        var attributes = termios()
        guard tcgetattr(STDIN_FILENO, &attributes) == 0 else { return }
        saved = attributes
        cfmakeraw(&attributes)
        tcsetattr(STDIN_FILENO, TCSANOW, &attributes)
    }

    static func restore() {
        guard var attributes = saved else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &attributes)
        saved = nil
    }
}

/// The guest's hvc0. Headless: wired to this terminal, with Ctrl-] as the escape.
/// Windowed: written to the bundle's console.log for debugging boots.
final class SerialConsole {
    static let escapeByte: UInt8 = 0x1d  // Ctrl-]

    let attachment: VZSerialPortAttachment
    var onEscape: (() -> Void)?
    private let toGuest = Pipe()
    private let headless: Bool

    init(headless: Bool, logURL: URL) throws {
        self.headless = headless
        if headless {
            attachment = VZFileHandleSerialPortAttachment(
                fileHandleForReading: toGuest.fileHandleForReading,
                fileHandleForWriting: FileHandle.standardOutput)
        } else {
            attachment = try VZFileSerialPortAttachment(url: logURL, append: false)
        }
    }

    func attachTerminal() {
        guard headless else { return }
        Terminal.makeRaw()
        let writer = toGuest.fileHandleForWriting
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let index = data.firstIndex(of: SerialConsole.escapeByte) {
                writer.write(data[data.startIndex..<index])
                handle.readabilityHandler = nil
                DispatchQueue.main.async { self?.onEscape?() }
            } else {
                writer.write(data)
            }
        }
    }
}

final class VMRunner: NSObject, VZVirtualMachineDelegate, NSApplicationDelegate, NSWindowDelegate {
    private let vm: VZVirtualMachine
    private let options: VMOptions
    private let console: SerialConsole
    private var window: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []
    private var stopping = false

    init(configuration: VZVirtualMachineConfiguration, options: VMOptions, console: SerialConsole) {
        vm = VZVirtualMachine(configuration: configuration)
        self.options = options
        self.console = console
        super.init()
        vm.delegate = self
    }

    func run() -> Never {
        for signal in [SIGINT, SIGTERM] {
            Darwin.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler { [weak self] in self?.forceStop() }
            source.resume()
            signalSources.append(source)
        }

        if options.headless {
            say("serial console attached; press Ctrl-] to stop the VM")
            console.onEscape = { [weak self] in self?.forceStop() }
            console.attachTerminal()
            start()
            dispatchMain()
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        app.mainMenu = makeMainMenu()
        showWindow()
        start()
        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
    }

    private func start() {
        vm.start { result in
            switch result {
            case .success:
                say("VM started")
            case .failure(let error):
                fail("failed to start VM: \(error.localizedDescription)")
            }
        }
    }

    private func showWindow() {
        let view = VZVirtualMachineView()
        view.virtualMachine = vm
        view.capturesSystemKeys = true
        if #available(macOS 14, *) {
            view.automaticallyReconfiguresDisplay = true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "btw — \(options.name)"
        window.contentView = view
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit btw", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        return mainMenu
    }

    // MARK: Stopping

    /// Asks the guest to power off (like pressing the power button), then pulls
    /// the plug if it hasn't gone down after a grace period.
    private func requestStop() {
        guard !stopping else { return }
        stopping = true
        if vm.canRequestStop, (try? vm.requestStop()) != nil {
            say("asked the guest to shut down")
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.forceStop() }
        } else {
            forceStop()
        }
    }

    private func forceStop() {
        stopping = true
        guard vm.canStop else { finish(0) }
        vm.stop { error in
            if let error { say("stop failed: \(error.localizedDescription)") }
            self.finish(0)
        }
    }

    private func finish(_ status: Int32) -> Never {
        Terminal.restore()
        exit(status)
    }

    // MARK: VZVirtualMachineDelegate

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        say("guest powered off")
        finish(0)
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        say("VM stopped with error: \(error.localizedDescription)")
        finish(1)
    }

    // MARK: NSApplicationDelegate / NSWindowDelegate

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestStop()
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestStop()
        return false
    }
}
