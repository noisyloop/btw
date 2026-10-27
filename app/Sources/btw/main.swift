import Foundation

let usage = """
usage: btw run [options]

Boot options (pick one; with neither, boots the VM's existing disk via EFI):
  --iso PATH          attach an arm64 installer ISO and boot it via EFI
  --kernel PATH       boot an uncompressed arm64 Linux kernel directly
  --initrd PATH       initial ramdisk for --kernel
  --cmdline STRING    kernel command line for --kernel (default: "console=hvc0")

VM options:
  --name NAME         VM bundle name (default: "default")
  --cpus N            virtual CPUs (default: half the host's cores, min 2)
  --memory GiB        memory size (default: 4)
  --disk GiB          size of a newly created disk (default: 32; ignored if it exists)
  --from IMAGE        create the VM's disk as a clone of a raw image, such as
                      out/btw-factory.img (ignored if the disk exists)
  --share DIR         share a host directory (repeatable); mount in the guest with
                      `mount -t virtiofs btw /mnt/btw`
  --headless          no window; wire the serial console to this terminal
                      (press Ctrl-] to stop the VM)

VM bundles live in ~/Library/Application Support/btw/VMs/<name>/.
"""

func say(_ message: String) {
    // "\r\n" because stdin may be in raw mode while a headless VM is running.
    FileHandle.standardError.write("btw: \(message)\r\n".data(using: .utf8)!)
}

func fail(_ message: String) -> Never {
    Terminal.restore()
    say(message)
    exit(1)
}

func existingFile(_ path: String) -> URL {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: url.path) else { fail("no such file: \(path)") }
    return url
}

// Finder passes no arguments (older macOS adds -psn_*), so a double-clicked
// btw.app asks what to boot instead of printing usage.
var launchArguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
if launchArguments.isEmpty && Bundle.main.bundleURL.pathExtension == "app" {
    launchArguments = ["run"] + Launcher.chooseBoot()
}
var arguments = launchArguments.makeIterator()

switch arguments.next() {
case "run":
    break
case "-h", "--help", "help":
    print(usage)
    exit(0)
default:
    print(usage)
    exit(1)
}

func value(for flag: String) -> String {
    guard let value = arguments.next() else { fail("missing value for \(flag)") }
    return value
}

func number(for flag: String) -> Int {
    guard let n = Int(value(for: flag)), n > 0 else { fail("\(flag) expects a positive integer") }
    return n
}

var options = VMOptions()
var iso: URL?
var kernel: URL?
var initrd: URL?
var cmdline = "console=hvc0"
var template: URL?

while let arg = arguments.next() {
    switch arg {
    case "--iso": iso = existingFile(value(for: arg))
    case "--kernel": kernel = existingFile(value(for: arg))
    case "--initrd": initrd = existingFile(value(for: arg))
    case "--cmdline": cmdline = value(for: arg)
    case "--name": options.name = value(for: arg)
    case "--cpus": options.cpus = number(for: arg)
    case "--memory": options.memoryGiB = UInt64(number(for: arg))
    case "--disk": options.diskGiB = UInt64(number(for: arg))
    case "--from": template = existingFile(value(for: arg))
    case "--share": options.shares.append(existingFile(value(for: arg)))
    case "--headless": options.headless = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        fail("unknown option \(arg) (see btw --help)")
    }
}

if let kernel {
    if iso != nil { fail("--iso and --kernel are mutually exclusive") }
    options.boot = .linux(kernel: kernel, initrd: initrd, cmdline: cmdline)
} else {
    if initrd != nil { fail("--initrd requires --kernel") }
    options.boot = .efi(installer: iso)
}

do {
    let bundle = try VMBundle(name: options.name)
    try bundle.ensureDisk(sizeGiB: options.diskGiB, from: template)
    let console = try SerialConsole(headless: options.headless, logURL: bundle.consoleLogURL)
    let configuration = try makeConfiguration(options: options, bundle: bundle, serial: console.attachment)
    try configuration.validate()

    say("bundle: \(bundle.url.path)")
    if !options.headless { say("serial console log: \(bundle.consoleLogURL.path)") }

    let runner = VMRunner(configuration: configuration, options: options, console: console)
    runner.run()
} catch {
    fail("\(error.localizedDescription)")
}
