import AppKit
import SwiftUI

@main
struct CartoonouselApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: StripStore

    init() {
        Theme.registerBundledFonts()
        _store = State(initialValue: StripStore())
    }

    var body: some Scene {
        Window("Cartoonousel", id: "main") {
            ContentView()
                .environment(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Strips…") { store.openPicker() }
                    .keyboardShortcut("o")
                Button("Try Sample Strips") { store.loadSamples() }
            }
            CommandMenu("Strip") {
                Button("Next Strip") { store.step(1) }
                    .disabled(store.strips.isEmpty)
                Button("Previous Strip") { store.step(-1) }
                    .disabled(store.strips.isEmpty)
                Button("First Strip") { store.first() }
                    .disabled(store.strips.isEmpty)
                Button("Last Strip") { store.last() }
                    .disabled(store.strips.isEmpty)
                Divider()
                Button("Remove Strip") { store.removeCurrent() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.strips.isEmpty)
                Button("Remove All Strips…") { store.confirmRemoveAll() }
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
                    .disabled(store.strips.isEmpty)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (`swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The design's tweakable props (Ink / Carousel sections), as app preferences.
struct SettingsView: View {
    @AppStorage(Prefs.splatAmount) private var splatAmount = 7.0
    @AppStorage(Prefs.wobble) private var wobble = true
    @AppStorage(Prefs.autoAdvance) private var autoAdvance = 0.0
    @AppStorage(Prefs.showFilmstrip) private var showFilmstrip = true

    var body: some View {
        Form {
            Section("Ink") {
                LabeledContent("Splats") {
                    HStack {
                        Slider(value: $splatAmount, in: 0...10, step: 1)
                        Text("\(Int(splatAmount))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
            }
            Section("Carousel") {
                Toggle("Wobble", isOn: $wobble)
                LabeledContent("Auto-advance") {
                    HStack {
                        Slider(value: $autoAdvance, in: 0...20, step: 1)
                        Text(autoAdvance > 0 ? "\(Int(autoAdvance))s" : "Off")
                            .monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                Toggle("Show filmstrip", isOn: $showFilmstrip)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
