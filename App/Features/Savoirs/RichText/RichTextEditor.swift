import SwiftUI
import UIKit
import FlaunedexCore

/// Where a picture for the card should come from.
enum PhotoSource {
    case library
    case camera
}

/// The text view behind the card editor.
///
/// Pasting is the one behaviour that differs from the stock view: pasted text
/// arrives as plain text and takes the formatting at the cursor (so a page
/// copied from a website cannot drag its fonts and colours into a card), and a
/// pasted picture is inserted as a card picture.
final class RichUITextView: UITextView {
    weak var richModel: RichTextEditorModel?

    override func paste(_ sender: Any?) {
        guard let model = richModel else { return super.paste(sender) }
        let board = UIPasteboard.general
        if board.hasImages, !board.hasStrings || board.hasURLs, let image = board.image {
            model.pasteImage(image)
        } else if let string = board.string {
            model.insertPlainText(string)
        } else {
            super.paste(sender)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return UIPasteboard.general.hasStrings || UIPasteboard.general.hasImages
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

/// Everything behind one editable side of a card.
///
/// The text view's storage holds the semantic keys of `RichTextCodec` (what
/// gets saved) plus the visual attributes `RichTextStyle` derives from them
/// (what gets drawn). Every command changes the semantic keys and then
/// restyles. After every edit a repair pass restores the invariants the codec
/// relies on:
///
/// - every character of a paragraph carries that paragraph's style;
/// - a list paragraph starts with exactly one bullet marker, and no other
///   paragraph has one.
///
/// Typing, deleting across lines, pasting several lines and undoing can all
/// break those invariants for a moment; the repair pass is what makes them
/// safe, rather than each command having to anticipate every case.
@MainActor
final class RichTextEditorModel: NSObject, ObservableObject, UITextViewDelegate {

    enum FormatFlag {
        case bold, italic, underline, strikethrough

        var key: NSAttributedString.Key {
            switch self {
            case .bold: return .flBold
            case .italic: return .flItalic
            case .underline: return .flUnderline
            case .strikethrough: return .flStrikethrough
            }
        }
    }

    @Published private(set) var isEmpty: Bool
    @Published private(set) var activeFormat = RichFormat()
    @Published private(set) var activeStyle: RichParagraphStyle = .body
    /// The selected text, offered as the label when a link is added.
    @Published private(set) var selectedText = ""
    private(set) var hasChanges = false

    private(set) var style: RichTextStyle
    /// Pictures inserted during this edit and not saved yet.
    private(set) var pendingImages: [UUID: PendingImage] = [:]

    /// The screen presents the photo pickers and the link dialog; the toolbar
    /// only asks for them.
    var onRequestPhoto: ((PhotoSource) -> Void)?
    var onRequestLink: (() -> Void)?

    private(set) weak var textView: RichUITextView?
    private var document: RichDocument
    private var toolbar: RichTextToolbar?
    /// The style of an empty last paragraph, which has no character of its own
    /// to carry one (after pressing Return at the end of a title, say).
    private var emptyParagraphStyle: RichParagraphStyle?
    /// The range the pending edit touches, repaired once the edit lands.
    private var pendingRepair: NSRange?
    /// When an edit replaces existing text: where the new text will sit and
    /// the format of the text it replaces, restored once the edit lands.
    private var pendingReplacement: (range: NSRange, format: RichFormat)?

    init(document: RichDocument, style: RichTextStyle) {
        self.document = document.normalized()
        self.isEmpty = document.isBlank
        self.style = style
        super.init()
        let stored = style.imageProvider
        self.style.imageProvider = { [weak self] id in
            MainActor.assumeIsolated { self?.pendingImages[id]?.image } ?? stored(id)
        }
    }

    // MARK: Wiring

    func attach(_ textView: RichUITextView) {
        self.textView = textView
        textView.richModel = self
        textView.delegate = self
        textView.allowsEditingTextAttributes = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 24, right: 14)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.tintColor = style.accent
        textView.linkTextAttributes = [
            .foregroundColor: style.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let toolbar = RichTextToolbar(model: self)
        self.toolbar = toolbar
        textView.inputAccessoryView = toolbar.view
        render(document)
    }

    /// Replace the whole content, as when the editor is reused for a new card.
    func load(_ newDocument: RichDocument) {
        document = newDocument.normalized()
        pendingImages = [:]
        hasChanges = false
        emptyParagraphStyle = nil
        textView?.undoManager?.removeAllActions()
        render(document)
    }

    private func render(_ document: RichDocument) {
        guard let textView else { return }
        textView.attributedText = style.attributedString(for: document)
        textView.typingAttributes = style.typingAttributes(format: .plain, style: .body)
        contentDidChange(markingChanged: false)
        refreshState()
    }

    /// What the editor holds now, in the stored form.
    var currentDocument: RichDocument {
        guard let textView else { return document }
        return RichTextCodec.document(from: textView.textStorage)
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    func endEditing() {
        textView?.resignFirstResponder()
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let paragraph = paragraphRange(at: range.location)
        let currentStyle = styleOfParagraph(paragraph, at: range.location)

        if text == "\n", range.length == 0 {
            if currentStyle == .bullet {
                if paragraphTextIsBlank(paragraph) {
                    // Return on an empty bullet ends the list, as in Mail.
                    setStyle(.body, forParagraphsIn: paragraph)
                } else {
                    insertLineBreak(at: range.location, nextStyle: .bullet)
                }
                return false
            }
            if currentStyle == .heading, range.location == contentEnd(of: paragraph) {
                // After a title comes ordinary text.
                insertLineBreak(at: range.location, nextStyle: .body)
                return false
            }
        }

        if text.isEmpty, range.length > 0, currentStyle == .bullet,
           let marker = markerRange(in: paragraph), range.location >= marker.location,
           NSIntersectionRange(range, marker).length > 0 {
            // Backspace into the bullet removes the bullet, not a character.
            setStyle(.body, forParagraphsIn: paragraph)
            return false
        }

        let inserted = NSRange(location: range.location, length: (text as NSString).length)
        if range.length > 0, inserted.length > 0 {
            // A replacement, typed over a selection or made by the text system
            // (autocorrection re-inserts the word under the cursor as soon as
            // the cursor lands in it). The system paths ignore the typing
            // format, so remember the replaced text's format and restore it.
            pendingReplacement = (inserted, firstTextFormat(in: range) ?? .plain)
        }
        pendingRepair = inserted
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        // Never restyle in the middle of a multi-stage input (Japanese kana,
        // Chinese pinyin): touching the marked text would break the composition.
        if textView.markedTextRange == nil {
            if let replacement = pendingReplacement {
                RichTextCodec.setFormat(replacement.format, in: textView.textStorage, range: replacement.range)
                pendingReplacement = nil
            }
            if let range = pendingRepair {
                repairParagraphs(in: range)
                pendingRepair = nil
            }
        }
        contentDidChange(markingChanged: true)
        refreshState()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let selection = textView.selectedRange
        if selection.length == 0,
           let marker = markerRange(in: paragraphRange(at: selection.location)),
           selection.location >= marker.location, selection.location < NSMaxRange(marker) {
            // The bullet is decoration: the cursor lives after it.
            textView.selectedRange = NSRange(location: NSMaxRange(marker), length: 0)
            return
        }
        if !isInEmptyLastParagraph(selection.location) { emptyParagraphStyle = nil }
        refreshState()
    }

    // MARK: Formatting commands

    func toggle(_ flag: FormatFlag) {
        guard let textView else { return }
        let selection = textView.selectedRange
        if selection.length == 0 {
            var format = activeFormat
            switch flag {
            case .bold: format.bold.toggle()
            case .italic: format.italic.toggle()
            case .underline: format.underline.toggle()
            case .strikethrough: format.strikethrough.toggle()
            }
            setTyping(format: format)
            return
        }
        let key = flag.key
        let turnOn = !everyTextCharacter(in: selection) { ($0[key] as? Bool) == true }
        changeAttributes(in: selection) { storage, range in
            if turnOn {
                storage.addAttribute(key, value: true, range: range)
            } else {
                storage.removeAttribute(key, range: range)
            }
        }
    }

    func setColor(_ color: RichColor?) {
        guard let textView else { return }
        let selection = textView.selectedRange
        if selection.length == 0 {
            var format = activeFormat
            format.color = color
            setTyping(format: format)
            return
        }
        changeAttributes(in: selection) { storage, range in
            if let color {
                storage.addAttribute(.flColor, value: color.rawValue, range: range)
            } else {
                storage.removeAttribute(.flColor, range: range)
            }
        }
    }

    /// Apply a paragraph style to every paragraph the selection touches. Asking
    /// for the style they all already have turns it off (back to body).
    func setParagraphStyle(_ requested: RichParagraphStyle) {
        guard let textView else { return }
        let selection = textView.selectedRange

        if selection.length == 0, isInEmptyLastParagraph(selection.location) {
            let current = emptyParagraphStyle ?? .body
            let target: RichParagraphStyle = current == requested ? .body : requested
            if target == .bullet {
                // A bullet can carry its own style: give the empty line one.
                emptyParagraphStyle = nil
                let marker = markerString()
                replace(NSRange(location: selection.location, length: 0), with: marker,
                        selection: NSRange(location: selection.location + marker.length, length: 0))
            } else {
                emptyParagraphStyle = target
                refreshState()
            }
            return
        }

        let paragraphs = (textView.textStorage.string as NSString).paragraphRange(for: clamped(selection))
        let target: RichParagraphStyle = allParagraphs(in: paragraphs, have: requested) ? .body : requested
        setStyle(target, forParagraphsIn: paragraphs)
    }

    /// Link the selection, or insert a linked label at the cursor. False when
    /// the address is not a usable link.
    @discardableResult
    func applyLink(_ raw: String, label: String?) -> Bool {
        guard let textView, let link = RichLink.normalized(raw), let url = URL(string: link) else { return false }
        let selection = textView.selectedRange
        if selection.length > 0 {
            changeAttributes(in: selection) { storage, range in
                storage.addAttribute(.flLink, value: url, range: range)
            }
        } else {
            let text = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var attributes = style.typingAttributes(format: activeFormat, style: activeStyle)
            attributes[.flLink] = url
            let piece = NSAttributedString(string: text.isEmpty ? link : text, attributes: attributes)
            replace(selection, with: piece, selection: NSRange(location: selection.location + piece.length, length: 0))
        }
        return true
    }

    func removeLink() {
        guard let textView else { return }
        var range = textView.selectedRange
        if range.length == 0 {
            // Unlink the whole link the cursor sits in.
            let storage = textView.textStorage
            let index = max(0, min(range.location, storage.length - 1))
            guard storage.length > 0 else { return }
            var effective = NSRange(location: 0, length: 0)
            guard storage.attribute(.flLink, at: index, longestEffectiveRange: &effective,
                                    in: NSRange(location: 0, length: storage.length)) != nil else { return }
            range = effective
        }
        changeAttributes(in: range) { storage, range in
            storage.removeAttribute(.flLink, range: range)
        }
    }

    var linkAtSelection: String? {
        guard let textView else { return nil }
        let storage = textView.textStorage
        guard storage.length > 0 else { return nil }
        let index = min(textView.selectedRange.location, storage.length - 1)
        let value = storage.attribute(.flLink, at: index, effectiveRange: nil)
        return (value as? URL)?.absoluteString ?? (value as? String)
    }

    // MARK: Pictures

    /// Insert a prepared picture as its own paragraph at the cursor, with a line
    /// after it so writing can continue below.
    func insertImage(_ pending: PendingImage) {
        guard let textView else { return }
        pendingImages[pending.id] = pending
        let selection = textView.selectedRange
        let paragraph = paragraphRange(at: selection.location)
        let currentStyle = styleOfParagraph(paragraph, at: selection.location)

        let piece = NSMutableAttributedString()
        if selection.location > paragraph.location {
            piece.append(NSAttributedString(string: "\n", attributes: style.typingAttributes(format: .plain, style: currentStyle)))
        }
        var pictureAttributes = RichTextCodec.paragraphAttributes(.body)
        pictureAttributes[.flImage] = RichTextCodec.imagePayload(pending.richImage)
        piece.append(NSAttributedString(string: RichTextCodec.objectReplacement, attributes: pictureAttributes))
        piece.append(NSAttributedString(string: "\n", attributes: style.typingAttributes(format: .plain, style: .body)))

        replace(selection, with: piece, selection: NSRange(location: selection.location + piece.length, length: 0))
    }

    func pasteImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95), let pending = PendingImage.prepare(from: data) else { return }
        insertImage(pending)
    }

    /// Paste as plain text with the formatting at the cursor.
    func insertPlainText(_ string: String) {
        guard let textView else { return }
        var clean = string
        for separator in ["\r\n", "\r", "\u{2028}", "\u{2029}"] {
            clean = clean.replacingOccurrences(of: separator, with: "\n")
        }
        clean = clean.replacingOccurrences(of: RichTextCodec.objectReplacement, with: "")
        textView.insertText(clean)
    }

    // MARK: State for the toolbar

    private func refreshState() {
        guard let textView else { return }
        let storage = textView.textStorage
        let selection = clamped(textView.selectedRange)
        let paragraph = paragraphRange(at: selection.location)
        let paragraphStyle = isInEmptyLastParagraph(selection.location)
            ? (emptyParagraphStyle ?? .body)
            : styleOfParagraph(paragraph, at: selection.location)

        let format: RichFormat
        if selection.length > 0 {
            format = firstTextFormat(in: selection) ?? .plain
            selectedText = (storage.string as NSString).substring(with: selection)
        } else {
            format = formatForTyping(at: selection.location, paragraph: paragraph)
            selectedText = ""
            textView.typingAttributes = style.typingAttributes(format: format, style: paragraphStyle)
        }
        activeFormat = format
        activeStyle = paragraphStyle
        toolbar?.update(format: format, style: paragraphStyle, hasLink: linkAtSelection != nil)
    }

    private func setTyping(format: RichFormat) {
        guard let textView else { return }
        textView.typingAttributes = style.typingAttributes(format: format, style: activeStyle)
        activeFormat = format
        toolbar?.update(format: format, style: activeStyle, hasLink: linkAtSelection != nil)
    }

    /// The format new text should get: the character before the cursor's, or
    /// at the very start of a paragraph the first character's. Pictures,
    /// bullets and line breaks lend no format, and links are never extended.
    private func formatForTyping(at location: Int, paragraph: NSRange) -> RichFormat {
        guard let storage = textView?.textStorage, storage.length > 0 else { return .plain }
        let candidates = location > paragraph.location ? [location - 1, location] : [location]
        for index in candidates where index >= paragraph.location && index < min(storage.length, contentEnd(of: paragraph)) {
            let attributes = storage.attributes(at: index, effectiveRange: nil)
            if isDecoration(attributes) { continue }
            var format = RichTextCodec.format(from: attributes)
            format.link = nil
            return format
        }
        return .plain
    }

    private func firstTextFormat(in range: NSRange) -> RichFormat? {
        guard let storage = textView?.textStorage else { return nil }
        var found: RichFormat?
        storage.enumerateAttributes(in: range, options: []) { attributes, subrange, stop in
            let text = (storage.string as NSString).substring(with: subrange)
            if !isDecoration(attributes), text != "\n" {
                found = RichTextCodec.format(from: attributes)
                stop.pointee = true
            }
        }
        return found
    }

    private func everyTextCharacter(in range: NSRange, _ predicate: ([NSAttributedString.Key: Any]) -> Bool) -> Bool {
        guard let storage = textView?.textStorage else { return false }
        var sawText = false
        var all = true
        storage.enumerateAttributes(in: range, options: []) { attributes, subrange, stop in
            let text = (storage.string as NSString).substring(with: subrange)
            guard !isDecoration(attributes), !text.allSatisfy(\.isNewline) else { return }
            sawText = true
            if !predicate(attributes) {
                all = false
                stop.pointee = true
            }
        }
        return sawText && all
    }

    private func isDecoration(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.flMarker] as? Bool) == true || attributes[.flImage] != nil
    }

