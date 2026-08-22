//
// Copyright © 2022 osy. All rights reserved.
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

private let kUTMBundleConfigFilename = "config.plist"

protocol UTMConfiguration: Codable, ObservableObject {
    associatedtype Drive: UTMConfigurationDrive
    static var oldestVersion: Int { get }
    static var currentVersion: Int { get }
    var information: UTMConfigurationInfo { get }
    var drives: [Drive] { get set }
    var backend: UTMBackend { get }
    func prepareSave(for packageURL: URL) async throws
    func saveData(to dataURL: URL) async throws -> [URL]
}

extension UTMConfiguration {
    static var oldestVersion: Int { 4 }
    static var currentVersion: Int { 4 }
}

extension CodingUserInfoKey {
    static var dataURL: CodingUserInfoKey {
        return CodingUserInfoKey(rawValue: "dataURL")!
    }
}

enum UTMBackend: String, CaseIterable, Codable {
    case unknown = "Unknown"
    case apple = "Apple"
    case qemu = "QEMU"
    case vphone = "vPhone"
}

enum UTMConfigurationError: Error {
    case versionTooLow
    case versionTooHigh
    case invalidConfigurationValue(String)
    case invalidBackend
    case invalidDataURL
    case invalidDriveConfiguration
    case customIconInvalid
    case driveAlreadyExists(URL)
    case cannotCreateDiskImage
}

extension UTMConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .versionTooLow: return NSLocalizedString("This configuration is too old and is not supported.", comment: "UTMConfiguration")
        case .versionTooHigh: return NSLocalizedString("This configuration is saved with a newer version of UTM and is not compatible with this version.", comment: "UTMConfiguration")
        case .invalidConfigurationValue(let value): return String.localizedStringWithFormat(NSLocalizedString("An invalid value of '%@' is used in the configuration file.", comment: "UTMConfiguration"), value)
        case .invalidBackend: return NSLocalizedString("The backend for this configuration is not supported.", comment: "UTMConfiguration")
        case .driveAlreadyExists(let url): return String.localizedStringWithFormat(NSLocalizedString("The drive '%@' already exists and cannot be created.", comment: "UTMConfiguration"), url.lastPathComponent)
        default: return NSLocalizedString("An internal error has occurred.", comment: "UTMConfiguration")
        }
    }
}

// MARK: - Configuration file parsing

private final class UTMConfigurationStub: Decodable {
    var backend: UTMBackend
    var configurationVersion: Int
    
    enum CodingKeys: String, CodingKey {
        case backend = "Backend"
        case configurationVersion = "ConfigurationVersion"
    }
    
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        backend = try values.decodeIfPresent(UTMBackend.self, forKey: .backend) ?? .unknown
        configurationVersion = try values.decodeIfPresent(Int.self, forKey: .configurationVersion) ?? 0
    }
}

extension UTMConfiguration {
    static var dataDirectoryName: String { "Data" }
    
