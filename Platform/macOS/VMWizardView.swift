//
// Copyright © 2021 osy. All rights reserved.
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

import SwiftUI
import UniformTypeIdentifiers

/// The UTM creation flow, specialised for the only supported guest: a virtual iPhone.
@available(macOS 12, *)
struct VMWizardView: View {
    @EnvironmentObject private var data: UTMData
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var name = "iPhone"
    @State private var variant = "regular"
    @State private var cpuCount = 8
    @State private var memoryMib = 8192
    @State private var diskGib = 64
    @State private var networkMode = "nat"
    @State private var useManualFirmware = false
    @State private var selectedFirmwareID = VPhoneFirmwareChoice.defaultChoice.id
    @State private var iphoneSource: URL?
    @State private var cloudOSSource: URL?
    @State private var choosingIPhoneIPSW = false
    @State private var choosingCloudOSIPSW = false
    @State private var errorMessage: String?
    @State private var showingLogs = false
    @StateObject private var provisioning = VPhoneProvisioningController()

    var body: some View {
        Group {
            switch step {
            case 0:
                identityPage
            case 1:
                resourcesPage
            case 2:
                firmwarePage
            default:
                provisioningPage
            }
        }
        .padding(.top)
        .frame(width: 460, height: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if step == 3 && provisioning.isRunning {
                    Button("Pause") { provisioning.cancel() }
                } else {
                    Button(step == 3 ? "Close" : "Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if step < 2 {
                    Button("Continue") { step += 1 }
                } else if step == 2 {
                    Button(createButtonTitle) { createIPhone(retrying: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedName.isEmpty || (useManualFirmware && (iphoneSource == nil || cloudOSSource == nil)))
                } else if provisioning.didFinish {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else if provisioning.canRestartDownload {
                    Button("Download Again") { restartFirmwareDownload() }
                        .buttonStyle(.borderedProminent)
                } else if provisioning.canRetry {
                    Button("Continue") {
                        provisioning.resetAMFIRecoveryForManualRetry()
                        createIPhone(retrying: true)
                    }
                        .buttonStyle(.borderedProminent)
                }
            }
            ToolbarItem(placement: .automatic) {
                if step > 0 && step < 3 && !provisioning.isRunning {
                    Button("Go Back") { step -= 1 }
                }
            }
        }
        .fileImporter(isPresented: $choosingIPhoneIPSW, allowedContentTypes: [.ipsw]) { result in
            if case .success(let url) = result { iphoneSource = url }
        }
        .fileImporter(isPresented: $choosingCloudOSIPSW, allowedContentTypes: [.ipsw]) { result in
            if case .success(let url) = result { cloudOSSource = url }
        }
        .alert("Couldn’t create virtual iPhone", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingLogs) {
            VPhoneSetupLogsView(logs: provisioning.logs)
        }
    }

    private var identityPage: some View {
        VMWizardContent("New Virtual iPhone") {
            Section {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Picker("Firmware profile", selection: $variant) {
                    Text("Less").tag("less")
                    Text("Regular").tag("regular")
                    Text("Developer").tag("dev")
                    Text("Jailbreak").tag("jb")
                    Text("Experimental").tag("exp")
                }
            } header: {
                Text("Identity")
            } footer: {
                Text(profileDescription)
            }
        }
    }

    private var resourcesPage: some View {
        VMWizardContent("Resources") {
            Section("Hardware") {
                Stepper(value: $cpuCount, in: 4...16) {
                    HStack {
                        Text("CPU")
                        Spacer()
                        Text("\(cpuCount) cores").foregroundColor(.secondary)
                    }
                }
                Stepper(value: $memoryMib, in: 4096...32768, step: 1024) {
                    HStack {
                        Text("Memory")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(memoryMib) * 1_048_576, countStyle: .binary))
                            .foregroundColor(.secondary)
                    }
                }
                Stepper(value: $diskGib, in: 32...256, step: 16) {
                    HStack {
                        Text("Disk")
                        Spacer()
                        Text("\(diskGib) GB").foregroundColor(.secondary)
                    }
                }
            }
            Section("Network") {
                Picker("Mode", selection: $networkMode) {
                    Text("NAT").tag("nat")
                    Text("Bridged").tag("bridged")
                    Text("None").tag("none")
                }
            }
        }
    }

