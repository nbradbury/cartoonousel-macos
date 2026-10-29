import Observation
import SwiftUI

/// mulberry32 — the same PRNG the design uses, so seeded splats come out identical.
struct Mulberry32 {
    private var a: UInt32
    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// Tracks the big "hero" splat behind the current strip and its pop-in / fade-out animation.
@Observable
final class SplatModel {
    struct Hero {
        var seed: UInt32
        var t0: Date
        var ox: Double
        var oy: Double
        var r: Double = 0
        var tOut: Date?
    }

    /// True while a hero is popping in or the previous one is fading; drives the TimelineView.
    private(set) var animating = false
    /// Bumped when an animation finishes so the final frame is drawn at rest.
    private(set) var settledToken = 0

    @ObservationIgnored var hero: Hero?
    @ObservationIgnored var prev: Hero?
    @ObservationIgnored private var generation = 0

    static let popDuration = 0.52
    static let fadeDuration = 0.24

    /// Starts a new hero splat; the old one fades out. `empty` centres it (empty-state layout).
    func newHero(empty: Bool) {
        let now = Date()
        if var old = hero {
            old.tOut = now
            prev = old
        }
        hero = Hero(
            seed: UInt32.random(in: 0..<1_000_000_000),
            t0: now,
            ox: empty ? 0 : Double.random(in: -0.03...0.03),
            oy: empty ? 0 : Double.random(in: -0.025...0.025)
        )
        generation += 1
        let gen = generation
        animating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.popDuration + 0.06) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.animating = false
            self.settledToken += 1
        }
    }
}

/// Full-window canvas: the fixed background splats plus the animated hero splat.
struct SplatBackdrop: View {
    let model: SplatModel
    /// How many of the fixed background splats to draw (0–10).
    let splatAmount: Int
    /// Aspect of the current strip, or nil for the empty state.
    let heroAspect: Double?

    var body: some View {
        let _ = model.settledToken
        TimelineView(.animation(minimumInterval: nil, paused: !model.animating)) { _ in
            Canvas { gc, size in
                SplatPainter.paint(&gc, size: size, model: model, splatAmount: splatAmount,
                                   heroAspect: heroAspect, now: Date())
            }
        }
        .allowsHitTesting(false)
    }
}

enum SplatPainter {
    /// (x fraction, y fraction, radius as fraction of min(w, h), seed)
    static let anchors: [(Double, Double, Double, UInt32)] = [
        (0, 0.52, 0.15, 11), (1, 0.7, 0.17, 23), (0.15, 0.9, 0.065, 37), (0.87, 0.92, 0.075, 41),
        (0.05, 0.36, 0.045, 53), (0.94, 0.32, 0.05, 67), (0.42, 0.04, 0.03, 71), (0.03, 0.97, 0.09, 97),
        (0.6, 0, 0.05, 101), (0.72, 0.13, 0.03, 89),
    ]

    static func heroRadius(size: CGSize, aspect: Double?) -> Double {
        let w = size.width, h = size.height, m = min(w, h)
        guard let a = aspect else { return m * 0.34 }
        let cw = min(0.72 * w, 0.58 * h * a), ch = cw / a
        return max(m * 0.22, min(m * 0.36, max(cw, ch) * 0.5))
    }

    static func paint(_ gc: inout GraphicsContext, size: CGSize, model: SplatModel,
                      splatAmount: Int, heroAspect: Double?, now: Date) {
        let w = size.width, h = size.height, m = min(w, h)
        for (fx, fy, rf, seed) in anchors.prefix(max(0, min(anchors.count, splatAmount))) {
            splat(&gc, cx: fx * w, cy: fy * h, r: rf * m, seed: seed, p: 1)
        }

        let cy = heroAspect == nil ? 0.46 : 0.47

        if let ph = model.prev, let tOut = ph.tOut {
            let q = now.timeIntervalSince(tOut) / SplatModel.fadeDuration
            if q < 1 {
                var faded = gc
                faded.opacity = 1 - q
                let r = ph.r > 0 ? ph.r : heroRadius(size: size, aspect: heroAspect)
                splat(&faded, cx: w / 2 + ph.ox * w, cy: h * cy + ph.oy * h, r: r, seed: ph.seed, p: 1)
            } else {
                model.prev = nil
            }
        }

        if var hero = model.hero {
            let p = min(1, now.timeIntervalSince(hero.t0) / SplatModel.popDuration)
            hero.r = heroRadius(size: size, aspect: heroAspect)
            model.hero = hero
            splat(&gc, cx: w / 2 + hero.ox * w, cy: h * cy + hero.oy * h, r: hero.r, seed: hero.seed, p: p)
        }
    }

