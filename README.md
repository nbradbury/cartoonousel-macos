# <img src="docs/icon.png" alt="" width="48" align="absmiddle"> Cartoonousel (macOS)

A native SwiftUI carousel for comic strips set on an ink-splat backdrop.

<img width="1336" height="976" alt="1" src="https://github.com/user-attachments/assets/54248e56-a4b9-4484-a86e-3b055a3082e4" />
<img width="1336" height="976" alt="2" src="https://github.com/user-attachments/assets/3f4b3a42-a905-4715-aabd-0f837668d873" />


## Run

Needs macOS 14+ and Xcode 15+.

- **Xcode:** open `Package.swift`, pick the `Cartoonousel` scheme with *My Mac* as the destination, then Run.
- **Terminal:** `swift run -c release`

## Fonts (optional)

The design uses **Bricolage Grotesque** and **JetBrains Mono**. If they're installed system-wide, the app picks them up. You can also drop the `.ttf` files into `Sources/Cartoonousel/Resources/Fonts/` and rebuild. Without them it falls back to SF Pro and SF Mono.

## What's where

| File | Contents |
|---|---|
| `CartoonouselApp.swift` | App, single window (hidden title bar), menus, Settings |
| `StripStore.swift` | Strips, current index, import, samples, remove, persistence |
| `Splats.swift` | mulberry32 PRNG, the splat painter, hero pop-in/fade |
| `CarouselView.swift` | Layout math, slides, drag/flick, tilt "wobble" |
| `Chrome.swift` | Header, empty state, filmstrip, "Let go." drop overlay |
| `ContentView.swift` | Composition, drop delegate, key and scroll-wheel handling |
| `Theme.swift` | Colours, fonts, hatching, ink buttons |

## Mapping from the design

- **Navigation:** drag (flicks move one strip), wheel/trackpad (one strip per gesture), ← → ↑ ↓ / space / Home / End, clicking a neighbour, or clicking a filmstrip thumb.
- **Full screen:** click the current strip to show it full screen; click again or press Esc to close. The arrow keys still page through strips.
- **Import:** ⌘O / *Add strips*, or drop files anywhere on the window. Files are sorted by name, numbers in order ("strip-2" before "strip-10").
- **Cartoons:** *Add Photos* (header) or *Turn photos into cartoons* (empty state) turns photos into black-and-white cartoons as they're imported, using a bundled Core ML conversion of AnimeGANv2 (`celeba_distill` weights from [bryandlee/animegan2-pytorch](https://github.com/bryandlee/animegan2-pytorch), MIT; see `Resources/Cartoonizer-LICENSE.txt`). Photos run at up to 1024 px, about 0.3 s each on the CPU. Only the cartoon is kept; re-import with ⌘O for the original.
- **Samples:** *Try sample strips* imports the comics bundled in `Sources/Cartoonousel/Resources/SampleStrips/`, the same way as importing files.
- **Remove:** ⌫ / ⌦ / ⌘⌫ / *Remove*. This also deletes the app's copy of the image.
- **Remove all:** ⌥⌘⌫ / *Strip → Remove All Strips…*, after a confirmation alert. This deletes the app's copies of every image.
- **Tweaks:** the design's props (splats, wobble, auto-advance, filmstrip) live in **Settings (⌘,)**.
- **Persistence:** the design used `localStorage`. Here, imported images are copied into `~/Library/Application Support/Cartoonousel/Strips/`, and the list and index go in `state.json` beside that folder.
- The PRNG and hash are bit-exact ports, so the background splats and per-strip tilts match the web version.
- **Deviation:** the header sits 12 pt lower than in the design so the title clears the window's traffic-light buttons.
