import AppKit
import Foundation

/// The btw factory disk: downloaded once from the latest GitHub release,
/// unpacked next to the VMs, and cloned (copy-on-write) into each new VM's disk.
enum FactoryImage {
    static let releaseURL = URL(string: "https://github.com/noisyloop/btw/releases/latest/download/btw-factory.tar.gz")!

    enum Failure: LocalizedError {
        case notPublished

        var errorDescription: String? {
            "No btw release with a disk image has been published yet."
        }
    }

    static func directory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = support.appendingPathComponent("btw/factory", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func imageURL() throws -> URL {
        try directory().appendingPathComponent("btw-factory.img")
    }

    /// Returns the unpacked factory image, downloading it first if needed.
    static func ensure() throws -> URL {
        let image = try imageURL()
        if FileManager.default.fileExists(atPath: image.path) { return image }

        let archive = try directory().appendingPathComponent("btw-factory.tar.gz")
        let window = ProgressWindow(title: "Setting up btw")
        defer { window.close() }
        window.update("Downloading btw…")
        let download = FactoryDownload(destination: archive) { written, total in
            DispatchQueue.main.async {
                let done = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
                if total > 0 {
                    let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                    window.update("Downloading btw: \(done) of \(all)", fraction: Double(written) / Double(total))
                } else {
                    window.update("Downloading btw: \(done)")
                }
            }
        }
        window.onCancel = { download.cancel() }
        try window.run { try download.run(releaseURL) }
        return try unpack(archive, window: window, deleteArchive: true)
    }

    /// Uses a disk image the person picked: a btw-factory.img as is, or a
    /// btw-factory.tar.gz (from a release or a Build run's artifacts, possibly
    /// already un-gzipped by Safari) unpacked.
    static func use(_ file: URL) throws -> URL {
        let name = file.lastPathComponent.lowercased()
        if name.hasSuffix(".img") { return file }
        guard name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") || name.hasSuffix(".tar") else {
            throw BTWError("Choose btw-factory.tar.gz or btw-factory.img.")
        }
        let window = ProgressWindow(title: "Setting up btw")
        defer { window.close() }
        return try unpack(file, window: window, deleteArchive: false)
    }

    private static func unpack(_ archive: URL, window: ProgressWindow, deleteArchive: Bool) throws -> URL {
        let directory = try directory()
        let image = try imageURL()
        // Unpack into a scratch folder first so an interrupted unpack never
        // leaves a half-written image where the next launch would trust it.
        let scratch = directory.appendingPathComponent("unpacking", isDirectory: true)
        try? FileManager.default.removeItem(at: scratch)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        window.update("Unpacking btw…")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", scratch.path]  // tar detects gzip itself
        window.onCancel = { tar.terminate() }
        try window.run {
            try tar.run()
            tar.waitUntilExit()
            guard tar.terminationStatus == 0 else {
                throw BTWError("Couldn't unpack \(archive.lastPathComponent) (tar exited with status \(tar.terminationStatus)).")
            }
        }

        let unpacked = scratch.appendingPathComponent("btw-factory.img")
        guard FileManager.default.fileExists(atPath: unpacked.path) else {
            throw BTWError("\(archive.lastPathComponent) doesn't contain btw-factory.img.")
        }
        try? FileManager.default.removeItem(at: image)
        try FileManager.default.moveItem(at: unpacked, to: image)
        if deleteArchive { try? FileManager.default.removeItem(at: archive) }
        return image
    }
}

/// A blocking download with progress, run off the main thread.
final class FactoryDownload: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let report: (Int64, Int64) -> Void
    private let finished = DispatchSemaphore(value: 0)
    private var failure: Error?
    private var task: URLSessionDownloadTask?

    init(destination: URL, report: @escaping (Int64, Int64) -> Void) {
        self.destination = destination
        self.report = report
    }

    func run(_ url: URL) throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.task = task
        task.resume()
        finished.wait()
        session.finishTasksAndInvalidate()
        if let failure { throw failure }
    }

    func cancel() {
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 404 {
                failure = FactoryImage.Failure.notPublished
            } else {
                failure = BTWError("The download failed (HTTP \(status)).")
            }
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, failure == nil { failure = error }
        finished.signal()
    }
}

/// Carries a background result back to the main thread.
final class ResultBox<T> {
    var value: Result<T, Error>?
}

/// A small modal window with a progress bar and Cancel, shown while work runs
/// on a background queue.
final class ProgressWindow: NSObject {
    var onCancel: (() -> Void)?
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var cancelled = false

    init(title: String) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false

        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = true

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [label, bar, cancel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 400),
        ])
        window.contentView = content
    }

    func update(_ text: String, fraction: Double? = nil) {
        label.stringValue = text
        if let fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    /// Shows the window modally while `work` runs on a background queue, and
    /// returns its result. Throws CancellationError if Cancel was pressed.
    func run<T>(_ work: @escaping () throws -> T) throws -> T {
        let result = ResultBox<T>()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try work() }
            DispatchQueue.main.async {
                result.value = outcome
                NSApplication.shared.stopModal()
            }
        }
        window.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.runModal(for: window)
        window.orderOut(nil)
        if cancelled { throw CancellationError() }
        guard let outcome = result.value else { throw BTWError("Setup was interrupted.") }
        return try outcome.get()
    }

    func close() {
        window.close()
    }

    @objc private func cancelPressed() {
        cancelled = true
        onCancel?()
    }
}