    /// One ink splat: a lumpy body, tapered arms with droplets, and scattered drops.
    /// `p` is pop-in progress 0…1 (back-out ease on the body, cubic ease on the spray).
    static func splat(_ gc: inout GraphicsContext, cx: Double, cy: Double, r: Double, seed: UInt32, p: Double) {
        var R = Mulberry32(seed: seed)
        let ink = GraphicsContext.Shading.color(Theme.ink)
        let e = p >= 1 ? 1 : 1 + 2.70158 * pow(p - 1, 3) + 1.70158 * pow(p - 1, 2)
        let eo = p >= 1 ? 1 : 1 - pow(1 - p, 3)
        let body = r * (0.15 + 0.85 * e)

        // Body
        let n = 22 + Int(floor(R.next() * 10))
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let a = Double(i) / Double(n) * .pi * 2 + (R.next() - 0.5) * 0.15
            var rr = 0.72 + R.next() * 0.2
            if R.next() < 0.28 { rr *= 1.1 + R.next() * 0.22 }
            pts.append(CGPoint(x: cx + cos(a) * rr * body, y: cy + sin(a) * rr * body))
        }
        var blob = Path()
        for i in 0...n {
            let p0 = pts[i % n], p1 = pts[(i + 1) % n]
            let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            if i == 0 { blob.move(to: mid) } else { blob.addQuadCurve(to: mid, control: p0) }
        }
        blob.closeSubpath()
        gc.fill(blob, with: ink)

        // Arms
        let arms = 5 + Int(floor(R.next() * 6))
        for _ in 0..<arms {
            let a = R.next() * .pi * 2
            let len = r * (1.05 + R.next() * 0.85)
            let wid = r * (0.045 + R.next() * 0.085)
            let dr = wid * (0.45 + R.next() * 0.5)
            let gap = 1.6 + R.next() * 2.4
            let L = body * 0.6 + (len - r * 0.6) * eo
            let ca = cos(a), sa = sin(a), nx = -sa, ny = ca
            let bx = cx + ca * body * 0.55, by = cy + sa * body * 0.55
            let tx = cx + ca * L, ty = cy + sa * L
            let kx = cx + ca * L * 0.82, ky = cy + sa * L * 0.82

            var arm = Path()
            arm.move(to: CGPoint(x: bx + nx * wid, y: by + ny * wid))
            arm.addQuadCurve(to: CGPoint(x: tx, y: ty),
                             control: CGPoint(x: kx + nx * wid * 0.28, y: ky + ny * wid * 0.28))
            arm.addQuadCurve(to: CGPoint(x: bx - nx * wid, y: by - ny * wid),
                             control: CGPoint(x: kx - nx * wid * 0.28, y: ky - ny * wid * 0.28))
            arm.closeSubpath()
            gc.fill(arm, with: ink)

            gc.fill(circle(x: tx - ca * wid * 0.2, y: ty - sa * wid * 0.2, r: wid * 0.32), with: ink)
            if eo > 0.35 {
                let dd = L + dr * gap
                gc.fill(circle(x: cx + ca * dd, y: cy + sa * dd, r: dr * eo), with: ink)
            }
        }

        // Drops
        let drops = 14 + Int(floor(R.next() * 16))
        for _ in 0..<drops {
            let a = R.next() * .pi * 2
            let d = r * (0.95 + pow(R.next(), 0.8) * 1.3)
            let dr = r * (0.008 + pow(R.next(), 2.2) * 0.065)
            let elong = R.next() < 0.3
            let dd = body * 0.7 + (d - r * 0.7) * eo
            let s = dr * (0.3 + 0.7 * eo)
            let x = cx + cos(a) * dd, y = cy + sin(a) * dd
            if elong {
                let oval = Path(ellipseIn: CGRect(x: -s * 1.9, y: -s * 0.9, width: s * 3.8, height: s * 1.8))
                    .applying(CGAffineTransform(rotationAngle: a).concatenating(CGAffineTransform(translationX: x, y: y)))
                gc.fill(oval, with: ink)
            } else {
                gc.fill(circle(x: x, y: y, r: s), with: ink)
            }
        }
    }

    private static func circle(x: Double, y: Double, r: Double) -> Path {
        let r = max(0, r)
        return Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}