    private var firmwarePage: some View {
        VMWizardContent("Firmware") {
            Section {
                Toggle("Use local IPSW files", isOn: $useManualFirmware)
                if !useManualFirmware {
                    Label("Download automatically", systemImage: "arrow.down.circle.fill")
                        .foregroundColor(.accentColor)
                    Picker("iOS version", selection: $selectedFirmwareID) {
                        ForEach(VPhoneFirmwareChoice.options) { choice in
                            Text("\(choice.name) — \(choice.cloudOSName)")
                                .tag(choice.id)
                        }
                    }
                    Text("vPhone downloads \(selectedFirmware.name) and \(selectedFirmware.cloudOSName) from Apple. The files are cached for future virtual iPhones.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    firmwarePicker(title: "iPhone IPSW", url: iphoneSource) {
                        choosingIPhoneIPSW = true
                    }
                    firmwarePicker(title: "CloudOS IPSW", url: cloudOSSource) {
                        choosingCloudOSIPSW = true
                    }
                }
            } footer: {
                if useManualFirmware {
                    Text("Choose both IPSW files. vPhone will use these local files and will not download the iPhone or CloudOS IPSW.")
                } else {
                    Text("The setup screen shows download progress, speed and time remaining. You can pause it; the next attempt continues the partially downloaded IPSW files.")
                }
            }
        }
    }

