# vPhone-UTM

A personal fork of [UTM](https://github.com/utmapp/UTM) rebuilt into a dedicated macOS frontend for
[vphone-cli-modded](https://github.com/MakrSas/vphone-cli-modded) — boots a virtual iPhone on Apple
Silicon via Apple's Virtualization.framework, instead of the general-purpose QEMU/multi-OS VM manager
this project started as. All credit for the underlying app (UI framework, VM lifecycle plumbing,
settings-sheet patterns) goes to the upstream UTM project; this fork narrows it to one job.

vphone-cli-modded does the actual work (firmware download/patch/restore, booting the VM); this app
is a GUI wrapper around it — creating/managing virtual iPhones from a proper app window and menu bar
instead of the bare CLI.

## Features

- **Guided VM creation** — a 4-step wizard (identity → resources → firmware → provisioning) drives
  `vphone-cli vm create` end-to-end and streams its progress live in the window, instead of a bare
  terminal.
- **Trackpad gestures in the VM window** — scroll gestures on the host trackpad translate into
  synthetic touch-drag events inside the guest.
- **Guest haptic feedback on the host trackpad** — when the guest triggers haptic feedback (jailbreak/
  experimental firmware only), it buzzes the Mac's own trackpad Taptic Engine.
- **A dedicated "Virtual iPhone" settings sheet** — hardware, network, SSH connection info, and
  freely-added custom key-value fields, alongside RAM editing on already-created VMs.
- **Move a VM's disk to external storage** to free up internal space, without losing track of it —
  the app notices if it's missing at launch and offers to relocate/re-point it.
- **Self-heals AMFI blocks** — this app (and vphone-cli-modded) run ad-hoc-signed with private
  virtualization entitlements, which AMFI kills on sight without an allowlist; both apps request that
  allowlist automatically (a single admin-password prompt) instead of leaving you to run a helper
  script by hand.

## Known issues

This is a personal project, fixed as things come up rather than on any schedule — open an issue if
you find something and I'll fix it.

## Install

**Prebuilt:** grab the latest build from [Releases](https://github.com/MakrSas/vPhone-UTM/releases) —
you'll also need [vphone-cli-modded](https://github.com/MakrSas/vphone-cli-modded/releases) installed
(this app shells out to it). After unzipping to `/Applications`, macOS will quarantine both as
downloaded — see the AMFI/Gatekeeper notes in each release's description.

**From source:**

```bash
git clone https://github.com/MakrSas/vPhone-UTM.git
cd vPhone-UTM
```

UTM's own dependencies (QEMU, SPICE, …) need to be staged into `sysroot-*` directories first — grab
them from [utmapp/UTM](https://github.com/utmapp/UTM)'s GitHub Actions `Sysroot-*` build artifacts
(this fork doesn't touch QEMU/SPICE, so upstream's sysroots are compatible). Then:

```bash
./scripts/install_local.sh
```

This builds the `macOS` scheme (Debug), signs it bottom-up (frameworks/XPC ad-hoc + hardened runtime,
outer app with `Platform/macOS/local-launch.entitlements`), and installs it to `/Applications`. See
that script for the manual steps if you'd rather run them yourself, and
`Documentation/MacDevelopment.md` for the general UTM dev setup this inherits.

## Requirements

- Apple Silicon Mac, macOS 15+
- [vphone-cli-modded](https://github.com/MakrSas/vphone-cli-modded) installed at
  `/opt/homebrew/bin/vphone-cli` (or set `$VPHONE_CLI_PATH`) — see that repo for its own requirements
  (SIP/AMFI relaxation, etc.), which this app inherits since it just drives that CLI

## License

UTM is distributed under the permissive Apache 2.0 license. However, it uses several (L)GPL components. Most are dynamically linked but the gstreamer plugins are statically linked and parts of the code are taken from qemu. Please be aware of this if you intend on redistributing this application.

Some icons made by [Freepik](https://www.freepik.com) from [www.flaticon.com](https://www.flaticon.com/).

Additionally, UTM frontend depends on the following MIT/BSD License components:

* [IQKeyboardManager](https://github.com/hackiftekhar/IQKeyboardManager)
* [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
* [ZIP Foundation](https://github.com/weichsel/ZIPFoundation)
* [InAppSettingsKit](https://github.com/futuretap/InAppSettingsKit)
