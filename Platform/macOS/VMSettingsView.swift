//
// Copyright © 2020 osy. All rights reserved.
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

import AppKit
import SwiftUI

@available(macOS 11, *)
struct VMSettingsView<Config: UTMConfiguration>: View {
    let vm: VMData
    @ObservedObject var config: Config
    
    @EnvironmentObject private var data: UTMData
    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>
    
    var body: some View {
        NavigationView {
            List {
                if config is UTMQemuConfiguration {
                    VMQEMUSettingsView(config: config as! UTMQemuConfiguration)
                } else if config is UTMAppleConfiguration {
                    VMAppleSettingsView(config: config as! UTMAppleConfiguration)
                } else if config is VPhoneConfiguration {
                    VPhoneSettingsView(config: config as! VPhoneConfiguration)
                }
            }.listStyle(.sidebar)
            Text("")
                .settingsToolbar()
        }
        .frame(minWidth: 800, minHeight: 400, alignment: .leading)
        .legacySettingsToolbar {
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(action: cancel) {
                    Text("Cancel")
                }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(action: save) {
                    Text("Save")
                }
            }
        }
        .environmentObject(vm)
        .disabled(data.busy)
        .overlay(BusyOverlay())
    }
    
    func save() {
        data.busyWorkAsync {
            try await data.save(vm: vm)
            await MainActor.run {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    func cancel() {
        presentationMode.wrappedValue.dismiss()
        data.busyWorkAsync {
            try await data.discardChanges(for: vm)
        }
    }
}

@available(macOS 11, *)
struct ScrollableViewModifier: ViewModifier {
    @State private var scrollViewContentSize: CGSize = .zero
    
    func body(content: Content) -> some View {
        ScrollView {
            content
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                GeometryReader { geo -> Color in
                    DispatchQueue.main.async {
                        scrollViewContentSize = geo.size
                    }
                    return Color.clear
                }
            )
        }
        .frame(idealWidth: scrollViewContentSize.width)
    }
}

fileprivate struct EmptyToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem {
            EmptyView()
        }
    }
}

@available(macOS 12, *)
struct SettingsToolbarViewModifier<AdditionalContent>: ViewModifier where AdditionalContent: ToolbarContent {
    @EnvironmentObject private var vm: VMData
    @EnvironmentObject private var data: UTMData
    @Environment(\.dismiss) private var dismiss
    
    let additionalContent: AdditionalContent?
    
    fileprivate init() where AdditionalContent == EmptyToolbarContent {
        self.additionalContent = nil
    }
    
    init(additionalContent: () -> AdditionalContent) {
        self.additionalContent = additionalContent()
    }
    
