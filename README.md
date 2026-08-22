# vPhone-UTM

A personal fork of [UTM](https://github.com/utmapp/UTM) rebuilt into a dedicated macOS frontend for
[vphone-cli](https://github.com/MakrSas/vphone-cli-modded) — booting a virtual iPhone via Apple's
Virtualization.framework instead of the general-purpose QEMU/UTM VM manager this project started as.

## What's different from upstream UTM

- **The VM-creation wizard drives `vphone-cli` end-to-end** instead of the generic multi-OS wizard —
  `Platform/macOS/VMWizardView.swift` was rewritten from the OS-picker/hardware/drives/sharing flow
  into a 4-step flow (identity → resources → firmware → provisioning) that shells out to
  `vphone-cli vm create` and streams its progress live in the window.
- **A dedicated "Virtual iPhone" settings sheet** (`Platform/macOS/VMSettingsView.swift`) — sidebar +
  detail layout with General/Hardware/Network/SSH/Advanced/Notes pages, freely add/remove custom
  key-value fields directly in the sidebar, and RAM editing on already-created VMs.
- **Fix: `vm create` launched via `do shell script … with administrator privileges` (as the GUI
  must, to grant the private virtualization entitlements) used to hang forever on "trying to
  authorize"** — the underlying CLI streamed its progress by checking `isatty(STDOUT_FILENO)`, which
  is always false when driven from a GUI through a pipe. Fixed on the CLI side
  ([vphone-cli-modded](https://github.com/MakrSas/vphone-cli-modded)); this repo's `UTMVirtualMachine`
  also gained AMFI self-heal (auto-retries once via `amfidont` if the CLI gets killed by AMFI on an
  ad-hoc-signed private-entitlement binary).
- **New app icon.**

## About UTM

> It is possible to invent a single machine which can be used to compute any computable sequence.

-- <cite>Alan Turing, 1936</cite>

UTM is a full featured system emulator and virtual machine host for iOS and macOS. It is based off of QEMU. In short, it allows you to run Windows, Linux, and more on your Mac, iPhone, and iPad. More information at https://getutm.app/ and https://mac.getutm.app/

<p align="center">
  <img width="450px" alt="UTM running on an iPhone" src="screen.png">
  <br>
  <img width="450px" alt="UTM running on a MacBook" src="screenmac.png">
</p>

## Features

* Full system emulation (MMU, devices, etc) using QEMU
* 30+ processors supported including x86_64, ARM64, and RISC-V
* VGA graphics mode using SPICE and QXL
* Text terminal mode
* USB devices
* JIT based acceleration using QEMU TCG
* Frontend designed from scratch for macOS 11 and iOS 11+ using the latest and greatest APIs
* Create, manage, run VMs directly from your device

## Additional macOS Features

* Hardware accelerated virtualization using Hypervisor.framework and QEMU
* Boot macOS guests with Virtualization.framework on macOS 12+

## UTM SE

UTM/QEMU requires dynamic code generation (JIT) for maximum performance. JIT on iOS devices require either a jailbroken device, or one of the various workarounds found for specific versions of iOS (see "Install" for more details).

UTM SE ("slow edition") uses a [threaded interpreter][3] which performs better than a traditional interpreter but still slower than JIT. This technique is similar to what [iSH][4] does for dynamic execution. As a result, UTM SE does not require jailbreaking or any JIT workarounds and can be sideloaded as a regular app.

To optimize for size and build times, only the following architectures are included in UTM SE: ARM, PPC, RISC-V, and x86 (all with both 32-bit and 64-bit variants).

## Install

UTM (SE) for iOS: https://getutm.app/install/

UTM is also available for macOS: https://mac.getutm.app/

## Development

### [macOS Development](Documentation/MacDevelopment.md)

### [iOS Development](Documentation/iOSDevelopment.md)

## Related

* [iSH][4]: emulates a usermode Linux terminal interface for running x86 Linux applications on iOS
* [a-shell][5]: packages common Unix commands and utilities built natively for iOS and accessible through a terminal interface

## License

UTM is distributed under the permissive Apache 2.0 license. However, it uses several (L)GPL components. Most are dynamically linked but the gstreamer plugins are statically linked and parts of the code are taken from qemu. Please be aware of this if you intend on redistributing this application.

Some icons made by [Freepik](https://www.freepik.com) from [www.flaticon.com](https://www.flaticon.com/).

Additionally, UTM frontend depends on the following MIT/BSD License components:

* [IQKeyboardManager](https://github.com/hackiftekhar/IQKeyboardManager)
* [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
* [ZIP Foundation](https://github.com/weichsel/ZIPFoundation)
* [InAppSettingsKit](https://github.com/futuretap/InAppSettingsKit)

Continuous integration hosting is provided by [MacStadium](https://www.macstadium.com/opensource)

[<img src="https://uploads-ssl.webflow.com/5ac3c046c82724970fc60918/5c019d917bba312af7553b49_MacStadium-developerlogo.png" alt="MacStadium logo" width="250">](https://www.macstadium.com)

  [1]: https://github.com/utmapp/UTM/actions?query=event%3Arelease+workflow%3ABuild
  [2]: screen.png
  [3]: https://github.com/ktemkin/qemu/blob/with_tcti/tcg/aarch64-tcti/README.md
  [4]: https://github.com/ish-app/ish
  [5]: https://github.com/holzschu/a-shell