    private var provisioningPage: some View {
        VMWizardContent("Setting up iPhone") {
            Section {
                Label(provisioning.title, systemImage: provisioning.didFinish ? "checkmark.circle.fill" : "iphone.gen3.radiowaves.left.and.right")
                    .foregroundColor(provisioning.didFinish ? .green : .primary)
                Text(provisioning.detail)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !provisioning.isRunning && !provisioning.didFinish {
                    HStack {
                        Spacer()
                        Button("Show Logs") { showingLogs = true }
                            .disabled(!provisioning.hasLogs)
                    }
                }

                if let progress = provisioning.progress {
                    ProgressView(value: progress)
                    HStack {
                        if let downloadedSize = provisioning.downloadedSize, let totalSize = provisioning.totalSize {
                            Text("\(downloadedSize) of \(totalSize)")
                        } else if let downloadedSize = provisioning.downloadedSize {
                            Text("\(downloadedSize) downloaded")
                        } else {
                            Text(progress == 0 ? "Connecting to Apple…" : "Downloading…")
                        }
                        Spacer()
                        Text("\(Int(progress * 100))%")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else if provisioning.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                if provisioning.downloadSpeed != nil || provisioning.timeRemaining != nil {
                    HStack(spacing: 12) {
                        if let speed = provisioning.downloadSpeed {
                            Label(speed, systemImage: "speedometer")
                        }
                        if let remaining = provisioning.timeRemaining {
                            Label(remaining, systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } header: {
                Text("Setup progress")
            } footer: {
                if provisioning.canRetry {
                    Text("Continuing recreates only the incomplete virtual iPhone. Downloaded firmware remains in the cache and is resumed where possible.")
                } else if provisioning.isRunning {
                    Text("Keep this window open while the iPhone is being prepared. macOS may request administrator approval near the end.")
                }
            }
        }
    }

private func firmwarePicker(title: String, url: URL?, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(url?.lastPathComponent ?? "Not selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Choose…", action: action)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedFirmware: VPhoneFirmwareChoice {
        VPhoneFirmwareChoice.options.first(where: { $0.id == selectedFirmwareID }) ?? .defaultChoice
    }

    private var createButtonTitle: String {
        useManualFirmware ? "Create from Local IPSW" : "Download and Create"
    }

    private var profileDescription: String {
        switch variant {
        case "less": return "Minimal patch set; closest to stock iOS."
        case "dev": return "Adds developer entitlement and debugging bypasses."
        case "jb": return "Includes Sileo and TrollStore after first boot."
        case "exp": return "Experimental research patches in addition to the jailbreak set."
        default: return "Recommended: stock-like iOS with the core research bypasses."
        }
    }

    private func createIPhone(retrying: Bool) {
        if useManualFirmware {
            guard let iphoneSource, let cloudOSSource,
                  iphoneSource.isFileURL, cloudOSSource.isFileURL,
                  FileManager.default.isReadableFile(atPath: iphoneSource.path),
                  FileManager.default.isReadableFile(atPath: cloudOSSource.path) else {
                errorMessage = "Both selected IPSW files must be local and readable."
                return
            }
        }
        provisioning.begin(retrying: retrying)
        step = 3
        let configuration = VPhoneConfiguration(name: trimmedName, cpuCount: cpuCount,
                                                memorySizeMib: memoryMib, diskSizeGib: diskGib,
                                                networkMode: networkMode, variant: variant,
                                                iphoneSource: useManualFirmware ? iphoneSource : URL(string: selectedFirmware.iPhoneURL),
                                                cloudOSSource: useManualFirmware ? cloudOSSource : URL(string: selectedFirmware.cloudOSURL))
        configuration.provisioningController = provisioning
        configuration.replaceIncompleteBundleOnSave = retrying && provisioning.ownsIncompleteBundle
        Task {
            do {
                _ = try await data.create(config: configuration)
                provisioning.finished()
            } catch {
                if provisioning.isCancellationRequested {
                    if provisioning.paused() {
                        createIPhone(retrying: true)
                    }
                } else if let cliError = error as? VPhoneVirtualMachineError,
                          cliError.needsAMFIPermission,
                          provisioning.beginAMFIRecovery() {
                    do {
                        try await VPhoneVirtualMachine.enableAMFIPermission(using: provisioning)
                        createIPhone(retrying: true)
                    } catch {
                        provisioning.failed(with: error)
                    }
                } else {
                    provisioning.failed(with: error)
                }
            }
        }
    }

    private func restartFirmwareDownload() {
        provisioning.restartDownload()
    }
}

@available(macOS 12, *)
private struct VPhoneSetupLogsView: View {
    let logs: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Setup logs")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        }
        .padding()
        .frame(minWidth: 680, minHeight: 420)
    }
}

private struct VPhoneFirmwareChoice: Identifiable {
    let name: String
    let iPhoneURL: String
    let cloudOSName: String
    let cloudOSURL: String

    var id: String { name }

    static let defaultChoice = options.first(where: { $0.name == "iOS 26.1" })!

    static let options: [Self] = [
        .init(name: "iOS 18.6.2", iPhoneURL: "https://updates.cdn-apple.com/2025SummerFCS/fullrestores/093-20738/98758B5A-311E-4538-B365-FEE3D8792CDF/iPhone17,3_18.6.2_22G100_Restore.ipsw", cloudOSName: "cloudOS 26.1", cloudOSURL: cloud261),
        .init(name: "iOS 26.0", iPhoneURL: "https://updates.cdn-apple.com/2025FallFCS/fullrestores/093-40775/B7282E74-76C1-4D0A-8FAE-CE97FC2330C2/iPhone17,3_26.0_23A341_Restore.ipsw", cloudOSName: "cloudOS 26.1", cloudOSURL: cloud261),
        .init(name: "iOS 26.0.1", iPhoneURL: "https://updates.cdn-apple.com/2025FallFCS/fullrestores/093-46329/C1717B2A-9E58-4131-A398-75D9B1D01A89/iPhone17,3_26.0.1_23A355_Restore.ipsw", cloudOSName: "cloudOS 26.1", cloudOSURL: cloud261),
        .init(name: "iOS 26.1", iPhoneURL: "https://updates.cdn-apple.com/2025FallFCS/fullrestores/089-13864/668EFC0E-5911-454C-96C6-E1063CB80042/iPhone17,3_26.1_23B85_Restore.ipsw", cloudOSName: "cloudOS 26.1", cloudOSURL: cloud261),
        .init(name: "iOS 26.2", iPhoneURL: "https://updates.cdn-apple.com/2025FallFCS/fullrestores/089-90760/1214478F-8ED8-4AE0-B693-2F63CE0259A9/iPhone17,3_26.2_23C55_Restore.ipsw", cloudOSName: "cloudOS 26.2", cloudOSURL: cloud262),
        .init(name: "iOS 26.2.1", iPhoneURL: "https://updates.cdn-apple.com/2025FallFCS/fullrestores/047-34150/D14FB1F1-B8C5-4A20-9250-8DD35EF19BF5/iPhone17,3_26.2.1_23C71_Restore.ipsw", cloudOSName: "cloudOS 26.2", cloudOSURL: cloud262),
        .init(name: "iOS 26.3", iPhoneURL: "https://updates.cdn-apple.com/2026WinterFCS/fullrestores/047-39165/E8E603F3-A2E2-4638-8067-394754896386/iPhone17,3_26.3_23D127_Restore.ipsw", cloudOSName: "cloudOS 26.3", cloudOSURL: cloud263),
        .init(name: "iOS 26.3.1", iPhoneURL: "https://updates.cdn-apple.com/2026WinterFCS/fullrestores/047-90312/17B5C7BE-C560-43BD-BA9A-7DD1E5C2FC23/iPhone17,3_26.3.1_23D8133_Restore.ipsw", cloudOSName: "cloudOS 26.3", cloudOSURL: cloud263),
        .init(name: "iOS 26.4", iPhoneURL: "https://updates.cdn-apple.com/2026SpringFCS/fullrestores/122-06082/FE21226A-B87F-4FC7-9D4B-B97A9EAF5C20/iPhone17,3_26.4_23E246_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 26.4.1", iPhoneURL: "https://updates.cdn-apple.com/2026SpringFCS/fullrestores/122-28526/10E1E3EC-6A3E-4620-A569-8E0C4361AB77/iPhone17,3_26.4.1_23E254_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 26.4.2", iPhoneURL: "https://updates.cdn-apple.com/2026SpringFCS/fullrestores/122-60828/A4082066-CCC4-4903-89E6-FF4801EA609C/iPhone17,3_26.4.2_23E261_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 26.5", iPhoneURL: "https://updates.cdn-apple.com/2026SpringFCS/fullrestores/122-63074/5E6B4A05-BDBC-45FE-9606-22B8F4315989/iPhone17,3_26.5_23F77_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 26.5.2", iPhoneURL: "https://updates.cdn-apple.com/2026SpringFCS/fullrestores/140-25549/1AFB1F72-E48E-476A-9C21-42B27C846C01/iPhone17,3_26.5.2_23F84_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 26.6", iPhoneURL: "https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-58193/1F477C3E-934B-43C0-B428-753B9E005EC0/iPhone17,3_26.6_23G71_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 26.6.1", iPhoneURL: "https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-93817/B5362BAA-F3EE-49C8-BA43-309F0DAD1362/iPhone17,3_26.6.1_23G83_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 27 beta 1", iPhoneURL: "https://updates.cdn-apple.com/2026SpringSeed/fullrestores/122-99394/32118457-A80B-4953-BF2A-11F74FD7D375/iPhone17,3_27.0_24A5355q_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 27 beta 2", iPhoneURL: "https://updates.cdn-apple.com/2026SpringSeed/fullrestores/140-21207/F0510574-F649-48C5-B535-0A477E342BFB/iPhone17,3_27.0_24A5370h_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 27 beta 3", iPhoneURL: "https://updates.cdn-apple.com/2026SpringSeed/fullrestores/140-35950/D135F5B5-C2BE-4630-8AE9-C78A6F0E8381/iPhone17,3_27.0_24A5380h_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 27 beta 4", iPhoneURL: "https://updates.cdn-apple.com/2026SpringSeed/fullrestores/140-57108/5E816D0E-89BB-4B95-8825-6A3EDF22E509/iPhone17,3_27.0_24A5390f_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 27 beta 5", iPhoneURL: "https://updates.cdn-apple.com/2026SpringSeed/fullrestores/140-86338/57B34BF9-3BF5-4B47-BCCA-81B282175957/iPhone17,3_27.0_24A5408d_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
        .init(name: "iOS 27 beta 6", iPhoneURL: "https://updates.cdn-apple.com/2026SpringSeed/ad5b3026-b03e-4b21-8bcb-96d6ea527e09/iPhone17,3_27.0_24A5418b_Restore.ipsw", cloudOSName: "cloudOS 26.4", cloudOSURL: cloud264),
    ]

    private static let cloud261 = "https://updates.cdn-apple.com/private-cloud-compute/399b664dd623358c3de118ffc114e42dcd51c9309e751d43bc949b98f4e31349"
    private static let cloud262 = "https://updates.cdn-apple.com/private-cloud-compute/0cb00f22e0f7a8b33995b49b2bdca77f781ed6093a09c570ac21b0f012bab908"
    private static let cloud263 = "https://updates.cdn-apple.com/private-cloud-compute/edc92b58ab7e2f207a6407fd0a0e1a60f7d43bf9d93325bf6d3db3e154ee5525"
    private static let cloud264 = "https://updates.cdn-apple.com/private-cloud-compute/c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ada27273262b0b8b64"
}
