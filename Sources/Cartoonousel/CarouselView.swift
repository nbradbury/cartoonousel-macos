import AppKit
import SwiftUI

/// Horizontal layout of the strips: the current one full size, neighbours at 50%, the rest at 38%.
struct CarouselLayout {
    let widths: [Double]
    let gap: Double
    let viewWidth: Double

    init(strips: [Strip], size: CGSize) {
        widths = strips.map { min(0.72 * size.width, 0.58 * size.height * $0.aspect) }
        gap = 0.035 * size.width + 30
        viewWidth = size.width
    }

    var count: Int { widths.count }

    /// Offsets from centre and scales with strip `c` in the middle.
    func layout(centeredOn c: Int) -> (x: [Double], scale: [Double]) {
        let n = count
        var x = [Double](repeating: 0, count: n), sc = [Double](repeating: 1, count: n)
        guard n > 0 else { return (x, sc) }
        var edge = widths[c] / 2
        if c + 1 < n {
            for i in (c + 1)..<n {
                let s = i == c + 1 ? 0.5 : 0.38
                x[i] = edge + gap + widths[i] * s / 2
                edge = x[i] + widths[i] * s / 2
                sc[i] = s
            }
        }
        edge = -widths[c] / 2
        if c > 0 {
            for i in stride(from: c - 1, through: 0, by: -1) {
                let s = i == c - 1 ? 0.5 : 0.38
                x[i] = edge - gap - widths[i] * s / 2
                edge = x[i] - widths[i] * s / 2
                sc[i] = s
            }
        }
        return (x, sc)
    }

    /// Distance from strip `c` to its nearest neighbour — how far a drag moves one step.
    func spacing(at c: Int) -> Double {
        let l = layout(centeredOn: c)
        if c + 1 < count { return abs(l.x[c + 1]) }
        if c > 0 { return abs(l.x[c - 1]) }
        return viewWidth * 0.5
    }

    /// Positions at a fractional carousel position (interpolates between neighbouring layouts).
    func positions(at pos: Double) -> (x: [Double], scale: [Double]) {
        let n = count
        guard n > 0 else { return ([], []) }
        let c0 = max(0, min(n - 1, Int(floor(pos))))
        let c1 = min(c0 + 1, n - 1)
        let f = pos - Double(c0)
        let l0 = layout(centeredOn: c0)
        if c1 == c0 || f < 0 {
            // Rubber-banding past either end: slide everything.
            let sp0 = spacing(at: c0)
            return (l0.x.map { $0 - f * sp0 }, l0.scale)
        }
        let l1 = layout(centeredOn: c1)
        let x = zip(l0.x, l1.x).map { $0 + ($1 - $0) * f }
        let s = zip(l0.scale, l1.scale).map { $0 + ($1 - $0) * f }
        return (x, s)
    }
}

/// The design's string hash (imul by 2654435761), used for each strip's resting tilt.
func stripHash(_ s: String) -> UInt32 {
    var h: UInt32 = 0
    for c in s.utf16 { h = (h ^ UInt32(c)) &* 2_654_435_761 }
    return h
}

@MainActor
struct CarouselView: View {
    let size: CGSize
    @Environment(StripStore.self) private var store
    @AppStorage(Prefs.wobble) private var wobble = true
    @State private var dragStart: Int?
    @GestureState private var dragging = false

