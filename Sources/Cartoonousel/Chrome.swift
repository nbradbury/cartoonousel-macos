import SwiftUI

/// Title + subtitle on the left; counter, Add and Remove on the right.
@MainActor
struct HeaderView: View {
    /// Extra top inset so the title clears the traffic-light buttons in the hidden title bar.
    var topInset: CGFloat = 12
    @Environment(StripStore.self) private var store

    var body: some View {
        let n = store.strips.count
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cartoonousel")
                    .font(Theme.display(30, weight: .heavy))
                    .tracking(30 * -0.035)
                Text(n > 0 ? "\(n) strip\(n > 1 ? "s" : "") · swipe, drag or ← →" : "a carousel for comic strips")
                    .font(Theme.mono(11))
                    .tracking(11 * 0.08)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.ink)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 8, trailing: 10))
            .background(Theme.paper)
            .padding(EdgeInsets(top: -6, leading: -10, bottom: -8, trailing: -10))
            .allowsHitTesting(false)

            Spacer(minLength: 0)

            if n > 0 {
                HStack(spacing: 10) {
                    Text(String(format: "%02d / %02d", store.index + 1, n))
                        .font(Theme.display(22, weight: .heavy))
                        .tracking(22 * -0.02)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14) // 12 + 2pt border
                        .padding(.vertical, 10)
                        .background(Theme.paper)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
                        .allowsHitTesting(false)
                    Button { store.openPicker() } label: { ShortcutLabel(title: "Add strips", shortcut: "⌘O") }
                        .buttonStyle(InkButtonStyle())
                    Button { store.removeCurrent() } label: { ShortcutLabel(title: "Remove", shortcut: "⌫") }
                        .buttonStyle(InkButtonStyle())
                }
            }
        }
        .padding(.top, 28 + topInset)
        .padding(.horizontal, 36)
    }
}

/// "Drop strips here" over the hero splat, with the pickers at the bottom.
@MainActor
struct EmptyStateView: View {
    let size: CGSize
    @Environment(StripStore.self) private var store

    var body: some View {
        let big = Theme.clamp(40, size.width * 0.066, 108)
        ZStack(alignment: .bottom) {
            // CSS line-height: 0.84 — SwiftUI can't do negative line spacing, so stack fixed-height lines.
            VStack(spacing: 0) {
                ForEach(["Drop", "strips", "here"], id: \.self) { line in
                    Text(line)
                        .font(Theme.display(big, weight: .heavy))
                        .tracking(big * -0.045)
                        .textCase(.uppercase)
                        .fixedSize()
                        .frame(height: big * 0.84)
                }
            }
            .foregroundStyle(Theme.paper)
                .frame(width: size.width, height: size.height * 0.92)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                Text("PNG · JPG · GIF · WEBP — drop one or a whole stack")
                    .font(Theme.mono(12))
                    .tracking(12 * 0.06)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.paper)
                HStack(spacing: 10) {
                    Button { store.openPicker() } label: { ShortcutLabel(title: "Choose files", shortcut: "⌘O", size: 13) }
                        .buttonStyle(InkButtonStyle(filled: true, fontSize: 13, hPad: 16, vPad: 12))
                    Button { store.loadSamples() } label: { Text("Try sample strips") }
                        .buttonStyle(InkButtonStyle(fontSize: 13, hPad: 16, vPad: 12))
                }
            }
            .padding(.bottom, 40)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Thumbnail strip along the bottom edge; the active thumb lifts and gets an underline.
@MainActor
struct FilmstripView: View {
    let maxWidth: CGFloat
    @Environment(StripStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            // Hug the thumbs; only scroll once they outgrow the window.
            ViewThatFits(in: .horizontal) {
                row
                ScrollView(.horizontal, showsIndicators: false) { row }
            }
            .frame(maxWidth: maxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .onChange(of: store.index) { _, _ in
                guard let id = store.current?.id else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var row: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(store.strips.enumerated()), id: \.element.id) { i, strip in
                Thumb(strip: strip, active: i == store.index) { store.go(i) }
                    .id(strip.id)
            }
            AddThumbButton { store.openPicker() }
        }
        // CSS padding 10/12/14 plus the 2pt border that sits outside it
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 16, trailing: 14))
    }

    @MainActor
    private struct Thumb: View {
        let strip: Strip
        let active: Bool
        let action: () -> Void
        @Environment(StripStore.self) private var store

        var body: some View {
            let w = (min(130, max(32, 42 * strip.aspect))).rounded()
            ZStack {
                Hatch(stripe: 4)
                if strip.kind == .image, let image = store.image(for: strip) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: 42)
                        .background(Theme.card)
                }
            }
            .frame(width: w, height: 42)
            .clipped()
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .overlay(alignment: .bottom) {
                if active {
                    Rectangle().fill(Theme.ink)
                        .frame(width: w, height: 4)
                        .offset(y: 10)
                }
            }
            .offset(y: active ? -5 : 0)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.3), value: active)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .help(strip.name)
        }
    }

    private struct AddThumbButton: View {
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text("+")
                    .font(Theme.display(24, weight: .heavy))
                    .foregroundStyle(hovering ? Theme.paper : Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(hovering ? Theme.ink : Theme.paper)
                    .overlay(
                        Rectangle().strokeBorder(Theme.ink,
                                                 style: StrokeStyle(lineWidth: 2, dash: hovering ? [] : [4, 3]))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Add strips")
        }
    }
}

/// Full-window "Let go." shown while files are dragged over the window.
struct DropOverlay: View {
    let visible: Bool
    let count: Int
    let width: CGFloat

    var body: some View {
        let big = Theme.clamp(64, width * 0.13, 220)
        VStack(spacing: 22) {
            Text("Let go.")
                .font(Theme.display(big, weight: .heavy))
                .tracking(big * -0.05)
            Text(count > 0 ? "\(count) \(count == 1 ? "strip" : "strips") incoming" : "drop to add")
                .font(Theme.mono(14))
                .tracking(14 * 0.1)
                .textCase(.uppercase)
        }
        .foregroundStyle(Theme.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
        .opacity(visible ? 1 : 0)
        .animation(.linear(duration: 0.16), value: visible)
        .allowsHitTesting(false)
    }
}
