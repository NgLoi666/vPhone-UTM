//
// Copyright © 2023 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private let kUTMBundleExtension = "utm"
private let kScreenshotPeriodSeconds = 60.0
let kUTMBundleScreenshotFilename = "screenshot.png"
private let kUTMBundleViewFilename = "view.plist"

/// UTM virtual machine backend
protocol UTMVirtualMachine: AnyObject, Identifiable {
    associatedtype Capabilities: UTMVirtualMachineCapabilities
    associatedtype Configuration: UTMConfiguration
    
    /// Path where the .utm is stored
    var pathUrl: URL { get }
    
    /// True if the .utm is loaded outside of the default storage
    ///
    /// This indicates that we cannot access outside the container.
    var isShortcut: Bool { get }
    
    /// The VM is running in disposible mode
    ///
    /// This indicates that changes should not be saved.
    var isRunningAsDisposible: Bool { get }
    
    /// Set by caller to handle VM events
    var delegate: (any UTMVirtualMachineDelegate)? { get set }
    
    /// Set by caller to handle changes in `config` or `registryEntry`
    var onConfigurationChange: (() -> Void)? { get set }
    
    /// Set by caller to handle changes in `state` or `screenshot`
    var onStateChange: (() -> Void)?  { get set }
    
    /// Configuration for this VM
    var config: Configuration { get }
    
    /// Additional configuration on a short lived, per-host basis
    ///
    /// This includes display size, bookmarks to removable drives, etc.
    var registryEntry: UTMRegistryEntry { get }
    
    /// Current VM state
    var state: UTMVirtualMachineState { get }
    
    /// If non-null, is the most recent screenshot of the running VM
    var screenshot: UTMVirtualMachineScreenshot? { get }

    /// If non-null, `saveSnapshot` and `restoreSnapshot` will not work due to the reason specified
    var snapshotUnsupportedError: Error? { get }

    /// If true, this VM does not have any active display
    var isHeadless: Bool { get }

    static func isVirtualMachine(url: URL) -> Bool
    
    /// Get name of UTM virtual machine from a file
    /// - Parameter url: File URL
    /// - Returns: The name of the VM
    static func virtualMachineName(for url: URL) -> String
    
    /// Get the path of a UTM virtual machine from a name and parent directory
    /// - Parameters:
    ///   - name: VM name
    ///   - parentUrl: Base directory file URL
    /// - Returns: URL of virtual machine
    static func virtualMachinePath(for name: String, in parentUrl: URL) -> URL
    
    /// Returns supported capabilities for this backend
    static var capabilities: Capabilities { get }
    
    /// Instantiate a new virtual machine
    /// - Parameters:
    ///   - packageUrl: Package where the virtual machine resides
    ///   - configuration: New virtual machine configuration
    ///   - isShortcut: Indicate that this package cannot be moved
    init(packageUrl: URL, configuration: Configuration, isShortcut: Bool) throws
    
    /// Discard any changes to configuration by reloading from disk
    /// - Parameter packageUrl: URL to reload from, if nil then use the existing package URL
    func reload(from packageUrl: URL?) throws
    
    /// Save .utm bundle to disk
    ///
    /// This will create a configuration file and any auxiliary data files if needed.
    func save() async throws
    
    /// Called when we save the config
    func updateRegistryFromConfig() async throws
    
    /// Called whenever the registry entry changes
    func updateConfigFromRegistry()
    
    /// Called when we have a duplicate UUID
    /// - Parameters:
    ///   - uuid: New UUID
    ///   - name: Optionally change name as well
    ///   - entry: Optionally copy data from an entry
    func changeUuid(to uuid: UUID, name: String?, copyingEntry entry: UTMRegistryEntry?)
    
    /// Starts the VM
    /// - Parameter options: Options for startup
    func start(options: UTMVirtualMachineStartOptions) async throws
    
    /// Stops the VM
    /// - Parameter method: How to handle the stop request
    func stop(usingMethod method: UTMVirtualMachineStopMethod) async throws
    
    /// Restarts the VM
    func restart() async throws
    
    /// Pauses the VM
    func pause() async throws
    
    /// Resumes the VM
    func resume() async throws
    
    /// Saves the current VM state
    /// - Parameter name: Optional snaphot name (default if nil)
    func saveSnapshot(name: String?) async throws
    
    /// Deletes the saved VM state
    /// - Parameter name: Optional snaphot name (default if nil)
    func deleteSnapshot(name: String?) async throws
    
    /// Restore saved VM state
    /// - Parameter name: Optional snaphot name (default if nil)
    func restoreSnapshot(name: String?) async throws
    
    /// Request a screenshot of the primary graphics device
    /// - Returns: true if successful and the screenshot will be in `screenshot`
    @discardableResult func takeScreenshot() async -> Bool
    
    /// If screenshot is modified externally, this must be called
    func reloadScreenshotFromFile() throws
}

/// Supported capabilities for a UTM backend
protocol UTMVirtualMachineCapabilities {
    /// The backend supports killing the VM process.
    var supportsProcessKill: Bool { get }
    
    /// The backend supports saving/restoring VM state.
    var supportsSnapshots: Bool { get }
    
    /// The backend supports taking screenshots.
    var supportsScreenshots: Bool { get }
    
    /// The backend supports running without persisting changes.
    var supportsDisposibleMode: Bool { get }
    
    /// The backend supports booting into recoveryOS.
    var supportsRecoveryMode: Bool { get }
    
    /// The backend supports remote sessions.
    var supportsRemoteSession: Bool { get }
}

/// Delegate for UTMVirtualMachine events
protocol UTMVirtualMachineDelegate: AnyObject {
    /// Called when VM state changes
    ///
    /// Will always be called from the main thread.
    /// - Parameters:
    ///   - vm: Virtual machine
    ///   - state: New state
    func virtualMachine(_ vm: any UTMVirtualMachine, didTransitionToState state: UTMVirtualMachineState)
    
