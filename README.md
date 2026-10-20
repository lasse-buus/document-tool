# Document Tool

A menu bar app for macOS. Drag any file, hold your trigger key, and a ring of actions appears under the cursor. Drop the file on a slice to run that action. Drop it in the middle, or let go of the key, to cancel.

## Download

Get the latest `Document-Tool-x.y.z.zip` from the [Releases](../../releases/latest) page. Unzip it and drag **Document Tool** into Applications. It needs macOS 14 Sonoma or newer and runs on both Apple silicon and Intel Macs.

The app isn't signed with an Apple Developer ID yet, so macOS blocks it the first time you open it:

1. Open it once. macOS says it can't verify the developer. Click **Done**.
2. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Document Tool.

Or run this once in Terminal instead:

```bash
xattr -dr com.apple.quarantine "/Applications/Document Tool.app"
```

## Build from source

You need Xcode (or the Xcode Command Line Tools) on macOS 14 or newer.

```bash
cd ~/Development/document-tool
chmod +x build.sh
./build.sh run        # builds "build/Document Tool.app" and launches it
```

On first launch it asks which key you want to hold. You can change it later under menu bar icon → Settings.

To work on it in Xcode, open `Package.swift` and press Run. The app sets itself as a menu bar app, so it behaves the same. "Open at login" only works from the built `.app`.

## Default slices

| File type | Slices (clockwise from the top) |
|---|---|
| PDF | To .txt · Share · Edit · Background · Trash |
| Text | To PDF · Share · Edit · Background · Trash |
| Image | Compress · Edit · Share · Trash |
| Video | Edit · Share · Trash |
| Code | Open in editor · Share · Snippet · Background · Trash |
| Other / mixed | Share · Edit · Trash |

- **Background**: renders the file on a gradient as a PNG next to the original, and copies it to the clipboard. Text goes on a light card, code on a dark card, and a PDF uses its first page.
- **Snippet**: makes a shareable image of the code, with a window frame, syntax colours, line numbers and the file name.
- **Compress**: saves a JPEG copy next to the original, or HEIC when the image has transparency. The original is never changed.
- When you drop several files, the action runs on all of them.

## Custom slices

Go to Settings → Actions and pick a file type. From there you can reorder, remove, or add up to 8 slices. A slice can be a built-in action or one of these:

- **Run a Shortcut**: each file is passed to the Shortcut as input. You can build almost anything this way.
- **Run a shell script**: runs in zsh, with the files as `$1 $2 …` and `"$@"`.
- **Open with app**: opens the files in any app you choose.

Settings are saved in `~/Library/Application Support/DocumentTool/config.json`.

## How it works

| File | What it does |
|---|---|
| `Drag/DragMonitor.swift` | Spots file drags anywhere on the system and checks whether the trigger key is held. |
| `Ring/RingController.swift` | A floating panel that is the drop target. It picks the slice by the direction from the centre. |
| `Ring/RingView.swift` | The pie menu, drawn in SwiftUI. |
| `Actions/` | Each action, plus `ActionRunner`, which runs them. |
| `Model/` | File types, actions and the saved settings. |
| `UI/` | Setup screen, key recorder, Settings, and the confirmation popup. |

The trigger can only use modifier keys (⌃ ⌥ ⇧ ⌘ fn). macOS lets an app read those without asking for Accessibility permission. Other keys would need that permission.

## Releasing a new version

Push a version tag. GitHub Actions builds a universal app and publishes it as a release:

```bash
git tag v0.2.0
git push origin v0.2.0
```

To build the release zip locally instead, run `./release.sh 0.2.0`, which writes it to `dist/`. Building for both chip types needs full Xcode, not just the Command Line Tools.

## License

MIT, see [LICENSE](LICENSE).