    // MARK: Editing primitives

    /// Change attributes over a range, restyle it, and register an undo that
    /// puts the old text (with its old attributes) back.
    private func changeAttributes(in range: NSRange, _ body: (NSTextStorage, NSRange) -> Void) {
        guard let textView else { return }
        let storage = textView.textStorage
        let range = clamped(range)
        let previous = storage.attributedSubstring(from: range)
        let selection = textView.selectedRange
        registerUndo(replacing: range, with: previous, selection: selection)
        storage.beginEditing()
        body(storage, range)
        storage.endEditing()
        style.apply(to: storage, range: (storage.string as NSString).paragraphRange(for: range))
        contentDidChange(markingChanged: true)
        refreshState()
    }

    /// Replace a range with attributed text, repair the paragraphs around it,
    /// and register the inverse replacement for undo.
    private func replace(_ range: NSRange, with replacement: NSAttributedString, selection: NSRange) {
        guard let textView else { return }
        let storage = textView.textStorage
        let range = clamped(range)
        let previous = storage.attributedSubstring(from: range)
        let before = textView.selectedRange
        let inserted = NSRange(location: range.location, length: replacement.length)
        registerUndo(replacing: inserted, with: previous, selection: before)
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        textView.selectedRange = clamped(selection)
        repairParagraphs(in: NSRange(location: inserted.location, length: max(inserted.length, 1)))
        contentDidChange(markingChanged: true)
        refreshState()
    }