    /// Called when VM errors
    ///
    /// Will always be called from the main thread.
    /// - Parameters:
    ///   - vm: Virtual machine
    ///   - message: Localized error message when supported, English message otherwise
    func virtualMachine(_ vm: any UTMVirtualMachine, didErrorWithMessage message: String)
    
    /// Called when VM installation updates progress
    /// - Parameters:
    ///   - vm: Virtual machine
    ///   - progress: Number between 0.0 and 1.0 indiciating installation progress
    func virtualMachine(_ vm: any UTMVirtualMachine, didUpdateInstallationProgress progress: Double)
    
    /// Called when VM successfully completes installation
    /// - Parameters:
    ///   - vm: Virtual machine
    ///   - success: True if installation is successful
    func virtualMachine(_ vm: any UTMVirtualMachine, didCompleteInstallation success: Bool)
}

/// Virtual machine state
enum UTMVirtualMachineState: Int, Codable, CaseIterable, Sendable {
    case stopped
    case starting
    case started
    case pausing
    case paused
    case resuming
    case saving
    case restoring
    case stopping
}

/// Additional options for VM start
struct UTMVirtualMachineStartOptions: OptionSet, Codable {
    let rawValue: UInt
    
    /// Boot without persisting any changes.
    static let bootDisposibleMode = Self(rawValue: 1 << 0)
    /// Boot into recoveryOS (when supported).
    static let bootRecovery = Self(rawValue: 1 << 1)
    /// Start VDI session where a remote client will connect to.
    static let remoteSession = Self(rawValue: 1 << 2)
}

/// Method to stop the VM
enum UTMVirtualMachineStopMethod: Int, Codable, CaseIterable, Sendable {
    /// Sends a request to the guest to shut down gracefully.
    case request
    /// Sends a hardware power down signal.
    case force
    /// Terminate the VM process.
    case kill
}

// MARK: - Class functions

extension UTMVirtualMachine {
    private static var fileManager: FileManager {
        FileManager.default
    }
    
    static func isVirtualMachine(url: URL) -> Bool {
        return url.pathExtension == kUTMBundleExtension
    }
    
    static func virtualMachineName(for url: URL) -> String {
        (fileManager.displayName(atPath: url.path) as NSString).deletingPathExtension
    }
    
    static func virtualMachinePath(for name: String, in parentUrl: URL) -> URL {
        let illegalFileNameCharacters = CharacterSet(charactersIn: ",/:\\?%*|\"<>")
        let name = name.components(separatedBy: illegalFileNameCharacters).joined(separator: "-")
        return parentUrl.appendingPathComponent(name).appendingPathExtension(kUTMBundleExtension)
    }
    
    /// Instantiate a new VM from a new configuration
    /// - Parameters:
    ///   - configuration: New configuration
    ///   - destinationUrl: Directory to store VM
    init(newForConfiguration configuration: Self.Configuration, destinationUrl: URL) throws {
        let packageUrl = Self.virtualMachinePath(for: configuration.information.name, in: destinationUrl)
        try self.init(packageUrl: packageUrl, configuration: configuration, isShortcut: false)
    }
}

// MARK: - Snapshots

extension UTMVirtualMachine {
    func saveSnapshot(name: String?) async throws {
        throw UTMVirtualMachineError.notImplemented
    }
    
    func deleteSnapshot(name: String?) async throws {
        throw UTMVirtualMachineError.notImplemented
    }
    
    func restoreSnapshot(name: String?) async throws {
        throw UTMVirtualMachineError.notImplemented
    }
}

// MARK: - Screenshot

struct UTMVirtualMachineScreenshot {
    let image: PlatformImage
    let pngData: Data?

    init?(contentsOfURL url: URL) {
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        #elseif canImport(UIKit)
        guard let image = UIImage(contentsOfURL: url) else {
            return nil
        }
        #endif
        self.image = image
        self.pngData = Self.createData(from: image)
    }

    init(wrapping image: PlatformImage) {
        self.image = image
        self.pngData = Self.createData(from: image)
    }

    private static func createData(from image: PlatformImage) -> Data? {
        #if canImport(AppKit)
        guard let cgref = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let newrep = NSBitmapImageRep(cgImage: cgref)
        newrep.size = image.size
        return newrep.representation(using: .png, properties: [:])
        #elseif canImport(UIKit)
        return image.pngData()
        #endif
    }
}

extension UTMVirtualMachine {
    nonisolated var isScreenshotEnabled: Bool {
        !UserDefaults.standard.bool(forKey: "NoScreenshot")
    }

    nonisolated private var isScreenshotSaveEnabled: Bool {
        isScreenshotEnabled && !UserDefaults.standard.bool(forKey: "NoSaveScreenshot")
    }
    
    private var screenshotUrl: URL {
        pathUrl.appendingPathComponent(kUTMBundleScreenshotFilename)
    }
    
