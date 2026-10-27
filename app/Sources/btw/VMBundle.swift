import Foundation
import Virtualization

struct BTWError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// On-disk state for one VM: its disk, EFI variables and stable machine identity.
struct VMBundle {
    let url: URL

    init(name: String) throws {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            throw BTWError("invalid VM name: \(name)")
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        url = support.appendingPathComponent("btw/VMs/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var diskURL: URL { url.appendingPathComponent("disk.img") }
    var efiVariablesURL: URL { url.appendingPathComponent("efi-vars.fd") }
    var machineIdentifierURL: URL { url.appendingPathComponent("machine-id") }
    var consoleLogURL: URL { url.appendingPathComponent("console.log") }

    /// Creates a sparse raw disk image; APFS only allocates blocks the guest writes.
    func ensureDisk(sizeGiB: UInt64) throws {
        guard !FileManager.default.fileExists(atPath: diskURL.path) else { return }
        guard FileManager.default.createFile(atPath: diskURL.path, contents: nil) else {
            throw BTWError("could not create \(diskURL.path)")
        }
        let handle = try FileHandle(forWritingTo: diskURL)
        defer { try? handle.close() }
        try handle.truncate(atOffset: sizeGiB << 30)
    }

    /// The guest sees the same hardware identity on every boot, which keeps
    /// EFI boot entries and machine-specific state valid.
    func machineIdentifier() throws -> VZGenericMachineIdentifier {
        if let data = try? Data(contentsOf: machineIdentifierURL),
           let identifier = VZGenericMachineIdentifier(dataRepresentation: data) {
            return identifier
        }
        let identifier = VZGenericMachineIdentifier()
        try identifier.dataRepresentation.write(to: machineIdentifierURL)
        return identifier
    }

    func efiVariableStore() throws -> VZEFIVariableStore {
        if FileManager.default.fileExists(atPath: efiVariablesURL.path) {
            return VZEFIVariableStore(url: efiVariablesURL)
        }
        return try VZEFIVariableStore(creatingVariableStoreAt: efiVariablesURL)
    }
}