    private func insertLineBreak(at location: Int, nextStyle: RichParagraphStyle) {
        let paragraph = paragraphRange(at: location)
        let currentStyle = styleOfParagraph(paragraph, at: location)
        let piece = NSMutableAttributedString(string: "\n", attributes: style.typingAttributes(format: .plain, style: currentStyle))
        if nextStyle == .bullet {
            piece.append(markerString())
        }
        emptyParagraphStyle = nextStyle == .bullet ? nil : nextStyle
        replace(NSRange(location: location, length: 0), with: piece,
                selection: NSRange(location: location + piece.length, length: 0))

        // The new paragraph takes the next style on every character it has,
        // including a line break it inherited from the old one.
        guard let storage = textView?.textStorage else { return }
        let newParagraph = paragraphRange(at: location + piece.length)
        if newParagraph.length > 0, nextStyle != .bullet {
            let onlyBreak = (storage.string as NSString).substring(with: newParagraph).allSatisfy(\.isNewline)
            if onlyBreak {
                storage.addAttribute(.flParagraph, value: nextStyle.rawValue, range: newParagraph)
                style.apply(to: storage, range: newParagraph)
            }
        }
        refreshState()
    }

    private func setStyle(_ target: RichParagraphStyle, forParagraphsIn range: NSRange) {
        guard let textView else { return }
        let storage = textView.textStorage
        let paragraphs = (storage.string as NSString).paragraphRange(for: clamped(range))
        guard paragraphs.length > 0 else { return }
        let previous = storage.attributedSubstring(from: paragraphs)
        let selectionBefore = textView.selectedRange

        storage.beginEditing()
        storage.addAttribute(.flParagraph, value: target.rawValue, range: paragraphs)
        storage.endEditing()
        let delta = repairParagraphs(in: paragraphs)
        let changed = NSRange(location: paragraphs.location, length: max(0, paragraphs.length + delta))
        registerUndo(replacing: changed, with: previous, selection: selectionBefore)
        contentDidChange(markingChanged: true)
        refreshState()
    }