    func startScreenshotTimer() -> Timer {
        // delete existing screenshot if required
        if !isScreenshotSaveEnabled && !isRunningAsDisposible {
            try? deleteScreenshot()
        }
        let timer = Timer(timeInterval: kScreenshotPeriodSeconds, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            guard self.isScreenshotEnabled else {
                return
            }
            if self.state == .started {
                Task { @MainActor in
                    await self.takeScreenshot()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        return timer
    }
    
    func loadScreenshot() -> UTMVirtualMachineScreenshot? {
        UTMVirtualMachineScreenshot(contentsOfURL: screenshotUrl)
    }
    
    func saveScreenshot() throws {
        guard isScreenshotSaveEnabled && !isRunningAsDisposible else {
            return
        }
        guard let screenshot = screenshot else {
            return
        }
        try screenshot.pngData?.write(to: screenshotUrl)
    }
    
    func deleteScreenshot() throws {
        try Self.fileManager.removeItem(at: screenshotUrl)
    }
    
    @MainActor func takeScreenshot() async -> Bool {
        return false
    }
}

// MARK: - Save UTM

@MainActor extension UTMVirtualMachine {
    func save() async throws {
        let existingPath = pathUrl
        let newPath = Self.virtualMachinePath(for: config.information.name, in: existingPath.deletingLastPathComponent())
        try await config.save(to: existingPath)
        try await updateRegistryFromConfig()
        let hasRenamed: Bool
        if !isShortcut && existingPath.path != newPath.path {
            try await Task.detached {
                try Self.fileManager.moveItem(at: existingPath, to: newPath)
            }.value
            hasRenamed = true
        } else {
            hasRenamed = false
        }
        // reload the config if we renamed in order to point all the URLs to the right path
        if hasRenamed {
            try reload(from: newPath)
            try await updateRegistryBasics() // update bookmark
        }
        // update last modified date
        try? updateLastModified()
    }
    
    /// Set the package's last modified time
    /// - Parameter date: Last modified date
    nonisolated func updateLastModified(to date: Date = Date()) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: pathUrl.path)
    }
}

// MARK: - Registry functions

@MainActor extension UTMVirtualMachine {
    nonisolated func loadRegistry() -> UTMRegistryEntry {
        let registryEntry = UTMRegistry.shared.entry(for: self)
        // migrate legacy view state
        let viewStateUrl = pathUrl.appendingPathComponent(kUTMBundleViewFilename)
        registryEntry.migrateUnsafe(viewStateURL: viewStateUrl)
        return registryEntry
    }
    
    /// Default implementation
    func updateRegistryFromConfig() async throws {
        try await updateRegistryBasics()
    }
    
    /// Called when we save the config
    func updateRegistryBasics() async throws {
        if registryEntry.uuid != id {
            changeUuid(to: id, name: nil, copyingEntry: registryEntry)
        }
        registryEntry.name = name
        let oldPath = registryEntry.package.path
        let oldRemoteBookmark = registryEntry.package.remoteBookmark
        registryEntry.package = try UTMRegistryEntry.File(url: pathUrl)
        if registryEntry.package.path == oldPath {
            registryEntry.package.remoteBookmark = oldRemoteBookmark
        }
    }
}

// MARK: - Identity

extension UTMVirtualMachine {
    var id: UUID {
        config.information.uuid
    }
    
    var name: String {
        config.information.name
    }
}

// MARK: - vPhone backend

#if os(macOS)
/// Live status for the first-install flow shown by the vPhone wizard.
///
/// Firmware archives are owned by vphone-cli in `~/.vphone/ipsws`. Its aria2
/// downloader retains partial files and resumes them on the next run, so the
/// wizard can safely discard only an incomplete VM bundle when retrying.
@MainActor
final class VPhoneProvisioningController: ObservableObject {
    @Published private(set) var title = "Preparing setup"
    @Published private(set) var detail = "Starting vphone-cli…"
    @Published private(set) var progress: Double?
    @Published private(set) var downloadedSize: String?
    @Published private(set) var totalSize: String?
    @Published private(set) var downloadSpeed: String?
    @Published private(set) var timeRemaining: String?
    @Published private(set) var isRunning = false
    @Published private(set) var canRetry = false
    @Published private(set) var canRestartDownload = false
    @Published private(set) var didFinish = false
    @Published private(set) var logs = ""

    var hasLogs: Bool { !logs.isEmpty }

    private(set) var isCancellationRequested = false
    private(set) var ownsIncompleteBundle = false
    private var restartDownloadRequested = false
    private var process: Process?
    private var downloadMonitor: Timer?
    private var monitoredDownload: URL?
    private var lastDownloadSample: (size: Int64, date: Date)?
    private var attemptedAMFIRecovery = false

    func begin(retrying: Bool) {
        stopMonitoringDownload()
        isCancellationRequested = false
        isRunning = true
        canRetry = false
        canRestartDownload = false
        didFinish = false
        if !retrying {
            logs = ""
            attemptedAMFIRecovery = false
        }
        title = retrying ? "Continuing setup" : "Preparing setup"
        detail = retrying ? "Using the downloaded firmware cache…" : "Starting vphone-cli…"
        if !retrying {
            progress = nil
            downloadedSize = nil
            totalSize = nil
            downloadSpeed = nil
            timeRemaining = nil
        }
    }

    func cancel() {
        guard isRunning else { return }
        isCancellationRequested = true
        restartDownloadRequested = false
        title = "Pausing setup"
        detail = "Keeping downloaded firmware so it can continue later…"
        process?.terminate()
    }

    func restartDownload() {
        guard isRunning, canRestartDownload, monitoredDownload != nil else { return }
        isCancellationRequested = true
        restartDownloadRequested = true
        canRestartDownload = false
        title = "Restarting firmware download"
        detail = "Removing only the incomplete IPSW and downloading it again…"
        process?.terminate()
    }

    /// Runs once after macOS terminates vphone-cli for AMFI validation. The
    /// actual authorization is presented by macOS; the app never receives or
    /// stores the administrator password.
    func beginAMFIRecovery() -> Bool {
        guard !attemptedAMFIRecovery else { return false }
        attemptedAMFIRecovery = true
        stopMonitoringDownload()
        isRunning = true
        canRetry = false
        canRestartDownload = false
        title = "Enabling vphone-cli"
        detail = "macOS is requesting administrator permission…"
        appendLog("\n[amfidont] Requesting macOS administrator permission.\n")
        return true
    }

