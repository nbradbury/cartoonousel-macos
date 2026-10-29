import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Prefs {
    static let splatAmount = "splatAmount"
    static let wobble = "wobble"
    static let autoAdvance = "autoAdvance"
    static let showFilmstrip = "showFilmstrip"
}

@MainActor
struct ContentView: View {
    @Environment(StripStore.self) private var store
    @AppStorage(Prefs.splatAmount) private var splatAmount = 7.0
    @AppStorage(Prefs.autoAdvance) private var autoAdvance = 0.0
    @AppStorage(Prefs.showFilmstrip) private var showFilmstrip = true

    @State private var splats = SplatModel()
    @State private var input = InputMonitor()
    @State private var dropTargeted = false
    @State private var dropCount = 0
    @State private var enteredFullScreen = false

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    /// Changes whenever the hero splat should be re-thrown (new current strip, or empty).
    private var heroKey: String { store.current?.id ?? "empty" }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let empty = store.strips.isEmpty
            ZStack {
                Theme.paper

                SplatBackdrop(model: splats, splatAmount: Int(splatAmount.rounded()),
                              heroAspect: store.current?.aspect)

                if empty {
                    EmptyStateView(size: size)
                } else {
                    CarouselView(size: size)
                }

                if !empty && showFilmstrip {
                    VStack {
                        Spacer()
                        FilmstripView(maxWidth: max(100, size.width - 72))
                            .padding(.bottom, 26)
                    }
                }

                VStack {
                    HeaderView()
                    Spacer()
                }

                if store.viewing, let strip = store.current {
                    StripViewer(strip: strip).transition(.opacity)
                }

                DropOverlay(visible: dropTargeted, count: dropCount, width: size.width)
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeOut(duration: 0.2), value: store.viewing)
        }
        .ignoresSafeArea()
        .background(WindowReader { input.window = $0 })
        .onDrop(of: [.fileURL], delegate: StripDropDelegate(store: store, targeted: $dropTargeted, count: $dropCount))
        .onAppear {
            input.install(store: store)
            splats.newHero(empty: store.strips.isEmpty)
        }
        .onDisappear { input.uninstall() }
        .onChange(of: heroKey) { _, _ in splats.newHero(empty: store.strips.isEmpty) }
        .onChange(of: store.viewing) { _, viewing in setFullScreen(viewing) }
        .onReceive(ticker) { _ in store.autoAdvanceIfIdle(seconds: autoAdvance) }
        .frame(minWidth: 720, minHeight: 480)
    }

    /// Enters macOS full screen for the viewer, and leaves it afterwards only if the viewer entered it.
    private func setFullScreen(_ on: Bool) {
        guard let window = input.window else { return }
        let isFull = window.styleMask.contains(.fullScreen)
        if on, !isFull {
            enteredFullScreen = true
            window.toggleFullScreen(nil)
        } else if !on, enteredFullScreen {
            enteredFullScreen = false
            if isFull { window.toggleFullScreen(nil) }
        }
    }
}

// MARK: - Drag & drop

struct StripDropDelegate: DropDelegate {
    let store: StripStore
    @Binding var targeted: Bool
    @Binding var count: Int

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        count = info.itemProviders(for: [.fileURL]).count
        targeted = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.add(url) }
                group.leave()
            }
        }
        let store = store
        group.notify(queue: .main) {
            MainActor.assumeIsolated { store.addFiles(box.urls) }
        }
        return true
    }
}

/// Collects URLs from item-provider callbacks, which may arrive on any thread.
final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func add(_ url: URL) {
        lock.lock(); storage.append(url); lock.unlock()
    }

    var urls: [URL] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

// MARK: - Keyboard & scroll wheel

/// Window-level keys and wheel paging, as in the design: ← → ↑ ↓ space, Home/End, ⌫/⌦,
/// and the wheel/trackpad pages one strip per gesture.
@MainActor
final class InputMonitor {
    weak var window: NSWindow?
    private var monitors: [Any] = []
    private var wheelLocked = false
    private var wheelAccum: CGFloat = 0
    private var wheelReset: DispatchWorkItem?

    func install(store: StripStore) {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.handlesEvents(in: event) else { return event }
                return self.key(event, store: store) ? nil : event
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.handlesEvents(in: event) else { return event }
                return self.wheel(event, store: store) ? nil : event
            }
        }) { monitors.append(m) }
    }

    func uninstall() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handlesEvents(in event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        return window.attachedSheet == nil
    }

    private func key(_ e: NSEvent, store: StripStore) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty, !store.strips.isEmpty else { return false }
        switch e.keyCode {
        case 124, 125, 49: store.step(1)          // → ↓ space
        case 123, 126: store.step(-1)             // ← ↑
        case 115: store.first()                   // Home
        case 119: store.last()                    // End
        case 51, 117: store.removeCurrent()       // ⌫ ⌦
        case 53 where store.viewing: store.viewing = false  // Esc
        default: return false
        }
        return true
    }

    private func wheel(_ e: NSEvent, store: StripStore) -> Bool {
        guard !store.strips.isEmpty else { return false }
        // AppKit deltas point the opposite way to the web's; mouse wheels report lines, not points.
        let scale: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 40
        let dx = -e.scrollingDeltaX * scale, dy = -e.scrollingDeltaY * scale
        let d = abs(dx) > abs(dy) ? dx : dy

        wheelReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.wheelLocked = false
                self?.wheelAccum = 0
            }
        }
        wheelReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: reset)

        if wheelLocked { return true }
        wheelAccum += d
        if abs(wheelAccum) > 36 {
            store.step(wheelAccum > 0 ? 1 : -1)
            wheelLocked = true
            wheelAccum = 0
        }
        return true
    }
}

/// Reports the hosting NSWindow so the monitors only act on the carousel window.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onWindow = onWindow
    }

    final class TrackingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
