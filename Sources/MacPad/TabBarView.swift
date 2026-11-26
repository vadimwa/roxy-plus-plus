import AppKit

/// Notepad++-style tab strip: click to select, × or middle-click to close, drag to reorder,
/// double-click empty space for a new tab, right-click for more.
final class TabBarView: NSView {
    struct Item {
        let id: UUID
        let title: String
        let dirty: Bool
        let tooltip: String
    }

    enum ContextAction {
        case close, closeOthers, closeToRight, copyPath, revealInFinder, openInTerminal, newTerminalHere
    }

    var items: [Item] = [] {
        didSet { clampScroll(); needsDisplay = true }
    }
    var selectedID: UUID? {
        didSet { ensureSelectedVisible(); needsDisplay = true }
    }

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNew: (() -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onContext: ((UUID, ContextAction) -> Void)?

    private var scrollX: CGFloat = 0
    private var hoverIndex: Int?
    private var hoverClose = false
    private var trackingArea: NSTrackingArea?
    private let font = NSFont.systemFont(ofSize: 12)
    private let minWidth: CGFloat = 90
    private let maxWidth: CGFloat = 240
    private let gap: CGFloat = 1
    private let leftInset: CGFloat = 6

    override var isFlipped: Bool { true }

    // MARK: - Geometry

    private func widths() -> [CGFloat] {
        items.map { item in
            let w = (item.title as NSString).size(withAttributes: [.font: font]).width + (item.dirty ? 60 : 46)
            return min(maxWidth, max(minWidth, ceil(w)))
        }
    }

    private func frames() -> [NSRect] {
        var x = leftInset - scrollX
        var result: [NSRect] = []
        for w in widths() {
            result.append(NSRect(x: x, y: 5, width: w, height: bounds.height - 5))
            x += w + gap
        }
        return result
    }

    private var contentWidth: CGFloat {
        widths().reduce(leftInset * 2) { $0 + $1 + gap }
    }

    private func clampScroll() {
        scrollX = max(0, min(scrollX, contentWidth - bounds.width))
    }

    private func ensureSelectedVisible() {
        guard let id = selectedID, let i = items.firstIndex(where: { $0.id == id }) else { return }
        let f = frames()[i]
        if f.minX < 0 {
            scrollX += f.minX - leftInset
        } else if f.maxX > bounds.width {
            scrollX += f.maxX - bounds.width + leftInset
        }
        clampScroll()
    }

    private func closeRect(for frame: NSRect) -> NSRect {
        NSRect(x: frame.maxX - 24, y: frame.midY - 8, width: 16, height: 16)
    }

    private func index(at point: NSPoint) -> Int? {
        frames().firstIndex { $0.contains(point) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        clampScroll()
        ensureSelectedVisible()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        Theme.tabBarBackground.setFill()
        bounds.fill()
        Theme.separator.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let allFrames = frames()
        for (i, item) in items.enumerated() {
            let f = allFrames[i]
            guard f.maxX >= 0, f.minX <= bounds.width else { continue }
            let selected = item.id == selectedID
            let hovered = hoverIndex == i
            let shape = NSBezierPath(roundedRect: NSRect(x: f.minX, y: f.minY, width: f.width, height: f.height + 8),
                                     xRadius: 6, yRadius: 6)

            if selected {
                Theme.tabSelected.setFill()
                shape.fill()
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                NSColor.systemOrange.setFill()
                NSRect(x: f.minX, y: f.minY, width: f.width, height: 2.5).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                if hovered {
                    Theme.tabHover.setFill()
                    shape.fill()
                }
                Theme.separator.setFill()
                NSRect(x: f.maxX, y: f.minY + 6, width: 1, height: f.height - 12).fill()
            }

            var textX = f.minX + 12
            if item.dirty {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: NSRect(x: textX, y: f.midY - 3.5, width: 7, height: 7)).fill()
                textX += 14
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
            let titleHeight = (item.title as NSString).size(withAttributes: attrs).height
            let titleRect = NSRect(x: textX, y: f.midY - titleHeight / 2, width: max(0, f.maxX - 30 - textX), height: titleHeight)
            (item.title as NSString).draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                          attributes: attrs)

            if selected || hovered {
                let cr = closeRect(for: f)
                if hovered && hoverClose {
                    Theme.tabHover.setFill()
                    NSBezierPath(ovalIn: cr).fill()
                }
                let x = NSBezierPath()
                let inset = cr.insetBy(dx: 5, dy: 5)
                x.move(to: NSPoint(x: inset.minX, y: inset.minY))
                x.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
                x.move(to: NSPoint(x: inset.maxX, y: inset.minY))
                x.line(to: NSPoint(x: inset.minX, y: inset.maxY))
                x.lineWidth = 1.3
                NSColor.secondaryLabelColor.setStroke()
                x.stroke()
            }
        }
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func updateHover(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = index(at: p)
        let onClose = i.map { closeRect(for: frames()[$0]).contains(p) } ?? false
        if i != hoverIndex || onClose != hoverClose {
            hoverIndex = i
            hoverClose = onClose
            needsDisplay = true
        }
        toolTip = i.map { items[$0].tooltip }
    }

    override func mouseMoved(with event: NSEvent) { updateHover(event) }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        hoverClose = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = index(at: p) else {
            if event.clickCount == 2 { onNew?() }
            return
        }
        let id = items[i].id
        if closeRect(for: frames()[i]).contains(p) {
            onClose?(id)
            return
        }
        onSelect?(id)

        // Drag to reorder
        var from = i
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let q = convert(next.locationInWindow, from: nil)
            let fr = frames()
            var target = from
            if from + 1 < fr.count, q.x > fr[from + 1].midX {
                target = from + 1
            } else if from > 0, q.x < fr[from - 1].midX {
                target = from - 1
            }
            if target != from {
                onMove?(from, target)
                from = target
                displayIfNeeded()
            }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let i = index(at: p) { onClose?(items[i].id) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        scrollX -= delta
        clampScroll()
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = index(at: p) else { return nil }
        let id = items[i].id
        let menu = NSMenu()
        let entries: [(String, ContextAction)] = [
            ("Close", .close),
            ("Close Other Tabs", .closeOthers),
            ("Close Tabs to the Right", .closeToRight),
            ("", .close),
            ("Copy Full Path", .copyPath),
            ("Reveal in Finder", .revealInFinder),
            ("New Terminal Tab Here", .newTerminalHere),
            ("Open in Terminal", .openInTerminal),
        ]
        for (title, action) in entries {
            if title.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(contextItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ContextBox(id: id, action: action)
            menu.addItem(item)
        }
        return menu
    }

    private final class ContextBox {
        let id: UUID
        let action: ContextAction
        init(id: UUID, action: ContextAction) { self.id = id; self.action = action }
    }

    @objc private func contextItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ContextBox else { return }
        onContext?(box.id, box.action)
    }
}