    func resetAMFIRecoveryForManualRetry() {
        attemptedAMFIRecovery = false
    }

    fileprivate func willCreateBundle() {
        // This is set only after a new name has been verified as unused. It keeps
        // a retry from ever removing a pre-existing, user-created VM.
        ownsIncompleteBundle = true
    }

    fileprivate func attach(process: Process) {
        self.process = process
    }

    fileprivate func detach(process: Process) {
        guard self.process === process else { return }
        self.process = nil
    }

    fileprivate func receive(_ output: String) {
        appendLog(output)
        let lines = output
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)

        for line in lines where !line.isEmpty {
            updateStage(for: line)
        }
        // aria2 refreshes a single carriage-return line. Parse the complete
        // chunk too, so a progress update is not lost before its next newline.
        updateDownloadStats(for: output)
    }

    @discardableResult
    func paused() -> Bool {
        let shouldRestartDownload = restartDownloadRequested
        restartDownloadRequested = false
        canRestartDownload = false
        let partialDownload = monitoredDownload
        stopMonitoringDownload()
        isRunning = false
        if shouldRestartDownload {
            guard let partialDownload else {
                title = "Setup paused"
                detail = "The partial IPSW could not be identified. Continue to resume it."
                canRetry = true
                return false
            }
            do {
                if FileManager.default.fileExists(atPath: partialDownload.path) {
                    try FileManager.default.removeItem(at: partialDownload)
                }
                title = "Restarting firmware download"
                detail = "The partial IPSW was removed. Starting a new download…"
                progress = nil
                downloadedSize = nil
                totalSize = nil
                downloadSpeed = nil
                timeRemaining = nil
                return true
            } catch {
                title = "Setup paused"
                detail = "Could not remove the partial IPSW. Continue will resume it."
                canRetry = true
                return false
            }
        }
        canRetry = true
        title = "Setup paused"
        detail = "The firmware cache is preserved. Continue to resume the download."
        downloadSpeed = nil
        timeRemaining = nil
        return false
    }

    func failed(with error: Error) {
        stopMonitoringDownload()
        isRunning = false
        canRetry = ownsIncompleteBundle
        canRestartDownload = false
        title = "Setup needs attention"
        detail = error.localizedDescription
        appendLog("\n[setup] \(error.localizedDescription)\n")
        downloadSpeed = nil
        timeRemaining = nil
    }

    func finished() {
        stopMonitoringDownload()
        isRunning = false
        canRetry = false
        canRestartDownload = false
        didFinish = true
        title = "Virtual iPhone is ready"
        detail = "Firmware is installed and the iPhone was added to your library."
        progress = 1
        downloadSpeed = nil
        timeRemaining = nil
    }

    private func updateStage(for line: String) {
        switch line {
        case let line where line.contains("=== fw prepare ==="):
            title = "Downloading firmware"
            detail = "Getting the iPhone and CloudOS firmware from Apple…"
        case let line where line.contains("==> Downloading "):
            title = "Downloading firmware"
            detail = line.replacingOccurrences(of: "==> ", with: "")
            progress = 0
            downloadedSize = nil
            totalSize = nil
            downloadSpeed = nil
            timeRemaining = nil
            monitorDownload(named: firmwareFilename(in: line))
        case let line where line.contains("Found existing") && line.contains("resuming"):
            title = "Continuing firmware download"
            detail = "A partially downloaded IPSW was found; resuming it now."
            canRestartDownload = true
            monitorDownload(named: firmwareFilename(in: line))
        case let line where line.contains("==> Extracting") || line.contains("Importing cloudOS") || line.contains("Generating hybrid"):
            stopMonitoringDownload()
            title = "Preparing firmware"
            detail = line.replacingOccurrences(of: "==> ", with: "")
            progress = nil
            downloadSpeed = nil
            timeRemaining = nil
        case let line where line.contains("=== fw patch ==="):
            title = "Patching firmware"
            detail = "Preparing the selected virtual iPhone profile…"
            progress = nil
        case let line where line.contains("=== Restore phase ==="):
            title = "Installing iOS"
            detail = "Restoring firmware to the virtual iPhone…"
            progress = nil
        case let line where line.contains("=== CFW install"):
            title = "Finishing setup"
            detail = "macOS may ask for administrator approval."
            progress = nil
        case let line where line.contains("host-mode CFW install") || line.contains("files placed on host mounts"):
            title = "Finishing setup"
            detail = "Installing custom firmware on the virtual iPhone — this can take several minutes…"
            progress = nil
        case let line where line.contains("=== First boot ===") || line.contains("=== Boot analysis ==="):
            title = "Starting virtual iPhone"
            detail = "Verifying the first boot…"
            progress = nil
        default:
            break
        }
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        let maximumLength = 128_000
        if logs.count > maximumLength {
            logs = String(logs.suffix(maximumLength))
        }
    }

    private func updateDownloadStats(for line: String) {
        let pattern = #"([0-9]+(?:\.[0-9]+)?\s*[KMGT]?i?B)\s*/\s*([0-9]+(?:\.[0-9]+)?\s*[KMGT]?i?B)\s*\(\s*([0-9]{1,3})%\s*\).*?\bDL:\s*([^\s\]]+)(?:.*?\bETA:\s*([^\s\]]+))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.matches(in: line, range: NSRange(line.startIndex..., in: line)).last,
              match.numberOfRanges == 6,
              let percentRange = Range(match.range(at: 3), in: line),
              let percent = Double(line[percentRange])
        else { return }

        let value = { (index: Int) -> String? in
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return String(line[range])
        }
        progress = min(max(percent / 100, 0), 1)
        downloadedSize = value(1)
        totalSize = value(2)
        downloadSpeed = value(4).map { "\($0)/s" }
        timeRemaining = value(5).map { "\($0) remaining" }
    }

