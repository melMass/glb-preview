# GLB Quick Look

macOS Quick Look extension for previewing `.glb` (glTF Binary) files. Press spacebar on any `.glb` file in Finder to get an interactive 3D preview with orbit, pan and zoom.

![Finder preview of a shoe model](screenshots/finder-preview.png)
![Animation controls with scrubber](screenshots/animation-controls.png)

## Features

- Spacebar preview of `.glb` files in Finder
- Interactive 3D viewer (orbit, pan, zoom)
- Draco mesh compression support
- Render modes: lit (PBR), albedo, normals, UVs, wireframe
- Animation playback with scrubber and pause
- Auto-rotate toggle
- Camera reset
- Thumbnail generation for Finder icons
- Fully offline (no network required)

## Install (pre-built)

1. Download [`GLBPreview.zip` from the latest release](https://github.com/DeepARSDK/glb-preview/releases/latest)
2. Unzip and drag `GLBPreview.app` to `/Applications`
3. Right-click the app > **Open**
4. macOS will show a warning that it cannot verify the app. Click **OK**, then go to **System Settings > Privacy & Security** and click **Open Anyway**:

![Gatekeeper prompt in Privacy & Security settings](screenshots/gatekeeper.png)

5. The app registers the Quick Look extensions on first launch — you're done

## Requirements

- macOS 13.0+

## Build from source

If you prefer to build from source:

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
cd glb-preview
xcodegen generate

# Open in Xcode
open GLBPreview.xcodeproj
```

In Xcode:

1. Select the **GLBPreview** scheme in the toolbar
2. Set your signing team on all three targets (GLBPreview, PreviewExtension, ThumbnailExtension) under **Signing & Capabilities**
3. Build with **Cmd+B**

Then install:

```bash
# Copy to Applications and reset Quick Look caches
rm -rf /Applications/GLBPreview.app
cp -R ~/Library/Developer/Xcode/DerivedData/GLBPreview-*/Build/Products/Debug/GLBPreview.app /Applications/
qlmanage -r && qlmanage -r cache
```

Open the app once to register the extensions:

```bash
open /Applications/GLBPreview.app
```

## Usage

- Select a `.glb` file in Finder and press **Space** to preview
- **Left-drag** to orbit
- **Scroll** to zoom
- Toolbar buttons (top right): render mode (cycles lit/albedo/normal/uv/wire), auto-rotate, camera reset
- Animation controls appear at the bottom when the model has animations

## Set as default app for .glb files

Right-click any `.glb` file > **Get Info** > **Open With** > select **GLBPreview** > **Change All**

## Project structure

```
glb-preview/
├── project.yml                              # XcodeGen project spec
├── GLBPreview/                              # Host app (minimal)
│   ├── GLBPreviewApp.swift
│   └── ContentView.swift
├── PreviewExtension/                        # Quick Look preview (spacebar)
│   ├── PreviewViewController.swift
│   ├── viewer.html                          # model-viewer based 3D viewer
│   └── model-viewer.min.js                  # Bundled model-viewer v4.0.0
└── ThumbnailExtension/                      # Finder icon thumbnails
    └── ThumbnailProvider.swift
```

## Debugging Quick Look extensions

macOS has two Quick Look systems and the tooling is confusing:

**Legacy system** (`qlmanage`, QL generator plugins): The old `.qlgenerator` bundle approach. `qlmanage -m plugins` only lists these — it will **not** show modern extension-based providers. Most online guides reference this system.

**Modern system** (ExtensionKit, `pluginkit`): What this project uses — `com.apple.quicklook.preview` / `com.apple.quicklook.thumbnail` app extension points. Registered via the host app, managed by ExtensionKit.

### Useful commands

```bash
# List registered QL preview extensions (modern system)
pluginkit -m -p com.apple.quicklook.preview
pluginkit -m -p com.apple.quicklook.thumbnail

# Check what UTI macOS assigns to a file
# If this shows "dyn.xxxxx" your UTImportedTypeDeclarations is missing/wrong
mdls -name kMDItemContentType some_file.glb

# Force-trigger a preview (works for both legacy and modern)
qlmanage -p some_file.glb

# Force-generate a thumbnail
qlmanage -t some_file.glb -s 512

# Reset QL caches (still needed after every rebuild)
qlmanage -r && qlmanage -r cache

# Console.app — filter for any of:
#   "quicklook", "extensionkit", "com.laurie.GLBPreview", "PreviewExtension"
```

### Common pitfalls

- **Extension shows in System Settings but doesn't trigger**: Almost always a UTI mismatch. The host app must declare `UTImportedTypeDeclarations` mapping `.glb` → `org.khronos.glb`, otherwise macOS assigns a dynamic UTI and the extension never matches.
- **macOS caches aggressively**: Always `qlmanage -r` after rebuild. If truly stuck: `killall Finder`, or log out and back in.
- **Sandbox blocks file access**: The extension runs sandboxed. It receives a security-scoped URL from QuickLook — call `url.startAccessingSecurityScopedResource()` if file reads fail silently.
- **Code signing matters**: Unsigned or ad-hoc signed extensions may not load. Check Console for `extensionkit` errors.
- **In-view buttons feel laggy (~1s)**: Use `pointerdown`, not `mousedown`/`click`, for controls inside the preview. The QL WKWebView synthesizes legacy mouse events with a gesture-disambiguation delay (~650 ms measured); pointer events bypass it entirely.

### Viewer JS logging

`PreviewViewController` bridges the web view's `console` (and uncaught errors / promise rejections) to the unified log, so the viewer's JS is observable without attaching a debugger:

```bash
# via the toolkit
overlay use toolkit.nu
watch-logs                # --level info by default

# or directly
log stream --predicate 'subsystem == "com.laurie.GLBPreview.PreviewExtension"' --level info
```

`console.error` → `.error`, `console.warn` → `.default`, `console.log`/`.info` → `.info`. Note `.info` messages need `--level info` to appear.

## Known limitations

- Thumbnail generation does not support Draco-compressed models (shows default icon)