    private static let settle = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.64)

    var body: some View {
        let strips = store.strips
        let layout = CarouselLayout(strips: strips, size: size)
        let pos = store.dragPos ?? Double(store.index)
        let placed = layout.positions(at: pos)

        ZStack {
            ForEach(Array(strips.enumerated()), id: \.element.id) { i, strip in
                let rel = Double(i) - pos
                let ar = abs(rel)
                let cr = max(-1, min(1, rel))
                let tilt = (Double(stripHash(strip.id) % 1000) / 1000 - 0.5) * 2.8
                let rot = wobble ? tilt * (1 - min(ar, 1)) + cr * 3 : 0

                SlideCard(strip: strip, number: i + 1, width: layout.widths[i],
                          captionOpacity: max(0, 1 - ar * 2.5))
                    .scaleEffect(placed.scale[i])
                    .rotationEffect(.degrees(rot))
                    .position(x: size.width / 2 + placed.x[i], y: size.height * 0.47)
                    .opacity(ar > 2.6 ? 0 : 1)
                    .zIndex(100 - (ar * 10).rounded())
                    .onTapGesture {
                        if i != store.index { store.go(i) } else { store.viewing = true }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .animation(store.dragPos == nil ? Self.settle : nil, value: pos)
        .animation(store.dragPos == nil ? Self.settle : nil, value: wobble)
        .animation(store.dragPos == nil ? Self.settle : nil, value: strips.map(\.id))
        .gesture(drag(layout: layout))
        .onChange(of: dragging) { _, active in
            // A cancelled drag (focus loss, ⌘-Tab…) never reaches onEnded — settle it here.
            if !active, let p = store.dragPos {
                dragStart = nil
                store.endDrag(at: Int(floor(p + 0.5)))
            }
        }
        .modifier(GrabCursor(grabbing: store.dragPos != nil))
    }

    private func drag(layout: CarouselLayout) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                let n = Double(store.strips.count)
                guard n > 0 else { return }
                if dragStart == nil { dragStart = store.index }
                let start = Double(dragStart ?? store.index)
                var p = start - value.translation.width / layout.spacing(at: dragStart ?? store.index)
                if p < 0 { p *= 0.3 }
                if p > n - 1 { p = n - 1 + (p - (n - 1)) * 0.3 }
                store.dragPos = p
            }
            .onEnded { value in
                let start = dragStart ?? store.index
                dragStart = nil
                let pos = store.dragPos ?? Double(start)
                var target = Int(floor(pos + 0.5))
                // A flick (> 0.45 px/ms, as in the design) always moves on by one.
                let v = value.velocity.width / 1000
                if abs(v) > 0.45 {
                    target = v < 0 ? Int(floor(pos)) + 1 : Int(ceil(pos)) - 1
                }
                store.endDrag(at: target)
            }
    }
}

/// One strip in the carousel: the framed card with its ring, plus the caption below.
@MainActor
struct SlideCard: View {
    let strip: Strip
    let number: Int
    let width: Double
    let captionOpacity: Double
    @Environment(StripStore.self) private var store

    var body: some View {
        let height = width / max(strip.aspect, 0.01)
        content
            .padding(4)
            .frame(width: width, height: height)
            .background(Theme.card)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 4))
            .overlay(alignment: .bottom) {
                caption
                    .fixedSize()
                    .alignmentGuide(.bottom) { d in d[.top] - 30 }
                    .opacity(captionOpacity)
                    .animation(.linear(duration: 0.3), value: captionOpacity)
            }
            // box-shadow: 0 0 0 12px paper, 0 0 0 15px ink
            .padding(12)
            .background(Theme.paper)
            .padding(3)
            .background(Theme.ink)
    }

    @ViewBuilder private var content: some View {
        if let image = store.image(for: strip) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Hatch()
        }
    }

    private var caption: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", number)).font(Theme.mono(12, weight: .semibold))
            Text(strip.name).font(Theme.mono(12))
        }
        .tracking(12 * 0.04)
        .lineLimit(1)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12) // 10 + 2pt border (CSS border sits outside the padding)
        .padding(.vertical, 8)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
    }
}

/// The current strip filling the window. Click or Esc closes it; the arrow keys still page.
struct StripViewer: View {
    let strip: Strip
    @Environment(StripStore.self) private var store

    var body: some View {
        ZStack {
            Theme.paper
            if let image = store.image(for: strip) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.viewing = false }
    }
}

/// Open hand over the carousel, closed hand while dragging.
struct GrabCursor: ViewModifier {
    let grabbing: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            content.pointerStyle(grabbing ? .grabActive : .grabIdle)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    /// macOS 14: set the cursor directly (push/pop gets unbalanced when the view disappears).
    private func fallback(_ content: Content) -> some View {
        content
            .onContinuousHover { phase in
                if case .active = phase {
                    (grabbing ? NSCursor.closedHand : NSCursor.openHand).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onChange(of: grabbing) { _, now in
                (now ? NSCursor.closedHand : NSCursor.openHand).set()
            }
            .onDisappear { NSCursor.arrow.set() }
    }
}