    private func firmwareFilename(in line: String) -> String? {
        let prefixes = ["==> Downloading ", "==> Found existing "]
        let filename = prefixes
            .first(where: { line.contains($0) })
            .map { line.replacingOccurrences(of: $0, with: "") }
            ?? line
        let candidate = filename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)
        guard let candidate, candidate.hasSuffix(".ipsw") else { return nil }
        return candidate
    }

    private func monitorDownload(named filename: String?) {
        stopMonitoringDownload()
        guard let filename else { return }
        monitoredDownload = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vphone/ipsws", isDirectory: true)
            .appendingPathComponent(filename)
        sampleDownload()
        downloadMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleDownload()
            }
        }
    }

    private func sampleDownload() {
        guard let monitoredDownload,
              let attributes = try? FileManager.default.attributesOfItem(atPath: monitoredDownload.path),
              let fileSize = attributes[.size] as? NSNumber
        else { return }

        let size = fileSize.int64Value
        let now = Date()
        downloadedSize = Self.formattedByteCount(size)
        if let previous = lastDownloadSample {
            let elapsed = now.timeIntervalSince(previous.date)
            let delta = max(0, size - previous.size)
            if elapsed > 0, delta > 0 {
                downloadSpeed = "\(Self.formattedByteCount(Int64(Double(delta) / elapsed)))/s"
            }
        }
        lastDownloadSample = (size, now)
    }

    private func stopMonitoringDownload() {
        downloadMonitor?.invalidate()
        downloadMonitor = nil
        monitoredDownload = nil
        lastDownloadSample = nil
    }

    private static func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// A UTM-compatible adapter for vphone-cli's native Apple Virtualization bundles.
/// The iPhone display remains owned by vphone-cli; this app owns the UTM-style
/// library, settings and lifecycle controls.
@MainActor
final class VPhoneVirtualMachine: UTMVirtualMachine {
    struct Capabilities: UTMVirtualMachineCapabilities {
        let supportsProcessKill = true
        let supportsSnapshots = false
        let supportsScreenshots = false
        let supportsDisposibleMode = false
        let supportsRecoveryMode = false
        let supportsRemoteSession = false
    }

    static let capabilities = Capabilities()

