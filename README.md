# ImgCompare

A small macOS app for comparing images: switch between them with number keys while zoom and pan stay put, compare two side by side with a split slider, or look at their difference.

## Build

Requires the Xcode Command Line Tools.

```sh
./scripts/build-app.sh            # builds build/ImgCompare.app
./scripts/build-app.sh --install  # also installs to ~/Applications and registers it with Finder
```

Quit the app before reinstalling.

## Opening images

- Select images in Finder → right-click → **Open With → ImgCompare**, or drop them on the Dock icon. Each opens as a new set (window or tab).
- Drop images or folders onto a window to add them to that set.
- **⌘N** new empty set, **⌘O** open as a new set, **⇧⌘O** add to the current set.
- Images that change on disk reload automatically, keeping your view.

## Shortcuts

| Key | Action |
| --- | --- |
| 1–9 | Show image |
| Tab | Flip to the last viewed image |
| ← → | Previous / next image |
| S | Split view (lower-numbered image on the left) |
| D | Difference view |
| N | Noise view |
| ↑ ↓ or [ ] | Difference gain, or noise view strength |
| , . | Noise view radius |
| P | Pixels / smooth filtering |
| 0 or F | Fit |
| A | Actual pixels (100%) |
| + − | Zoom in / out |
| Double-click | Fit / 100% |
| Drag, two-finger scroll | Pan |
| Pinch, mouse wheel | Zoom |
| Hold ⌥ | Alignment overlay of the current image over the last viewed one |
| ⌥ drag | Move the current image |
| ⌥ arrows | Nudge by 1 px (⇧ for 10 px) |
| ⌥ scroll / pinch | Scale the current image |
| ⌥R | Reset alignment |
| O | Alignment overlay style: difference / onion skin |
| ⌫ | Remove the image from the set |
| H | Show / hide shortcuts |

100% zoom means one pixel of the highest-resolution image per screen pixel. Smaller images (e.g. an upscaler's input) are scaled to match it.

## Noise view

Shows faint color patches that are hard to see by eye: each image minus a heavy blur, amplified around mid-gray. Truly flat areas come out solid gray, mottling and blotches show up as colored blobs, and lines and edges as bright or dark outlines. It works in every view, so you can flip between an original and its cleanup, or put them in a split, with the same zoom.

Strength defaults to 25× and the radius to 12 px. The radius is in the first image's pixels, so an upscaled image gets a proportionally larger blur and both show the same scale of patches. A smaller radius shows finer grain; a larger one shows bigger blotches.