    /// Register the replacement that undoes an edit.
    ///
    /// UndoManager's callback is declared as callable from any thread; UIKit
    /// only ever calls it on the main thread, where the editor lives, and the
    /// callback asserts exactly that. The saved text is an immutable copy, so
    /// handing it across that boundary is safe, which the wrapper records.
    private func registerUndo(replacing range: NSRange, with previous: NSAttributedString, selection: NSRange) {
        let saved = SavedText(value: previous)
        textView?.undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.replace(range, with: saved.value, selection: selection)
            }
        }
    }

    // MARK: The repair pass

    /// Restore the paragraph invariants over every paragraph `range` touches
    /// and restyle them. Returns how many characters were added (positive) or
    /// removed (negative), so callers can track the edited range.
    @discardableResult
    private func repairParagraphs(in range: NSRange) -> Int {
        guard let textView else { return 0 }
        let storage = textView.textStorage
        guard storage.length > 0 else { return 0 }
        let string = storage.string as NSString
        let covering = string.paragraphRange(for: clamped(range))

        var paragraphs: [NSRange] = []
        var index = covering.location
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: min(index, string.length), length: 0))
            paragraphs.append(paragraph)
            index = NSMaxRange(paragraph)
        } while index < NSMaxRange(covering) && index < string.length

        var selection = textView.selectedRange
        var delta = 0
        storage.beginEditing()
        // Last to first, so each edit leaves the earlier ranges valid.
        for paragraph in paragraphs.reversed() where paragraph.length > 0 {
            var length = paragraph.length
            let raw = storage.attribute(.flParagraph, at: paragraph.location, effectiveRange: nil) as? String
            let paragraphStyle = raw.flatMap(RichParagraphStyle.init(rawValue:)) ?? .body
            storage.addAttribute(.flParagraph, value: paragraphStyle.rawValue, range: paragraph)

            var flagged: [NSRange] = []
            storage.enumerateAttribute(.flMarker, in: NSRange(location: paragraph.location, length: length)) { value, subrange, _ in
                if (value as? Bool) == true { flagged.append(subrange) }
            }
            let markerLength = (RichTextCodec.bulletMarker as NSString).length
            let proper = flagged.count == 1
                && flagged[0] == NSRange(location: paragraph.location, length: markerLength)
                && (storage.string as NSString).substring(with: flagged[0]) == RichTextCodec.bulletMarker

            if !(paragraphStyle == .bullet && proper) {
                for flag in flagged.reversed() {
                    storage.deleteCharacters(in: flag)
                    Self.adjust(&selection, removing: flag)
                    length -= flag.length
                    delta -= flag.length
                }
                if paragraphStyle == .bullet {
                    let marker = markerString()
                    storage.insert(marker, at: paragraph.location)
                    Self.adjust(&selection, inserting: NSRange(location: paragraph.location, length: marker.length))
                    length += marker.length
                    delta += marker.length
                }
            }
            style.apply(to: storage, range: NSRange(location: paragraph.location, length: length))
        }
        storage.endEditing()
        textView.selectedRange = clamped(selection)
        return delta
    }

    private static func adjust(_ selection: inout NSRange, inserting range: NSRange) {
        if selection.location >= range.location { selection.location += range.length }
    }

    private static func adjust(_ selection: inout NSRange, removing range: NSRange) {
        if selection.location >= NSMaxRange(range) {
            selection.location -= range.length
        } else if selection.location > range.location {
            selection.location = range.location
        }
    }

    // MARK: Paragraph helpers

    private func markerString() -> NSAttributedString {
        var attributes = style.typingAttributes(format: .plain, style: .bullet)
        attributes[.flMarker] = true
        return NSAttributedString(string: RichTextCodec.bulletMarker, attributes: attributes)
    }

    private func paragraphRange(at location: Int) -> NSRange {
        guard let storage = textView?.textStorage else { return NSRange(location: 0, length: 0) }
        let string = storage.string as NSString
        return string.paragraphRange(for: NSRange(location: min(max(0, location), string.length), length: 0))
    }

    /// Where the paragraph's text ends, before its line break.
    private func contentEnd(of paragraph: NSRange) -> Int {
        guard let storage = textView?.textStorage, paragraph.length > 0 else { return paragraph.location }
        let last = NSMaxRange(paragraph) - 1
        let character = (storage.string as NSString).character(at: last)
        return character == 0x0A ? last : NSMaxRange(paragraph)
    }

    private func styleOfParagraph(_ paragraph: NSRange, at location: Int) -> RichParagraphStyle {
        guard let storage = textView?.textStorage else { return .body }
        if paragraph.length == 0 {
            return isInEmptyLastParagraph(location) ? (emptyParagraphStyle ?? .body) : .body
        }
        let raw = storage.attribute(.flParagraph, at: paragraph.location, effectiveRange: nil) as? String
        return raw.flatMap(RichParagraphStyle.init(rawValue:)) ?? .body
    }

    private func markerRange(in paragraph: NSRange) -> NSRange? {
        guard let storage = textView?.textStorage, paragraph.length > 0 else { return nil }
        var effective = NSRange(location: 0, length: 0)
        guard (storage.attribute(.flMarker, at: paragraph.location, longestEffectiveRange: &effective,
                                 in: paragraph) as? Bool) == true else { return nil }
        return effective
    }

    private func paragraphTextIsBlank(_ paragraph: NSRange) -> Bool {
        guard let storage = textView?.textStorage else { return true }
        var blank = true
        storage.enumerateAttributes(in: paragraph, options: []) { attributes, subrange, stop in
            guard (attributes[.flMarker] as? Bool) != true else { return }
            if attributes[.flImage] != nil { blank = false; stop.pointee = true; return }
            let text = (storage.string as NSString).substring(with: subrange)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blank = false
                stop.pointee = true
            }
        }
        return blank
    }

    private func allParagraphs(in range: NSRange, have target: RichParagraphStyle) -> Bool {
        guard let storage = textView?.textStorage else { return false }
        let string = storage.string as NSString
        var index = range.location
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: min(index, string.length), length: 0))
            if styleOfParagraph(paragraph, at: paragraph.location) != target { return false }
            index = NSMaxRange(paragraph)
        } while index < NSMaxRange(range) && index < string.length
        return true
    }

    private func isInEmptyLastParagraph(_ location: Int) -> Bool {
        guard let storage = textView?.textStorage else { return true }
        let length = storage.length
        guard location >= length else { return false }
        return length == 0 || (storage.string as NSString).character(at: length - 1) == 0x0A
    }

    private func clamped(_ range: NSRange) -> NSRange {
        let length = textView?.textStorage.length ?? 0
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    private func contentDidChange(markingChanged: Bool) {
        if markingChanged { hasChanges = true }
        guard let storage = textView?.textStorage else { return }
        var blank = true
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attributes, subrange, stop in
            if (attributes[.flMarker] as? Bool) == true { return }
            if attributes[.flImage] != nil { blank = false; stop.pointee = true; return }
            let text = (storage.string as NSString).substring(with: subrange)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blank = false
                stop.pointee = true
            }
        }
        if isEmpty != blank { isEmpty = blank }
    }
}