    static var libraryRoot: URL {
        if let override = ProcessInfo.processInfo.environment["VPHONE_LIBRARY_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".vphone/VMs", isDirectory: true)
    }

    private(set) var pathUrl: URL
    private(set) var isShortcut = false
    private(set) var isRunningAsDisposible = false
    weak var delegate: (any UTMVirtualMachineDelegate)?
    var onConfigurationChange: (() -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var config: VPhoneConfiguration {
        willSet { onConfigurationChange?() }
    }
    private(set) var registryEntry: UTMRegistryEntry {
        willSet { onConfigurationChange?() }
    }
    private(set) var state: UTMVirtualMachineState = .stopped {
        willSet { onStateChange?() }
        didSet { delegate?.virtualMachine(self, didTransitionToState: state) }
    }
    private(set) var screenshot: UTMVirtualMachineScreenshot?
    let snapshotUnsupportedError: Error? = UTMVirtualMachineError.notImplemented
    let isHeadless = false

    private var launchProcess: Process?

    static func isVirtualMachine(url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("config.plist").path)
    }

    static func virtualMachineName(for url: URL) -> String {
        url.lastPathComponent
    }

    static func virtualMachinePath(for name: String, in parentUrl: URL) -> URL {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safeName = name.components(separatedBy: illegal).joined(separator: "-")
        return libraryRoot.appendingPathComponent(safeName, isDirectory: true)
    }

    init(packageUrl: URL, configuration: VPhoneConfiguration, isShortcut: Bool = false) throws {
        self.pathUrl = packageUrl
        self.config = configuration
        self.isShortcut = isShortcut
        self.registryEntry = UTMRegistryEntry.empty
        if !FileManager.default.fileExists(atPath: packageUrl.appendingPathComponent(VPhoneConfiguration.metadataFilename).path) {
            try? configuration.saveMetadata(to: packageUrl)
        }
        self.registryEntry = loadRegistry()
    }

    func reload(from packageUrl: URL?) throws {
        let newPath = packageUrl ?? pathUrl
        if let metadata = try? VPhoneConfiguration.loadMetadata(from: newPath) {
            config = metadata
        } else {
            config = VPhoneConfiguration(name: newPath.lastPathComponent)
            try? config.saveMetadata(to: newPath)
        }
        pathUrl = newPath
        updateConfigFromRegistry()
    }

    func save() async throws {
        let oldName = pathUrl.lastPathComponent
        let newName = config.information.name
        let fileManager = FileManager.default
        if config.replaceIncompleteBundleOnSave && fileManager.fileExists(atPath: pathUrl.path) {
            // The retry button is only enabled for a bundle created by this setup
            // controller. IPSWs live outside this bundle and are deliberately kept
            // so aria2 can continue their partial downloads.
            try fileManager.removeItem(at: pathUrl)
        }
        if fileManager.fileExists(atPath: pathUrl.path) {
            if oldName != newName {
                try await runCLI(["vm", "rename", oldName, newName])
                pathUrl = Self.virtualMachinePath(for: newName, in: Self.libraryRoot)
            }
            try await runCLI(["vm", "config", newName,
                              "--cpu", String(config.cpuCount),
                              "--memory", String(config.memorySizeMib),
                              "--network", config.networkMode])
        } else {
            var command = ["vm", "create", newName,
                           "-V", config.variant,
                           "--disk-size", String(config.diskSizeGib),
                           "--root-popup", "-v"]
            if let iphoneSource = config.iphoneSource, let cloudOSSource = config.cloudOSSource {
                command += ["--iphone-source", Self.sourceArgument(for: iphoneSource),
                            "--cloudos-source", Self.sourceArgument(for: cloudOSSource)]
            }
            if config.enableFrida { command += ["--frida"] }
            if config.forceDSCMaxSlide { command += ["--force-dsc-maxslide"] }
            if config.keepArtifacts { command += ["--keep-artifacts"] }
            if config.variant == "exp" {
                let spoofBuild = config.spoofBuild.trimmingCharacters(in: .whitespaces)
                if !spoofBuild.isEmpty { command += ["--spoof-build", spoofBuild] }
            }
            config.provisioningController?.willCreateBundle()
            try await runCLI(command, controller: config.provisioningController)
            try await runCLI(["vm", "config", newName,
                              "--cpu", String(config.cpuCount),
                              "--memory", String(config.memorySizeMib),
                              "--network", config.networkMode])
        }
        pathUrl = Self.virtualMachinePath(for: newName, in: Self.libraryRoot)
        try config.saveMetadata(to: pathUrl)
        try await updateRegistryFromConfig()
    }

    func updateRegistryFromConfig() async throws {
        try await updateRegistryBasics()
    }

    func updateConfigFromRegistry() {
        if registryEntry.name != config.information.name {
            registryEntry.name = config.information.name
        }
    }

    func changeUuid(to uuid: UUID, name: String? = nil, copyingEntry entry: UTMRegistryEntry?) {
        config.information.uuid = uuid
        if let name { config.information.name = name }
        registryEntry = UTMRegistry.shared.entry(for: self)
        if let entry { registryEntry.update(copying: entry) }
    }

    func start(options: UTMVirtualMachineStartOptions = []) async throws {
        guard state == .stopped else { return }
        guard FileManager.default.fileExists(atPath: pathUrl.path) else {
            throw VPhoneVirtualMachineError.bundleMissing
        }
        var launchCommand = ["vm", "launch", config.information.name]
        if !config.enableHapticFeedback { launchCommand.append("--no-haptics") }
        let process = Process()
        process.executableURL = try Self.executableURL()
        process.arguments = Self.arguments(launchCommand)
        // Captured (not discarded) so a "Disk image not found" failure — the
        // disk got moved via `vm relocate-disk`, e.g. onto external storage,
        // and its drive isn't mounted or the file moved again since — can be
        // told apart from any other launch failure and offer a real fix
        // instead of just a dead-end error message.
        let outputPipe = Pipe()
        var capturedOutput = Data()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            capturedOutput.append(data)
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        state = .starting
        do {
            try process.run()
        } catch {
            state = .stopped
            throw error
        }
        launchProcess = process
        state = .started
        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.launchProcess === process else { return }
                self.launchProcess = nil
                self.state = .stopped
                guard process.terminationStatus != 0 else { return }
                let output = String(data: capturedOutput, encoding: .utf8) ?? ""
                if let missingDiskPath = Self.diskNotFoundPath(in: output) {
                    self.offerDiskRelocationRecovery(missingDiskPath: missingDiskPath, options: options)
                } else {
                    self.delegate?.virtualMachine(self, didErrorWithMessage: VPhoneVirtualMachineError.commandFailed(process.terminationStatus).localizedDescription)
                }
            }
        }
    }

    /// vphone-cli prints exactly `Disk image not found: <path>` (see
    /// `VPhoneError.diskNotFound` in vphone-cli-modded) when `vm launch`'s own
    /// pre-flight file-existence check fails.
    private static func diskNotFoundPath(in output: String) -> String? {
        let marker = "Disk image not found: "
        guard let range = output.range(of: marker) else { return nil }
        let rest = output[range.upperBound...]
        return rest.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
    }

    /// Offers to repair a stale disk reference (drive unplugged, file moved
    /// by hand after `vm relocate-disk`) with a native alert rather than just
    /// reporting the launch failure — "Try Again" re-attempts the same path
    /// (covers "I just remounted the drive"), "Locate…" lets the user point
    /// at the disk's current location and repairs the manifest before retrying.
    @MainActor
    private func offerDiskRelocationRecovery(missingDiskPath: String, options: UTMVirtualMachineStartOptions) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Find the Virtual iPhone's Disk"
        alert.informativeText = "Expected it at:\n\(missingDiskPath)\n\nIf its drive isn't connected, connect it and try again. If the file was moved, locate its new location."
        alert.addButton(withTitle: "Locate…")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Locate…
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select the disk image (or the folder it's in) at its new location."
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            Task { @MainActor in
                do {
                    try await Self.relocateDisk(name: config.information.name, to: picked)
                    try await start(options: options)
                } catch {
                    delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
                }
            }
        case .alertSecondButtonReturn: // Try Again
            Task { @MainActor in
                do {
                    try await start(options: options)
                } catch {
                    delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
                }
            }
        default: // Cancel
            break
        }
    }

    static func relocateDisk(name: String, to destination: URL) async throws {
        let executable = try executableURL()
        let args = arguments(["vm", "relocate-disk", name, "--to", destination.path])
        _ = try await runCapturing(executable: executable, arguments: args)
    }

    func stop(usingMethod method: UTMVirtualMachineStopMethod = .request) async throws {
        guard state != .stopped else { return }
        state = .stopping
        do {
            try await runCLI(["vm", "stop", config.information.name])
        } catch {
            state = .started
            throw error
        }
        if launchProcess?.isRunning == true {
            launchProcess?.terminate()
        }
        launchProcess = nil
        state = .stopped
    }

    func restart() async throws {
        try await stop(usingMethod: .request)
        try await start(options: [])
    }

    func clone(to newName: String) async throws {
        try await runCLI(["vm", "clone", config.information.name, newName])
        let destination = Self.virtualMachinePath(for: newName, in: Self.libraryRoot)
        let copiedData = try PropertyListEncoder().encode(config)
        let copiedConfig = try PropertyListDecoder().decode(VPhoneConfiguration.self, from: copiedData)
        copiedConfig.information.name = newName
        copiedConfig.information.uuid = UUID()
        try copiedConfig.saveMetadata(to: destination)
    }

    func deleteFromLibrary() async throws {
        if state != .stopped {
            try await stop(usingMethod: .force)
        }
        try await runCLI(["vm", "delete", config.information.name, "--force"])
    }

    func pause() async throws { throw UTMVirtualMachineError.notImplemented }
    func resume() async throws { throw UTMVirtualMachineError.notImplemented }
    func takeScreenshot() async -> Bool { false }
    func reloadScreenshotFromFile() throws { }

    private static func executableURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [environment["VPHONE_CLI_PATH"], "/opt/homebrew/bin/vphone-cli", "/usr/local/bin/vphone-cli"]
            .compactMap { $0 }
            .map { URL(fileURLWithPath: $0) }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw VPhoneVirtualMachineError.cliNotFound
        }
        return executable
    }

    /// Enables the path-scoped AMFI helper shipped with vphone-cli. `osascript`
    /// asks macOS to authenticate the user, so no password is ever handled by
    /// vPhone itself.
    static func enableAMFIPermission(using controller: VPhoneProvisioningController) async throws {
        let executable = try executableURL()
        controller.receive("[amfidont] Starting the bundled permission helper…\n")
        let output = try await VPhoneAMFIWorkaround.enable(for: executable)
        if !output.isEmpty {
            controller.receive("[amfidont] \(output)\n")
        }
        controller.receive("[amfidont] Permission helper finished; retrying vphone-cli.\n")
    }

    /// Read-only snapshot of `vphone-cli vm info <name> --json` — versions and
    /// identity recorded at restore time, so they're readable without booting.
    struct FirmwareInfo: Decodable {
        struct OSVersion: Decodable { let version: String; let build: String }
        struct RestoreInfo: Decodable {
            let ios: OSVersion
            let cloudOS: OSVersion
            let variant: String?
            let device: String?
        }
        let restoreInfo: RestoreInfo?
        let udid: String?
    }

    static func firmwareInfo(name: String) async throws -> FirmwareInfo {
        let executable = try executableURL()
        let output = try await runCapturing(executable: executable, arguments: arguments(["vm", "info", name, "--json"]))
        return try JSONDecoder().decode(FirmwareInfo.self, from: Data(output.utf8))
    }

    private static func runCapturing(executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { finishedProcess in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    let errorText = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !errorText.isEmpty {
                        continuation.resume(throwing: VPhoneVirtualMachineError.commandFailedWithMessage(errorText))
                    } else {
                        continuation.resume(throwing: VPhoneVirtualMachineError.commandFailed(finishedProcess.terminationStatus))
                    }
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Proactively ensures vphone-cli is allowlisted through AMFI as soon as
    /// vPhone launches, instead of only reacting after some CLI invocation
    /// gets killed (exit 9/137) mid-task. `vphone-amfidont` itself checks
    /// whether amfidont is already running and already covers this app's
    /// path, and exits immediately with no prompt if so — so this is a no-op
    /// on every launch except the first one after a host reboot (amfidont's
    /// daemon doesn't survive that without its own supervision).
    static func ensureAMFIPermissionAtLaunch() async {
        guard let executable = try? executableURL() else { return }
        do {
            let output = try await VPhoneAMFIWorkaround.enable(for: executable)
            if !output.isEmpty { NSLog("[amfidont] %@", output) }
        } catch {
            NSLog("[amfidont] Launch-time check failed: %@", error.localizedDescription)
        }
    }

    private static func arguments(_ command: [String]) -> [String] {
        command + ["--library-root", libraryRoot.path]
    }

    private static func sourceArgument(for source: URL) -> String {
        source.isFileURL ? source.path : source.absoluteString
    }

    /// Runs `command`, and — unless `allowAMFIRecovery` is false — transparently
    /// requests the amfidont permission and retries once if macOS's AMFI killed
    /// vphone-cli (exit 9/137) before it could even start. Without this, any
    /// command other than `vm create` (delete, stop, rename, clone, config) hit
    /// a dead-end "macOS stopped vphone-cli…" alert with no recovery path, since
    /// only the create wizard drove `beginAMFIRecovery`/`enableAMFIPermission`.
    /// `vm create` opts out (`allowAMFIRecovery: false`) because VMWizardView
    /// already owns AMFI recovery for that command, tied into its
    /// pause/retry/`ownsIncompleteBundle` state machine — retrying here too
    /// would just prompt for the administrator password twice on failure.
    private func runCLI(
        _ command: [String], controller: VPhoneProvisioningController? = nil, allowAMFIRecovery: Bool = true
    ) async throws {
        let executable = try Self.executableURL()
        let arguments = Self.arguments(command)
        let status = try await Self.spawnCLI(executable: executable, arguments: arguments, controller: controller)
        if status == 0 { return }

        let error = VPhoneVirtualMachineError.commandFailed(status)
        guard allowAMFIRecovery, error.needsAMFIPermission else { throw error }

        await controller?.receive("\n[amfidont] macOS blocked vphone-cli; requesting administrator permission…\n")
        let output = try await VPhoneAMFIWorkaround.enable(for: executable)
        if !output.isEmpty { await controller?.receive("[amfidont] \(output)\n") }

        let retryStatus = try await Self.spawnCLI(executable: executable, arguments: arguments, controller: controller)
        guard retryStatus == 0 else { throw VPhoneVirtualMachineError.commandFailed(retryStatus) }
    }

    private static func spawnCLI(
        executable: URL, arguments: [String], controller: VPhoneProvisioningController?
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            let readOutput: (FileHandle) -> Void = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in controller?.receive(text) }
            }
            output.fileHandleForReading.readabilityHandler = readOutput
            errors.fileHandleForReading.readabilityHandler = readOutput
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { finishedProcess in
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in controller?.detach(process: finishedProcess) }
                continuation.resume(returning: finishedProcess.terminationStatus)
            }
            do {
                try process.run()
                controller?.attach(process: process)
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Invokes vphone-cli's own `vphone-amfidont` helper through the standard
/// macOS authorization dialog. The helper allowlists only its enclosing
/// vphone-cli.app bundle rather than enabling a global bypass.
private enum VPhoneAMFIWorkaround {
    static func enable(for cliExecutable: URL) async throws -> String {
        let resolvedExecutable = cliExecutable.resolvingSymlinksInPath()
        let app = resolvedExecutable
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // vphone-cli.app
        let helper = app
            .appendingPathComponent("Contents/Resources/vphone-amfidont")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw VPhoneAMFIWorkaroundError.helperMissing
        }

        guard let amfidont = amfidontURL() else {
            throw VPhoneAMFIWorkaroundError.amfidontMissing
        }

        // The bundled helper uses `command -v amfidont`; GUI applications do
        // not inherit the user's shell PATH, so provide the discovered path.
        let searchPath = [
            amfidont.deletingLastPathComponent().path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
        ].joined(separator: ":")
        let command = "PATH=\(shellQuote(searchPath)) \(shellQuote(helper.path))"
        let appleScript = "do shell script \(appleScriptString(command)) with administrator privileges"
        return try await runAppleScript(appleScript)
    }

    private static func amfidontURL() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let userPythonDirectory = home.appendingPathComponent("Library/Python", isDirectory: true)
        let pythonBins = (try? fileManager.contentsOfDirectory(at: userPythonDirectory,
                                                                includingPropertiesForKeys: [.isDirectoryKey],
                                                                options: [.skipsHiddenFiles])) ?? []
        let candidates = pythonBins.map { $0.appendingPathComponent("bin/amfidont") }
            + [URL(fileURLWithPath: "/opt/homebrew/bin/amfidont"),
               URL(fileURLWithPath: "/usr/local/bin/amfidont")]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private static func runAppleScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { finishedProcess in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: VPhoneAMFIWorkaroundError.authorizationFailed(text))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

private enum VPhoneAMFIWorkaroundError: LocalizedError {
    case helperMissing
    case amfidontMissing
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "The vphone-amfidont helper is missing from vphone-cli. Reinstall vphone-cli and try again."
        case .amfidontMissing:
            return "amfidont is not installed. Install it with ‘xcrun python3 -m pip install -U amfidont’, then try again."
        case .authorizationFailed(let output):
            if output.localizedCaseInsensitiveContains("User canceled") || output.contains("-128") {
                return "Administrator permission was not granted."
            }
            return output.isEmpty ? "macOS could not enable vphone-cli." : output
        }
    }
}

