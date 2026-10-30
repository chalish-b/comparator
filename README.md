<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon-dark.png">
    <img src="docs/icon-light.png" width="128" alt="">
  </picture>
</p>

<h1 align="center">Comparator</h1>

<p align="center">Small and fast image comparison tool for macOS.</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.webp">
  <img src="docs/screenshot-light.webp" alt="Comparator in split view, with a low-resolution image on the left and its upscaled version on the right">
</picture>

- Switch between images without losing your place.
- Split view, side by side or stacked, with a draggable divider.
- Difference view to highlight the pixels that don't match.
- Noise view that shows faint color patches and fine detail.
- Move, nudge, or scale an image to line it up with another.
- File and format details for each image, side by side when comparing two.
- Images reload automatically when they change on disk.

## Install

Requires macOS 15 or later. Download `Comparator-<version>.dmg` from the [latest release](https://github.com/chalish-b/comparator/releases/latest), open it, and drag Comparator into Applications.

Comparator isn't signed with an Apple developer certificate, so the first time you open it, macOS says it can't verify the app. To allow it, run this in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Comparator.app
```

Or click **Done**, open **System Settings → Privacy & Security**, scroll down to the message about Comparator, and click **Open Anyway**.

You need to do this again after downloading a new version.

## Build

Requires the Xcode Command Line Tools.

```sh
./scripts/build-app.sh --release            # builds build/Comparator.app
./scripts/build-app.sh --release --install  # also installs to ~/Applications and registers it with Finder
```

Quit the app before reinstalling.

The app icon is `Resources/AppIcon.icon`, made with Icon Composer. After editing it, run `./scripts/compile-icon.sh` (requires Xcode) and commit the updated `Resources/AppIcon/` and `docs/icon-*.png`.

## Opening images

- Select images in Finder → right-click → **Open With → Comparator**, or drop them on the Dock icon. Each opens as a new set (window or tab).
- Drop images or folders onto a window to add them to that set.
- **⌘T** new empty set, **⌘O** open as a new set, **⇧⌘O** add to the current set.
- Images that change on disk reload automatically, keeping your view.

## Command line

To open images from a terminal, link the `comparator` command into a folder on your `PATH`:

```sh
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/Comparator.app/Contents/MacOS/Comparator /usr/local/bin/comparator
```

Then open images or folders as a new set, optionally with a view to start in:

```sh
comparator input.png upscaled.png
comparator renders/ --split --zoom 400 --center 0.5,0.3
```

| Option | Effect |
| --- | --- |
| `--split`, `--stacked` | Split view, side by side or stacked |
| `--difference` | Difference view |
| `--swap` | Swap the split sides |
| `--show A[,B]` | Show image A, or images A and B with B as the current one |
| `--zoom N` | Zoom to N percent (default: fit) |
| `--center X,Y` | Center the view on this point of the first image, from `0,0` (top left) to `1,1` (bottom right) |
| `--divider F` | Split divider position, from 0 to 1 |
| `--pixels`, `--smooth` | Pixels or smooth filtering |

`comparator --help` lists these in the terminal.

## Shortcuts

| Key | Action |
| --- | --- |
| 1–9 | Show image |
| Tab | Flip to the last viewed image; in split view, swap sides |
| ↑ ↓ | Previous / next image |
| S | Split view (lower-numbered image on the left) |
| ⇧S | Rotate split: side by side / stacked (lower-numbered image on top) |
| D | Difference view |
| N | Noise view |
| [ ] | Difference gain, or noise view strength |
| , . | Noise view radius |
| P | Pixels / smooth filtering |
| 0 or F | Fit |
| A | Actual pixels (100%) |
| + − | Zoom in / out |
| Double-click | Fit / 100% |
| Drag, two-finger scroll | Pan |
| Pinch, mouse wheel | Zoom |
| Hold ⌥ | Alignment overlay of the current image over the last viewed one; in split view, of the image under the pointer over the other |
| ⌥ drag | Move the current image |
| ⌥ arrows | Nudge by 1 px (⇧ for 0.1 px) |
| ⌥ scroll / pinch | Scale the current image |
| ⌥R | Reset alignment |
| O | Alignment overlay style: difference / onion skin |
| ⌫ | Remove the image from the set |
| I | Show / hide image info |
| H | Show / hide shortcuts |

100% zoom means one pixel of the highest-resolution image per screen pixel. Smaller images (e.g. an upscaler's input) are scaled to match it.