/// The formatting bar above the keyboard.
///
/// Built in UIKit because it lives in the text view's `inputAccessoryView`,
/// where it rides up and down with the keyboard for free.
@MainActor
final class RichTextToolbar {
    let view: UIToolbar
    private weak var model: RichTextEditorModel?

    private var styleItem = UIBarButtonItem()
    private var boldItem = UIBarButtonItem()
    private var italicItem = UIBarButtonItem()
    private var underlineItem = UIBarButtonItem()
    private var strikeItem = UIBarButtonItem()
    private var colorItem = UIBarButtonItem()
    private var linkItem = UIBarButtonItem()
    private var photoItem = UIBarButtonItem()

    init(model: RichTextEditorModel) {
        self.model = model
        view = UIToolbar(frame: CGRect(x: 0, y: 0, width: 390, height: 44))
        view.autoresizingMask = [.flexibleWidth]
        view.tintColor = model.style.accent

        styleItem = UIBarButtonItem(image: UIImage(systemName: "textformat.size"), menu: nil)
        styleItem.accessibilityLabel = "Style du paragraphe"
        boldItem = toggleItem("bold", "Gras", .bold)
        italicItem = toggleItem("italic", "Italique", .italic)
        underlineItem = toggleItem("underline", "Souligné", .underline)
        strikeItem = toggleItem("strikethrough", "Barré", .strikethrough)
        colorItem = UIBarButtonItem(image: UIImage(systemName: "paintpalette"), menu: nil)
        colorItem.accessibilityLabel = "Couleur"
        linkItem = UIBarButtonItem(image: UIImage(systemName: "link"),
                                   primaryAction: UIAction { [weak model] _ in model?.onRequestLink?() })
        linkItem.accessibilityLabel = "Lien"
        photoItem = UIBarButtonItem(image: UIImage(systemName: "photo"), menu: photoMenu())
        photoItem.accessibilityLabel = "Image"
        let done = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"),
                                   primaryAction: UIAction { [weak model] _ in model?.endEditing() })
        done.accessibilityLabel = "Masquer le clavier"