enum VPhoneVirtualMachineError: LocalizedError {
    case cliNotFound
    case bundleMissing
    case commandFailed(Int32)
    /// Like `commandFailed`, but vphone-cli printed something to stderr —
    /// surface that instead of just the exit code (e.g. `vm relocate-disk`'s
    /// own validation messages).
    case commandFailedWithMessage(String)

    var needsAMFIPermission: Bool {
        if case let .commandFailed(status) = self {
            return status == 9 || status == 137
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return NSLocalizedString("vphone-cli was not found. Install it with Homebrew, then reopen vPhone.", comment: "VPhoneVirtualMachine")
        case .bundleMissing:
            return NSLocalizedString("The virtual iPhone bundle could not be found.", comment: "VPhoneVirtualMachine")
        case .commandFailed(let status):
            if status == 9 || status == 137 {
                return NSLocalizedString("macOS stopped vphone-cli before setup began, even after vPhone requested permission. Open Show Logs, then choose Continue to try again.", comment: "VPhoneVirtualMachine")
            }
            return String.localizedStringWithFormat(NSLocalizedString("vphone-cli exited with code %d.", comment: "VPhoneVirtualMachine"), status)
        case .commandFailedWithMessage(let message):
            return message
        }
    }
}
#endif

// MARK: - Errors