    static func load(from packageURL: URL) throws -> any UTMConfiguration {
        let scopedAccess = packageURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                packageURL.stopAccessingSecurityScopedResource()
            }
        }
        let dataURL = packageURL.appendingPathComponent(Self.dataDirectoryName)
        let configURL = packageURL.appendingPathComponent(kUTMBundleConfigFilename)
        let configData = try Data(contentsOf: configURL)
        let decoder = PropertyListDecoder()
        decoder.userInfo = [.dataURL: dataURL]
        let stub = try decoder.decode(UTMConfigurationStub.self, from: configData)
        if stub.backend == .unknown {
            #if os(macOS)
            // we might be using a legacy configuration
            do {
                // is it a legacy apple config?
                let legacy = try decoder.decode(UTMLegacyAppleConfiguration.self, from: configData)
                return UTMAppleConfiguration(migrating: legacy, dataURL: dataURL)
            } catch {
                guard case UTMAppleConfigurationError.notAppleConfiguration = error else {
                    throw error
                }
            }
            #endif
            // is it a legacy QEMU config?
            let dict = try NSDictionary(contentsOf: configURL, error: ()) as! [AnyHashable : Any]
            let name = ConcreteVirtualMachine.virtualMachineName(for: packageURL)
            let legacy = UTMLegacyQemuConfiguration(dictionary: dict, name: name, path: packageURL)
            return UTMQemuConfiguration(migrating: legacy)
        } else if stub.backend == .qemu {
            // QEMU configuration
            return try decoder.decode(UTMQemuConfiguration.self, from: configData)
        } else if stub.backend == .apple {
            // Apple configuration
            #if os(macOS)
            return try decoder.decode(UTMAppleConfiguration.self, from: configData)
            #else
            throw UTMConfigurationError.invalidBackend
            #endif
        } else if stub.backend == .vphone {
            #if os(macOS)
            return try decoder.decode(VPhoneConfiguration.self, from: configData)
            #else
            throw UTMConfigurationError.invalidBackend
            #endif
        } else {
            throw UTMConfigurationError.invalidBackend
        }
    }
    
    func save(to packageURL: URL) async throws {
        let fileManager = FileManager.default

        // let concrete class do any pre-processing
        try await prepareSave(for: packageURL)
        // create package directory
        if !fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)
        }
        // create data directory
        let dataURL = packageURL.appendingPathComponent(Self.dataDirectoryName)
        if !fileManager.fileExists(atPath: dataURL.path) {
            try fileManager.createDirectory(at: dataURL, withIntermediateDirectories: false)
        }
        // save new and existing data
        let existingDataURLs = try await saveData(to: dataURL)
        // cleanup any extra unreferenced files
        try await Self.cleanupAllFiles(at: dataURL, notIncluding: existingDataURLs)
        // create config.plist
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let settingsData = try encoder.encode(self)
        try settingsData.write(to: packageURL.appendingPathComponent(kUTMBundleConfigFilename))
    }
    
    /// Check if a file has changed and if so, copy the new file to the bundle
    /// - Parameters:
    ///   - sourceURL: File to copy
    ///   - destFolderURL: Destination in bundle's data directory
    ///   - customCopy: If non-nil, a custom copy function is invoked
    /// - Returns: URL of the updated item in the bundle
    static func copyItemIfChanged(from sourceURL: URL, to destFolderURL: URL, customCopy: ((_ sourceURL: URL, _ destURL: URL) async throws -> URL)? = nil) async throws -> URL {
        _ = sourceURL.startAccessingSecurityScopedResource()
        defer {
            sourceURL.stopAccessingSecurityScopedResource()
        }
        let fileManager = FileManager.default
        let destURL = destFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
        // check if both are same file
        if fileManager.fileExists(atPath: destURL.path) {
            let sourceRef = try sourceURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            let destRef = try destURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            if sourceRef?.isEqual(destRef) ?? false {
                return destURL
            }
        }
        if let customCopy = customCopy {
            return try await customCopy(sourceURL, destFolderURL)
        } else {
            let newUrl = UTMData.newImage(from: sourceURL, to: destFolderURL)
            try await Task.detached {
                try FileManager.default.copyItem(at: sourceURL, to: newUrl)
            }.value
            return destURL
        }
    }
    
    private static func cleanupAllFiles(at dataURL: URL, notIncluding urls: [URL]) async throws {
        let fileManager = FileManager.default
        let existingNames = urls.map { url in
            url.lastPathComponent
        }
        let dataFileURLs = try fileManager.contentsOfDirectory(at: dataURL, includingPropertiesForKeys: nil)
        try await Task.detached {
            for dataFileURL in dataFileURLs {
                if !existingNames.contains(dataFileURL.lastPathComponent) {
                    try FileManager.default.removeItem(at: dataFileURL)
                }
            }
        }.value
    }
}

// MARK: - vPhone metadata

/// UI metadata stored alongside a vphone-cli bundle.
///
/// vphone-cli owns `config.plist` in the bundle, so this configuration deliberately
/// uses its own sidecar file and never writes to the firmware manifest.
#if os(macOS)
final class VPhoneConfiguration: UTMConfiguration {
    typealias Drive = UTMQemuConfigurationDrive

    static let metadataFilename = ".vphone-utm.plist"

    @Published var information: UTMConfigurationInfo
    @Published var cpuCount: Int
    @Published var memorySizeMib: Int
    @Published var diskSizeGib: Int
    @Published var networkMode: String
    @Published var variant: String
    @Published var iphoneSource: URL?
    @Published var cloudOSSource: URL?
    @Published var drives: [UTMQemuConfigurationDrive]

    /// Create-time-only `vm create` flags — vphone-cli's `vm config` cannot
    /// change these on an existing VM (see VPhoneVMConfigCommand), so the
    /// settings UI shows them read-only once the bundle already exists.
    @Published var enableFrida: Bool
    @Published var forceDSCMaxSlide: Bool
    @Published var spoofBuild: String
    @Published var keepArtifacts: Bool

    /// Free-form user-defined notes, distinct from `information.notes` — an
    /// ordered list so the user can add/remove/rename entries themselves.
    @Published var customFields: [VPhoneCustomField]

    /// Transient UI state for a newly-created virtual iPhone. This is deliberately
    /// not encoded: an existing VM must never start the firmware pipeline again
    /// just because its settings are saved.
    var provisioningController: VPhoneProvisioningController?
    var replaceIncompleteBundleOnSave = false

