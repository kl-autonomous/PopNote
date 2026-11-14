// PopNote — a tiny floating note for macOS.
// ⌥⌘N opens a fresh note above everything (full-screen apps too).
// Press ⌥⌘N again (or Esc, or the close button) to save it to the app and hide it.
// "Copy" puts the text on the clipboard, saves it, and hides.

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onDismiss: (() -> Void)?

    // The app has no visible menu bar, so handle the usual edit shortcuts here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, flags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            var action: Selector?
            switch key {
            case "x": action = #selector(NSText.cut(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            case "w": onDismiss?(); return true
            default: break
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }  // Esc
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NotePanel!
    var textView: NSTextView!
    var copyButton: NSButton!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?

    let notesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PopNote", isDirectory: true)
    let oldNotesDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PopNote/Notes", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        migrateOldNotes()
        buildPanel()
        buildStatusItem()
        registerHotKey()
    }

    // MARK: Panel

    func buildPanel() {
        panel = NotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "PopNote"
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 240, height: 160)
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.saveAndHide() }
        panel.center()
        panel.setFrameAutosaveName("PopNotePanel")

        let content = panel.contentView!
        let barHeight: CGFloat = 40

        let scroll = NSScrollView(frame: NSRect(x: 0, y: barHeight, width: content.bounds.width,
                                                height: content.bounds.height - barHeight - 28))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        textView = NSTextView(frame: scroll.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 10, height: 6)
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scroll.documentView = textView
        content.addSubview(scroll)

        let hint = NSTextField(labelWithString: "⌥⌘N / Esc: save  ·  ⌘↩: save + copy")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.frame = NSRect(x: 14, y: 12, width: content.bounds.width - 120, height: 16)
        hint.autoresizingMask = [.width]
        content.addSubview(hint)

        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyAndHide))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.keyEquivalentModifierMask = [.command]   // ⌘↩ also copies
        copyButton.toolTip = "Copy to clipboard and close (⌘↩)"
        copyButton.frame = NSRect(x: content.bounds.width - 92, y: 6, width: 80, height: 28)
        copyButton.autoresizingMask = [.minXMargin]
        content.addSubview(copyButton)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveAndHide()
        return false
    }

    func toggle() {
        panel.isVisible ? saveAndHide() : showNewNote()
    }

    @objc func showNewNote() {
        if panel.isVisible { return }
        textView.string = ""
        textView.undoManager?.removeAllActions()
        // Keep the note on screen even if a display was unplugged.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main,
           !screen.visibleFrame.contains(panel.frame) {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                                         y: screen.visibleFrame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(textView)
    }

    func saveAndHide() {
        saveCurrentNote()
        panel.orderOut(nil)
    }

    @objc func copyAndHide() {
        let text = textView.string
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        saveAndHide()
    }

    func saveCurrentNote() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try text.write(to: newNoteURL(for: text, date: Date()), atomically: true, encoding: .utf8) }
        catch { NSSound.beep() }
        textView.string = ""
    }

    /// "2026-11-14 0817 – grocery list.md" — date, then the note's first line.
    func newNoteURL(for text: String, date: Date) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HHmm"
        let firstLine = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        var title = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• \t"))
        title = String(title.unicodeScalars.map {
            CharacterSet(charactersIn: "/:\\").contains($0) || CharacterSet.controlCharacters.contains($0) ? " " : Character($0)
        }).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if title.count > 40 { title = String(title.prefix(40)).trimmingCharacters(in: .whitespaces) + "…" }
        let base = fmt.string(from: date) + (title.isEmpty ? "" : " – " + title)
        var url = notesDir.appendingPathComponent(base + ".md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = notesDir.appendingPathComponent(base + " \(n).md"); n += 1
        }
        return url
    }

    /// Notes from version 1 lived in ~/Library/Application Support/PopNote/Notes as .txt.
    func migrateOldNotes() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: oldNotesDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.pathExtension == "txt" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let dest = newNoteURL(for: text, date: date)
            do { try fm.moveItem(at: file, to: dest) } catch { continue }
            try? fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: dest.path)
        }
        // Tidy up the old folders, but only if nothing but Finder's .DS_Store is left in them.
        for dir in [oldNotesDir, oldNotesDir.deletingLastPathComponent()] {
            guard let rest = try? fm.contentsOfDirectory(atPath: dir.path),
                  rest.allSatisfy({ $0 == ".DS_Store" }) else { break }
            try? fm.removeItem(at: dir)
        }
    }

    // MARK: Menu bar

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "PopNote")
        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New Note", action: #selector(showNewNote), keyEquivalent: "n")
        newItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(newItem)
        menu.addItem(NSMenuItem(title: "Open Saved Notes", action: #selector(openNotesFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PopNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    @objc func openNotesFolder() { NSWorkspace.shared.open(notesDir) }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: Global hotkey (⌥⌘N) — Carbon hotkeys need no Accessibility permission

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x504E5445), id: 1)  // 'PNTE'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            let alert = NSAlert()
            alert.messageText = "⌥⌘N is already used by another app"
            alert.informativeText = "PopNote still works from its menu bar icon."
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