enum UTMVirtualMachineError: Error {
    case notImplemented
}

extension UTMVirtualMachineError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return NSLocalizedString("Not implemented.", comment: "UTMVirtualMachine")
        }
    }
}

// MARK: - Non-asynchronous version (to be removed)

extension UTMVirtualMachine {
    func requestVmStart(options: UTMVirtualMachineStartOptions = []) {
        Task {
            do {
                try await start(options: options)
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestVmStop(force: Bool = false) {
        Task {
            do {
                try await stop(usingMethod: force ? .kill : .force)
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestVmReset() {
        Task {
            do {
                try await restart()
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestVmPause(save: Bool = false) {
        Task {
            do {
                try await pause()
                if save {
                    try await saveSnapshot(name: nil)
                }
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestVmSaveState() {
        Task {
            do {
                try await saveSnapshot(name: nil)
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestVmDeleteState() {
        Task {
            do {
                try await deleteSnapshot(name: nil)
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestVmResume() {
        Task {
            do {
                try await resume()
                try? await deleteSnapshot(name: nil)
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
    
    func requestGuestPowerDown() {
        Task {
            do {
                try await stop(usingMethod: .request)
            } catch {
                delegate?.virtualMachine(self, didErrorWithMessage: error.localizedDescription)
            }
        }
    }
}