        view.items = [styleItem, boldItem, italicItem, underlineItem, strikeItem,
                      colorItem, linkItem, photoItem, .flexibleSpace(), done]
        update(format: .plain, style: .body, hasLink: false)
    }

    private func toggleItem(_ symbol: String, _ label: String, _ flag: RichTextEditorModel.FormatFlag) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: symbol),
                                   primaryAction: UIAction { [weak model] _ in model?.toggle(flag) })
        item.accessibilityLabel = label
        return item
    }

    func update(format: RichFormat, style: RichParagraphStyle, hasLink: Bool) {
        boldItem.isSelected = format.bold
        italicItem.isSelected = format.italic
        underlineItem.isSelected = format.underline
        strikeItem.isSelected = format.strikethrough
        linkItem.isSelected = hasLink
        styleItem.image = UIImage(systemName: Self.symbol(for: style))
        styleItem.menu = styleMenu(current: style)
        colorItem.menu = colorMenu(current: format.color)
        if let color = format.color {
            colorItem.image = UIImage(systemName: "paintpalette.fill")?
                .withTintColor(RichTextStyle.uiColor(color), renderingMode: .alwaysOriginal)
        } else {
            colorItem.image = UIImage(systemName: "paintpalette")
        }
    }

    static func symbol(for style: RichParagraphStyle) -> String {
        switch style {
        case .body: return "text.alignleft"
        case .heading: return "textformat.size"
        case .bullet: return "list.bullet"
        case .quote: return "text.quote"
        }
    }

    private func styleMenu(current: RichParagraphStyle) -> UIMenu {
        let entries: [(RichParagraphStyle, String)] = [
            (.body, "Texte"), (.heading, "Titre"), (.bullet, "Liste à puces"), (.quote, "Citation"),
        ]
        let actions = entries.map { style, title in
            UIAction(title: title, image: UIImage(systemName: Self.symbol(for: style)),
                     state: style == current ? .on : .off) { [weak model] _ in
                model?.setParagraphStyle(style)
            }
        }
        return UIMenu(title: "Paragraphe", children: actions)
    }

    private func colorMenu(current: RichColor?) -> UIMenu {
        let names: [RichColor: String] = [
            .red: "Rouge", .orange: "Orange", .green: "Vert", .blue: "Bleu", .purple: "Violet", .gray: "Gris",
        ]
        var actions: [UIAction] = RichColor.allCases.map { color in
            UIAction(title: names[color] ?? color.rawValue,
                     image: UIImage(systemName: "circle.fill")?
                        .withTintColor(RichTextStyle.uiColor(color), renderingMode: .alwaysOriginal),
                     state: current == color ? .on : .off) { [weak model] _ in
                model?.setColor(color)
            }
        }
        actions.append(UIAction(title: "Couleur par défaut", image: UIImage(systemName: "circle"),
                                state: current == nil ? .on : .off) { [weak model] _ in
            model?.setColor(nil)
        })
        return UIMenu(title: "Couleur du texte", children: actions)
    }

    private func photoMenu() -> UIMenu {
        var actions = [
            UIAction(title: "Photothèque", image: UIImage(systemName: "photo.on.rectangle")) { [weak model] _ in
                model?.onRequestPhoto?(.library)
            },
        ]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actions.append(UIAction(title: "Appareil photo", image: UIImage(systemName: "camera")) { [weak model] _ in
                model?.onRequestPhoto?(.camera)
            })
        }
        return UIMenu(title: "Ajouter une image", children: actions)
    }
}

/// SwiftUI wrapper for the editor. The model owns all the behaviour; this only
/// creates the view and hands it over.
struct RichTextEditor: UIViewRepresentable {
    let model: RichTextEditorModel

    func makeUIView(context: Context) -> RichUITextView {
        let textView = RichUITextView()
        model.attach(textView)
        return textView
    }

    func updateUIView(_ uiView: RichUITextView, context: Context) {}
}

/// An immutable attributed string carried into an undo callback.
private struct SavedText: @unchecked Sendable {
    let value: NSAttributedString
}
