import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

struct Strip: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// width / height
    var aspect: Double
    /// File name inside the library folder. Optional because strips saved by older builds
    /// (placeholder samples) have none; `load()` drops those.
    var fileName: String?
}

/// The carousel's model: the list of strips, the current index and the live drag position.
/// Persists to ~/Library/Application Support/Cartoonousel (state.json + copies of imported images),
/// replacing the design's localStorage("cartoonousel.v1").
@MainActor
@Observable
final class StripStore {
    private(set) var strips: [Strip] = []
    private(set) var index = 0
    /// Fractional carousel position while the user is dragging; nil otherwise.
    var dragPos: Double?

    /// Last time the user navigated; auto-advance waits for this to go quiet.
    @ObservationIgnored var lastAct = Date()
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]

    private let folder: URL
    private var imagesFolder: URL { folder.appendingPathComponent("Strips", isDirectory: true) }
    private var stateURL: URL { folder.appendingPathComponent("state.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Cartoonousel", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        load()
    }

    var current: Strip? { strips.indices.contains(index) ? strips[index] : nil }

    // MARK: - Navigation

    func go(_ i: Int) {
        guard !strips.isEmpty else { return }
        lastAct = Date()
        let clamped = max(0, min(strips.count - 1, i))
        if clamped != index { index = clamped; save() }
    }

    func step(_ delta: Int) { go(index + delta) }
    func first() { go(0) }
    func last() { go(strips.count - 1) }

    /// Ends a drag: clears the live position and settles on `target`.
    func endDrag(at target: Int) {
        dragPos = nil
        lastAct = Date()
        let clamped = max(0, min(max(0, strips.count - 1), target))
        if clamped != index { index = clamped; save() }
    }

    /// Auto-advance tick (wraps around).
    func autoAdvanceIfIdle(seconds: Double) {
        let n = strips.count
        guard seconds > 0, n > 1, dragPos == nil, Date().timeIntervalSince(lastAct) > seconds else { return }
        lastAct = Date()
        index = (index + 1) % n
        save()
    }

    // MARK: - Adding & removing

    func openPicker() {
        let panel = NSOpenPanel()
        panel.title = "Add strips"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .image]
        guard panel.runModal() == .OK else { return }
        addFiles(panel.urls)
    }

    /// Imports image files, ordered by name with numeric awareness ("strip-2" before "strip-10"),
    /// and jumps to the first new one.
    func addFiles(_ urls: [URL]) {
        let images = urls
            .filter { url in
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                    ?? UTType(filenameExtension: url.pathExtension)
                return type?.conforms(to: .image) ?? false
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var added: [Strip] = []
        for url in images {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let size = Self.pixelSize(of: url), size.width > 0, size.height > 0 else { continue }

            let id = "img-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(5).lowercased())"
            let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
            let fileName = "\(id).\(ext)"
            do {
                try FileManager.default.copyItem(at: url, to: imagesFolder.appendingPathComponent(fileName))
            } catch {
                continue
            }
            added.append(Strip(id: id, name: url.lastPathComponent,
                               aspect: size.width / size.height, fileName: fileName))
        }
        append(added)
    }

    /// Imports the strips bundled in Resources/SampleStrips, like any other files.
    func loadSamples() {
        guard let folder = Bundle.module.url(forResource: "SampleStrips", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        addFiles(urls)
    }

    func removeCurrent() {
        guard let strip = current else { return }
        if let file = strip.fileName {
            try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(file))
        }
        imageCache[strip.id] = nil
        strips.remove(at: index)
        index = max(0, min(index, strips.count - 1))
        save()
    }

    /// Asks for confirmation, then removes every strip along with the app's copies of the images.
    func confirmRemoveAll() {
        guard !strips.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Remove all strips?"
        alert.informativeText = "This removes all \(strips.count) strips and deletes the app's copies of their images."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove All").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for file in strips.compactMap(\.fileName) {
            try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(file))
        }
        imageCache.removeAll()
        strips.removeAll()
        index = 0
        save()
    }

    private func append(_ list: [Strip]) {
        guard !list.isEmpty else { return }
        lastAct = Date()
        let start = strips.count
        strips.append(contentsOf: list)
        index = start
        save()
    }

    // MARK: - Images

    func image(for strip: Strip) -> NSImage? {
        if let hit = imageCache[strip.id] { return hit }
        guard let file = strip.fileName,
              let image = NSImage(contentsOf: imagesFolder.appendingPathComponent(file)) else { return nil }
        imageCache[strip.id] = image
        return image
    }

    private static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        // EXIF orientations 5–8 are rotated a quarter turn.
        if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    // MARK: - Persistence

    private struct Saved: Codable {
        var strips: [Strip]
        var index: Int
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        let fm = FileManager.default
        strips = saved.strips.filter { strip in
            guard let file = strip.fileName else { return false }
            return fm.fileExists(atPath: imagesFolder.appendingPathComponent(file).path)
        }
        index = strips.isEmpty ? 0 : max(0, min(saved.index, strips.count - 1))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(strips: strips, index: index)) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
