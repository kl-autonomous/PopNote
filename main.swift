// PopNote — a tiny floating note for macOS.
// ⌥⌘N opens a fresh note above everything (full-screen apps too).
// Press ⌥⌘N again (or Esc, or the close button) to save it to the app and hide it.
// "Copy" puts the text on the clipboard, saves it, and hides.
// Images can be dropped or pasted in; they show inline and are saved next to the
// note as files, linked from the Markdown.

import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

/// A text view that shows images inline but keeps all text plain (no fonts or colours
/// carried in from pasted web pages).
final class NoteTextView: NSTextView {
    static let maxImageWidth: CGFloat = 320
    let baseFont = NSFont.systemFont(ofSize: 14)

    func resetTypingAttributes() {
        typingAttributes = [.font: baseFont, .foregroundColor: NSColor.textColor]
    }

    override func paste(_ sender: Any?) {
        if insertImages(from: .general) { return }
        pasteAsPlainText(sender)
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let pb = info.draggingPasteboard
        let index = characterIndexForInsertion(at: convert(info.draggingLocation, from: nil))
        let images = Self.images(on: pb)
        let text = pb.string(forType: .string)
        guard !images.isEmpty || text != nil else { return super.performDragOperation(info) }
        window?.makeKey()
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: index, length: 0))
        if !images.isEmpty { insert(images: images) } else if let text { insertText(text, replacementRange: selectedRange()) }
        return true
    }

    /// Image files (keeping their original bytes) or raw image data from the clipboard or a drag.
    /// Text wins over image data, so copying text from a PDF or web page pastes text.
    static func images(on pb: NSPasteboard) -> [(data: Data, ext: String)] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
            return urls.compactMap { url in
                guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
                return (data, url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())
            }
        }
        if let s = pb.string(forType: .string), !s.isEmpty { return [] }
        if let png = pb.data(forType: .png) { return [(png, "png")] }
        if let image = NSImage(pasteboard: pb), let png = image.pngData { return [(png, "png")] }
        return []
    }

    @discardableResult
    func insertImages(from pb: NSPasteboard) -> Bool {
        let images = Self.images(on: pb)
        if images.isEmpty { return false }
        insert(images: images)
        return true
    }

    func insert(images: [(data: Data, ext: String)]) {
        let out = NSMutableAttributedString()
        for (data, ext) in images {
            guard let image = NSImage(data: data) else { continue }
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = "image.\(ext)"
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            attachment.image = image
            var size = image.size
            if size.width > Self.maxImageWidth {
                size = NSSize(width: Self.maxImageWidth, height: size.height * Self.maxImageWidth / size.width)
            }
            attachment.bounds = CGRect(origin: .zero, size: size)
            out.append(NSAttributedString(attachment: attachment))
            out.append(NSAttributedString(string: "\n", attributes: [.font: baseFont, .foregroundColor: NSColor.textColor]))
        }
        insertText(out, replacementRange: selectedRange())
        resetTypingAttributes()
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

extension NSTextAttachment {
    /// The image's bytes and file extension, whichever way it got into the note.
    var imageFile: (data: Data, ext: String)? {
        if let data = fileWrapper?.regularFileContents {
            let ext = (fileWrapper?.preferredFilename as NSString?)?.pathExtension ?? ""
            return (data, ext.isEmpty ? "png" : ext)
        }
        if let png = image?.pngData { return (png, "png") }
        return nil
    }
}

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
    var textView: NoteTextView!
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

        textView = NoteTextView(frame: scroll.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isRichText = true          // needed to hold images; paste still strips formatting
        textView.importsGraphics = true     // accept image drags
        textView.allowsUndo = true
        textView.font = textView.baseFont
        textView.resetTypingAttributes()
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
        textView.resetTypingAttributes()
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

    var noteHasImages: Bool {
        var found = false
        let s = textView.attributedString()
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    /// The note's text with the image placeholders removed.
    var plainText: String {
        textView.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    var noteIsEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !noteHasImages
    }

    @objc func copyAndHide() {
        if !noteIsEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            if noteHasImages {
                // Rich copy so Notes, Mail, Pages etc. get the pictures too.
                let s = textView.attributedString()
                if let rtfd = s.rtfd(from: NSRange(location: 0, length: s.length), documentAttributes: [:]) {
                    pb.setData(rtfd, forType: .rtfd)
                }
            }
            pb.setString(plainText, forType: .string)
        }
        saveAndHide()
    }

    func saveCurrentNote() {
        guard !noteIsEmpty else { return }
        do {
            let markdown = try markdownSavingImages()
            try markdown.write(to: newNoteURL(for: markdown, date: Date()), atomically: true, encoding: .utf8)
        } catch { NSSound.beep() }
        textView.string = ""
    }

    /// Turns the note into Markdown. Each image is written to ~/Documents/PopNote/attachments/
    /// and replaced by a ![](attachments/…) link.
    func markdownSavingImages() throws -> String {
        let s = textView.attributedString()
        let attachmentsDir = notesDir.appendingPathComponent("attachments", isDirectory: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = fmt.string(from: Date())
        var out = ""
        var n = 1
        var failure: Error?
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, range, stop in
            guard let attachment = value as? NSTextAttachment else {
                out += (s.string as NSString).substring(with: range)
                return
            }
            guard let (data, ext) = attachment.imageFile else { return }
            do {
                try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
                var name: String
                repeat { name = "\(stamp)-\(n).\(ext)"; n += 1 }
                while FileManager.default.fileExists(atPath: attachmentsDir.appendingPathComponent(name).path)
                try data.write(to: attachmentsDir.appendingPathComponent(name))
                out += "![](attachments/\(name))"
            } catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
        return out.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// "2026-11-14 0817 – grocery list.md" — date, then the note's first line.
    func newNoteURL(for text: String, date: Date) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HHmm"
        let firstLine = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("![") } ?? ""
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
