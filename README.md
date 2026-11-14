# PopNote

A tiny floating note for macOS. Press a shortcut, jot something down, press it again and it's saved. No account, no sync service, no settings screen.

## What it does

| Shortcut | Action |
|---|---|
| **⌥⌘N** | Open a new, empty note on top of everything, including full-screen apps and every Space |
| **⌥⌘N** again, **Esc**, or the close button | Save the note and hide it |
| **⌘↩** or the **Copy** button | Save the note, copy it to the clipboard, and hide it |

Empty notes are not saved.

Each note is a plain Markdown file in `~/Documents/PopNote/`, named by date and first line, for example `2026-11-14 0825 – grocery list.md`. Any editor can open these files, and Spotlight can search them.

### Images

Drag an image into a note, or paste one with ⌘V. It shows inline while you write. When the note is saved, each image is written to `~/Documents/PopNote/attachments/` and the note gets a normal Markdown link (`![](attachments/20261114-083254-1.png)`), so editors like Obsidian or Typora show it. **Copy** puts both the pictures and the text on the clipboard, so pasting into Notes, Mail or Pages keeps the images. Pasting text never brings in fonts or colours.

PopNote lives in the menu bar (no Dock icon). From there you can open a new note, open the notes folder, turn on **Launch at Login**, or quit.

## Install

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/kl-autonomous/PopNote.git
cd PopNote
./build.sh
open /Applications/PopNote.app
```

`build.sh` compiles the single source file, ad-hoc signs the app, and copies it to `/Applications`. The first time PopNote saves a note, macOS may ask whether it can access your Documents folder.

The global shortcut uses the Carbon hotkey API, so PopNote doesn't need Accessibility permission. If another app already uses ⌥⌘N, PopNote tells you, and you can still open notes from its menu bar icon.

## Changing the shortcut

Edit `registerHotKey()` in `main.swift` (key code and modifiers) and the matching `New Note` menu item, then run `./build.sh` again.

## License

[MIT](LICENSE)