    func body(content: Content) -> some View {
        let view = content.toolbar {
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(action: cancel) {
                    Text("Cancel")
                }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Form {
                    Button(action: save) {
                        Text("Save")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        if let additionalContent = additionalContent {
            view.toolbar {
                additionalContent
            }
        } else {
            view
        }
    }
    
    private func save() {
        data.busyWorkAsync {
            try await data.save(vm: vm)
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func cancel() {
        dismiss()
        data.busyWorkAsync {
            try await data.discardChanges(for: vm)
        }
    }
}

@available(macOS 11, *)
extension View {
    func scrollable() -> some View {
        self.modifier(ScrollableViewModifier())
    }
    
    @ViewBuilder
    fileprivate func legacySettingsToolbar<Content>(@ToolbarContentBuilder content: () -> Content) -> some View where Content: ToolbarContent {
        if #available(macOS 12, *) {
            self
        } else {
            self.toolbar(content: content)
        }
    }
    
    @ViewBuilder
    func settingsToolbar() -> some View {
        if #available(macOS 12, *) {
            self.modifier(SettingsToolbarViewModifier())
        } else {
            self
        }
    }
    
    @ViewBuilder
    func settingsToolbar<Content>(@ToolbarContentBuilder additionalContent: () -> Content) -> some View where Content: ToolbarContent {
        if #available(macOS 12, *) {
            self.modifier(SettingsToolbarViewModifier(additionalContent: additionalContent))
        } else {
            self
        }
    }
}

@available(macOS 11, *)
struct VMSettingsView_Previews: PreviewProvider {
    @State static private var qemuConfig = UTMQemuConfiguration()
    @State static private var appleConfig = UTMAppleConfiguration()
    @State static private var data = UTMData()
    
    static var previews: some View {
        VMSettingsView(vm: VMData(from: .empty), config: qemuConfig)
            .environmentObject(data)
            .previewDisplayName("QEMU VM Settings")
        VMSettingsView(vm: VMData(from: .empty), config: appleConfig)
            .environmentObject(data)
            .previewDisplayName("Apple VM Settings")
    }
}

// MARK: - Virtual iPhone settings

/// Sidebar + detail settings for a virtual iPhone, mirroring the page-per-topic
/// layout `VMQEMUSettingsView`/`VMAppleSettingsView` use — each `NavigationLink`
/// pushes into the shared detail pane on the right (see `VMSettingsView`), so
/// the fields spread across the full 800×400 sheet instead of piling into one
/// cramped sidebar list next to a permanently empty detail pane.
@available(macOS 11, *)
struct VPhoneSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration
    @EnvironmentObject private var vm: VMData

    @State private var generalActive = true

    /// `vm create` flags (Frida, DSC max-slide, spoof build, keep artifacts)
    /// only take effect the moment the VM is first provisioned — vphone-cli's
    /// `vm config` has no way to change them afterward, so editing them on an
    /// already-created VM would silently do nothing. Gate the controls on
    /// that instead of quietly no-oping on save.
    private var isExistingVM: Bool {
        FileManager.default.fileExists(atPath: vm.pathUrl.path)
    }

    var body: some View {
        NavigationLink(isActive: $generalActive) {
            VPhoneGeneralSettingsView(config: config).scrollable().settingsToolbar()
        } label: {
            Label("General", systemImage: "info.circle")
        }
        NavigationLink {
            VPhoneHardwareSettingsView(config: config).scrollable().settingsToolbar()
        } label: {
            Label("Hardware", systemImage: "cpu")
        }
        NavigationLink {
            VPhoneNetworkSettingsView(config: config).scrollable().settingsToolbar()
        } label: {
            Label("Network", systemImage: "network")
        }
        NavigationLink {
            VPhoneSSHSettingsView(config: config).scrollable().settingsToolbar()
        } label: {
            Label("SSH", systemImage: "terminal")
        }
        NavigationLink {
            VPhoneAdvancedSettingsView(config: config, isLocked: isExistingVM).scrollable().settingsToolbar()
        } label: {
            Label("Advanced", systemImage: "wrench.and.screwdriver")
        }
        NavigationLink {
            VPhoneNotesSettingsView(config: config).scrollable().settingsToolbar()
        } label: {
            Label("Notes", systemImage: "note.text")
        }
        // Custom entries are edited right in this sidebar — add/rename/remove
        // here, rather than herding them into one cramped sub-page — since
        // that's what "editable list" means for a NavigationView sidebar.
        Section("Custom") {
            ForEach($config.customFields) { $field in
                NavigationLink {
                    VPhoneCustomFieldDetailView(field: $field) {
                        config.customFields.removeAll { $0.id == field.id }
                    }
                    .scrollable()
                    .settingsToolbar()
                } label: {
                    Label(field.key.isEmpty ? "Untitled" : field.key, systemImage: "tag")
                }
            }
            .onDelete { offsets in
                config.customFields.remove(atOffsets: offsets)
            }
            Button {
                config.customFields.append(VPhoneCustomField(key: "New Field"))
            } label: {
                Label("Add Field", systemImage: "plus.circle")
            }
        }
    }
}

@available(macOS 11, *)
private struct VPhoneGeneralSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration

    var body: some View {
        Form {
            Section("Virtual iPhone") {
                TextField("Name", text: $config.information.name)
                Picker("Firmware profile", selection: $config.variant) {
                    Text("Less").tag("less")
                    Text("Regular").tag("regular")
                    Text("Developer").tag("dev")
                    Text("Jailbreak").tag("jb")
                    Text("Experimental").tag("exp")
                }
                Text("Firmware profile is used when the iPhone is first provisioned.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

@available(macOS 11, *)
private struct VPhoneHardwareSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration

    var body: some View {
        Form {
            Section("Hardware") {
                Stepper(value: $config.cpuCount, in: 4...16) {
                    HStack {
                        Text("CPU")
                        Spacer()
                        Text("\(config.cpuCount) cores").foregroundColor(.secondary)
                    }
                }
                Stepper(value: $config.memorySizeMib, in: 4096...32768, step: 1024) {
                    HStack {
                        Text("Memory")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(config.memorySizeMib) * 1_048_576, countStyle: .binary))
                            .foregroundColor(.secondary)
                    }
                }
                Text("CPU and memory can be changed on an existing iPhone — restart it afterward for the new values to take effect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Disk")
                    Spacer()
                    Text("\(config.diskSizeGib) GB").foregroundColor(.secondary)
                }
                Text("Disk size is selected when the iPhone is created and cannot be changed later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

@available(macOS 11, *)
private struct VPhoneNetworkSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration

    var body: some View {
        Form {
            Section("Network") {
                Picker("Mode", selection: $config.networkMode) {
                    Text("NAT").tag("nat")
                    Text("Bridged").tag("bridged")
                    Text("None").tag("none")
                }
            }
        }
    }
}

@available(macOS 11, *)
private struct VPhoneAdvancedSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration
    let isLocked: Bool

    var body: some View {
        Form {
            Section("Provisioning") {
                Toggle("Enable Frida", isOn: $config.enableFrida)
                    .disabled(isLocked)
                Text("Installs re.frida.server and relaxes the jb/exp kernel for Frida Stalker support.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Force DSC max-slide fit", isOn: $config.forceDSCMaxSlide)
                    .disabled(isLocked)
                Text("Zeroes the dyld cache max-slide on non-27 bases so it fits — opt in only if firmware provisioning fails to map the shared cache.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if config.variant == "exp" {
                    TextField("Spoof build version", text: $config.spoofBuild)
                        .disabled(isLocked)
                    Text("Experimental profile only — rewrites ProductBuildVersion to this build id.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Keep intermediate artifacts", isOn: $config.keepArtifacts)
                    .disabled(isLocked)
                Text("Keeps built restore firmware and extracted CFW input dirs after provisioning instead of removing them to save space.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if isLocked {
                Section {
                    Text("These only take effect when the iPhone is first provisioned and cannot be changed on an existing VM.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

@available(macOS 11, *)
private struct VPhoneNotesSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration

    var body: some View {
        Form {
            Section("Notes") {
                TextEditor(text: Binding($config.information.notes, replacingNilWith: ""))
                    .frame(minHeight: 200)
            }
        }
    }
}

/// A single user-defined sidebar entry — rename it (renames the row in the
/// sidebar too, since the label is driven by `field.key`), fill in a value,
/// or remove it. No fixed schema: for whatever the built-in settings don't
/// cover.
@available(macOS 11, *)
private struct VPhoneCustomFieldDetailView: View {
    @Binding var field: VPhoneCustomField
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section("Custom Field") {
                TextField("Name", text: $field.key)
                TextEditor(text: $field.value)
                    .frame(minHeight: 150)
            }
            Section {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Field", systemImage: "trash")
                }
            }
        }
    }
}

/// vphone-cli's jb/exp CFW profiles enable OpenSSH on a fixed port with the
/// standard jailbreak default credential (`cfw_install_jb.sh`'s final banner:
/// "SSH will be available on port 22222 (password: alpine)"). The guest's IP
/// is only known to the separate `vphone-cli` process actually running the
/// VM (host↔guest vsock handshake in `VPhoneControl.swift`) — vPhone-UTM has
/// no channel to that live state, so this shows the fixed part of the
/// connection command rather than a fake "live" address it can't back up.
@available(macOS 11, *)
private struct VPhoneSSHSettingsView: View {
    @ObservedObject var config: VPhoneConfiguration

    private var isAvailable: Bool { config.variant == "jb" || config.variant == "exp" }

    private var command: String { "ssh root@<iphone-ip> -p 22222" }

    var body: some View {
        Form {
            Section("SSH") {
                if isAvailable {
                    HStack {
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(command, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    Text("Default password is alpine — change it after first login.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Replace <iphone-ip> with the address shown in the vphone-cli window's title bar once the iPhone has booted and connected — vPhone-UTM doesn't have a way to read that live from here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("SSH is enabled by the Jailbreak and Experimental firmware profiles only.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

@available(macOS 11, *)
struct VPhoneDetailsView: View {
    @ObservedObject var vm: VMData
    @ObservedObject var config: VPhoneConfiguration
    @EnvironmentObject private var data: UTMData
    @State private var size: Int64 = 0

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .binary)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black)
                    Image(systemName: "iphone")
                        .font(.system(size: 150, weight: .thin))
                        .foregroundColor(.white)
                    if vm.isBusy {
                        Spinner(size: .large)
                    } else if vm.isStopped {
                        Button {
                            data.run(vm: vm)
                        } label: {
                            Label("Start iPhone", systemImage: "play.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 72))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)

                VStack(alignment: .leading, spacing: 14) {
                    detailRow("Status", systemImage: "info.circle", value: vm.stateLabel)
                    detailRow("Device", systemImage: "iphone", value: "Virtual iPhone")
                    detailRow("CPU", systemImage: "cpu", value: "\(config.cpuCount) cores")
                    detailRow("Memory", systemImage: "memorychip", value: vm.detailsSystemMemoryLabel)
                    detailRow("Disk", systemImage: "internaldrive", value: sizeLabel)
                    detailRow("Network", systemImage: "network", value: config.networkMode.uppercased())
                    detailRow("Firmware profile", systemImage: "checkmark.shield", value: config.variant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                if let notes = config.information.notes, !notes.isEmpty {
                    Text(notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationSubtitle(vm.detailsTitleLabel)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if vm.isStopped {
                    Button {
                        data.run(vm: vm)
                    } label: {
                        Label("Start", systemImage: "play")
                    }
                } else {
                    Button {
                        data.stop(vm: vm)
                    } label: {
                        Label("Stop", systemImage: "stop")
                    }
                }
                Button {
                    data.edit(vm: vm)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .disabled(!vm.isModifyAllowed)
            }
        }
        .sheet(isPresented: $data.showSettingsModal) {
            VMSettingsView(vm: vm, config: config)
                .environmentObject(data)
        }
        .task(id: vm.id) {
            size = await data.computeSize(for: vm)
        }
    }

    private func detailRow(_ title: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .frame(width: 160, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