    var backend: UTMBackend { .vphone }

    init(name: String = "Virtual iPhone", cpuCount: Int = 8, memorySizeMib: Int = 8192,
         diskSizeGib: Int = 64, networkMode: String = "nat", variant: String = "regular",
         iphoneSource: URL? = nil, cloudOSSource: URL? = nil) {
        var information = UTMConfigurationInfo()
        information.name = name
        self.information = information
        self.cpuCount = cpuCount
        self.memorySizeMib = memorySizeMib
        self.diskSizeGib = diskSizeGib
        self.networkMode = networkMode
        self.variant = variant
        self.iphoneSource = iphoneSource
        self.cloudOSSource = cloudOSSource
        self.drives = []
        self.enableFrida = false
        self.forceDSCMaxSlide = false
        self.spoofBuild = ""
        self.keepArtifacts = false
        self.customFields = []
    }

    private enum CodingKeys: String, CodingKey {
        case backend = "Backend"
        case configurationVersion = "ConfigurationVersion"
        case information = "Information"
        case cpuCount = "CPU"
        case memorySizeMib = "Memory"
        case diskSizeGib = "Disk"
        case networkMode = "Network"
        case variant = "Variant"
        case iphoneSource = "iPhoneSource"
        case cloudOSSource = "CloudOSSource"
        case enableFrida = "EnableFrida"
        case forceDSCMaxSlide = "ForceDSCMaxSlide"
        case spoofBuild = "SpoofBuild"
        case keepArtifacts = "KeepArtifacts"
        case customFields = "CustomFields"
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        information = try values.decode(UTMConfigurationInfo.self, forKey: .information)
        cpuCount = try values.decodeIfPresent(Int.self, forKey: .cpuCount) ?? 8
        memorySizeMib = try values.decodeIfPresent(Int.self, forKey: .memorySizeMib) ?? 8192
        diskSizeGib = try values.decodeIfPresent(Int.self, forKey: .diskSizeGib) ?? 64
        networkMode = try values.decodeIfPresent(String.self, forKey: .networkMode) ?? "nat"
        variant = try values.decodeIfPresent(String.self, forKey: .variant) ?? "regular"
        iphoneSource = try values.decodeIfPresent(URL.self, forKey: .iphoneSource)
        cloudOSSource = try values.decodeIfPresent(URL.self, forKey: .cloudOSSource)
        drives = []
        enableFrida = try values.decodeIfPresent(Bool.self, forKey: .enableFrida) ?? false
        forceDSCMaxSlide = try values.decodeIfPresent(Bool.self, forKey: .forceDSCMaxSlide) ?? false
        spoofBuild = try values.decodeIfPresent(String.self, forKey: .spoofBuild) ?? ""
        keepArtifacts = try values.decodeIfPresent(Bool.self, forKey: .keepArtifacts) ?? false
        customFields = try values.decodeIfPresent([VPhoneCustomField].self, forKey: .customFields) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(backend, forKey: .backend)
        try values.encode(Self.currentVersion, forKey: .configurationVersion)
        try values.encode(information, forKey: .information)
        try values.encode(cpuCount, forKey: .cpuCount)
        try values.encode(memorySizeMib, forKey: .memorySizeMib)
        try values.encode(diskSizeGib, forKey: .diskSizeGib)
        try values.encode(networkMode, forKey: .networkMode)
        try values.encode(variant, forKey: .variant)
        try values.encodeIfPresent(iphoneSource, forKey: .iphoneSource)
        try values.encodeIfPresent(cloudOSSource, forKey: .cloudOSSource)
        try values.encode(enableFrida, forKey: .enableFrida)
        try values.encode(forceDSCMaxSlide, forKey: .forceDSCMaxSlide)
        try values.encode(spoofBuild, forKey: .spoofBuild)
        try values.encode(keepArtifacts, forKey: .keepArtifacts)
        try values.encode(customFields, forKey: .customFields)
    }

    func prepareSave(for packageURL: URL) async throws {
    }

    func saveData(to dataURL: URL) async throws -> [URL] {
        []
    }

    static func loadMetadata(from bundleURL: URL) throws -> VPhoneConfiguration {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(metadataFilename))
        return try PropertyListDecoder().decode(VPhoneConfiguration.self, from: data)
    }

    func saveMetadata(to bundleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: bundleURL.appendingPathComponent(Self.metadataFilename))
    }
}

/// A single user-defined note attached to a virtual iPhone — purely
/// informational (not read by vphone-cli), so the user can annotate a VM
/// with whatever they want without waiting on new first-class settings.
struct VPhoneCustomField: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}
#endif
