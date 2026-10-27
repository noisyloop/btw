import Foundation
import Virtualization

struct VMOptions {
    enum Boot {
        /// UEFI firmware; boots the VM disk, or the installer ISO when the disk is empty.
        case efi(installer: URL?)
        /// Direct kernel boot, skipping firmware and bootloader.
        case linux(kernel: URL, initrd: URL?, cmdline: String)
    }

    var name = "default"
    var boot: Boot = .efi(installer: nil)
    var cpus = max(2, ProcessInfo.processInfo.processorCount / 2)
    var memoryGiB: UInt64 = 4
    var diskGiB: UInt64 = 32
    var headless = false
    var shares: [URL] = []
}

/// Tag the guest mounts host shares with: `mount -t virtiofs btw /mnt/btw`.
let sharedDirectoryTag = "btw"
/// Tag for Apple's Rosetta translator: `mount -t virtiofs rosetta /media/rosetta`.
let rosettaTag = "rosetta"

func makeConfiguration(
    options: VMOptions, bundle: VMBundle, serial: VZSerialPortAttachment
) throws -> VZVirtualMachineConfiguration {
    let config = VZVirtualMachineConfiguration()

    config.cpuCount = min(
        max(options.cpus, VZVirtualMachineConfiguration.minimumAllowedCPUCount),
        VZVirtualMachineConfiguration.maximumAllowedCPUCount)
    config.memorySize = min(
        max(options.memoryGiB << 30, VZVirtualMachineConfiguration.minimumAllowedMemorySize),
        VZVirtualMachineConfiguration.maximumAllowedMemorySize)

    let platform = VZGenericPlatformConfiguration()
    platform.machineIdentifier = try bundle.machineIdentifier()
    config.platform = platform

    var storage: [VZStorageDeviceConfiguration] = []
    let disk = try VZDiskImageStorageDeviceAttachment(
        url: bundle.diskURL, readOnly: false, cachingMode: .automatic, synchronizationMode: .full)
    storage.append(VZVirtioBlockDeviceConfiguration(attachment: disk))

    switch options.boot {
    case .efi(let installer):
        let loader = VZEFIBootLoader()
        loader.variableStore = try bundle.efiVariableStore()
        config.bootLoader = loader
        if let installer {
            // Presented as a USB stick so EFI falls through to it while the disk is empty.
            let iso = try VZDiskImageStorageDeviceAttachment(url: installer, readOnly: true)
            storage.append(VZUSBMassStorageDeviceConfiguration(attachment: iso))
        }
    case .linux(let kernel, let initrd, let cmdline):
        let loader = VZLinuxBootLoader(kernelURL: kernel)
        loader.initialRamdiskURL = initrd
        loader.commandLine = cmdline
        config.bootLoader = loader
    }
    config.storageDevices = storage

    let network = VZVirtioNetworkDeviceConfiguration()
    network.attachment = VZNATNetworkDeviceAttachment()
    config.networkDevices = [network]

    let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
    serialPort.attachment = serial
    config.serialPorts = [serialPort]

    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

    if !options.headless {
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1200)]
        config.graphicsDevices = [graphics]
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        let sound = VZVirtioSoundDeviceConfiguration()
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        sound.streams = [output]
        config.audioDevices = [sound]

        // Host <-> guest clipboard, picked up by spice-vdagent in the guest.
        let consolePort = VZVirtioConsolePortConfiguration()
        consolePort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
        let spice = VZSpiceAgentPortAttachment()
        spice.sharesClipboard = true
        consolePort.attachment = spice
        let consoleDevice = VZVirtioConsoleDeviceConfiguration()
        consoleDevice.ports[0] = consolePort
        config.consoleDevices = [consoleDevice]
    }

    var directoryShares: [VZDirectorySharingDeviceConfiguration] = []
    if !options.shares.isEmpty {
        var directories: [String: VZSharedDirectory] = [:]
        for url in options.shares {
            let name = url.lastPathComponent
            guard directories[name] == nil else { throw BTWError("two --share directories are named \(name)") }
            directories[name] = VZSharedDirectory(url: url, readOnly: false)
        }
        let device = VZVirtioFileSystemDeviceConfiguration(tag: sharedDirectoryTag)
        device.share = VZMultipleDirectoryShare(directories: directories)
        directoryShares.append(device)
    }
    if VZLinuxRosettaDirectoryShare.availability == .installed {
        let device = VZVirtioFileSystemDeviceConfiguration(tag: rosettaTag)
        device.share = try VZLinuxRosettaDirectoryShare()
        directoryShares.append(device)
    }
    config.directorySharingDevices = directoryShares

    return config
}
