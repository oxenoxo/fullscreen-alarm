import Cocoa

// MARK: - 闹钟面板（仿 Apple 时钟）

private let ink = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)

func panelFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let desc = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: desc, size: size) ?? base
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class AlarmRowView: NSView {
    let alarm: Alarm
    var onToggle: ((Bool) -> Void)?
    var onEdit: (() -> Void)?

    private let timeLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()
    private var hovered = false

    init(alarm: Alarm) {
        self.alarm = alarm
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        timeLabel.font = panelFont(40, .light)
        timeLabel.textColor = ink.withAlphaComponent(alarm.enabled ? 0.95 : 0.30)
        timeLabel.stringValue = alarm.timeText
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        noteLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        noteLabel.textColor = ink.withAlphaComponent(alarm.enabled ? 0.48 : 0.26)
        noteLabel.stringValue = alarm.label.isEmpty ? "闹钟" : alarm.label
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteLabel)

        toggle.state = alarm.enabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.appearance = NSAppearance(named: .aqua)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 86),
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            timeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            noteLabel.leadingAnchor.constraint(equalTo: timeLabel.leadingAnchor),
            noteLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: -6),
            noteLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
        ])
    }

    @objc private func toggleChanged() {
        onToggle?(toggle.state == .on)
    }

    override func mouseDown(with event: NSEvent) {
        onEdit?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        NSColor(white: 0, alpha: hovered ? 0.088 : 0.052).setFill()
        path.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
        NSCursor.arrow.set()
    }
}

final class AlarmPanelView: NSView {
    var onAdd: (() -> Void)?
    var onEdit: ((Alarm) -> Void)?
    var onToggle: ((Alarm, Bool) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "闹钟")
    private let addButton = NSButton()
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let footer = NSTextField(labelWithString: "")
    private let emptyTitle = NSTextField(labelWithString: "还没有闹钟")
    private let emptyHint = NSTextField(labelWithString: "点右上角的 + 添加第一个")

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        titleLabel.font = panelFont(30, .semibold)
        titleLabel.textColor = ink.withAlphaComponent(0.95)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加闹钟")
        addButton.imageScaling = .scaleProportionallyDown
        addButton.isBordered = false
        addButton.contentTintColor = ink.withAlphaComponent(0.75)
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        emptyTitle.font = panelFont(16, .medium)
        emptyTitle.textColor = ink.withAlphaComponent(0.38)
        emptyTitle.alignment = .center
        emptyTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyTitle)

        emptyHint.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        emptyHint.textColor = ink.withAlphaComponent(0.28)
        emptyHint.alignment = .center
        emptyHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyHint)

        footer.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        footer.textColor = ink.withAlphaComponent(0.42)
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footer)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 46),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            addButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 26),
            addButton.heightAnchor.constraint(equalToConstant: 26),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            emptyTitle.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyTitle.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -14),
            emptyHint.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyHint.topAnchor.constraint(equalTo: emptyTitle.bottomAnchor, constant: 6),
        ])
    }

    @objc private func addTapped() {
        onAdd?()
    }

    func reload() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        let alarms = AlarmStore.shared.alarms
        for a in alarms {
            let row = AlarmRowView(alarm: a)
            row.onEdit = { [weak self] in self?.onEdit?(a) }
            row.onToggle = { [weak self] on in self?.onToggle?(a, on) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        emptyTitle.isHidden = !alarms.isEmpty
        emptyHint.isHidden = !alarms.isEmpty

        if let up = AlarmStore.shared.upcoming {
            let minutes = max(0, Int(up.date.timeIntervalSinceNow) / 60)
            let when: String
            if minutes < 60 {
                when = "\(minutes) 分钟后"
            } else if minutes < 1440 {
                let h = minutes / 60
                let m = minutes % 60
                when = m == 0 ? "\(h) 小时后" : "\(h) 小时 \(m) 分后"
            } else {
                when = "\(minutes / 1440) 天后"
            }
            footer.stringValue = "下次闹钟 · \(up.alarm.timeText) · \(when)"
        } else {
            footer.stringValue = "所有闹钟都是关着的"
        }

        layoutSubtreeIfNeeded()
    }
}

final class AlarmPanelController: NSObject, NSWindowDelegate {
    static let shared = AlarmPanelController()
    private var window: NSWindow?
    private var panel: AlarmPanelView?

    private override init() { super.init() }

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel?.reload()
    }

    func reload() {
        panel?.reload()
    }

    private func build() {
        let size = NSSize(width: 408, height: 664)
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "闹钟"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.appearance = NSAppearance(named: .aqua)
        win.delegate = self
        win.center()

        let root = NSView(frame: NSRect(origin: .zero, size: size))

        let bg = NSVisualEffectView(frame: root.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.material = .underWindowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.appearance = NSAppearance(named: .aqua)
        root.addSubview(bg)

        let veil = SolidView(frame: root.bounds)
        veil.autoresizingMask = [.width, .height]
        veil.color = NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 0.86)
        root.addSubview(veil)

        let panel = AlarmPanelView(frame: root.bounds)
        panel.autoresizingMask = [.width, .height]
        root.addSubview(panel)

        panel.onAdd = { [weak self] in self?.presentEditor(nil) }
        panel.onEdit = { [weak self] alarm in self?.presentEditor(alarm) }
        panel.onToggle = { [weak self] alarm, on in
            var updated = alarm
            updated.enabled = on
            AlarmStore.shared.upsert(updated)
            self?.reload()
        }

        win.contentView = root
        self.window = win
        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        // 关窗不退出，靠 Dock 图标重新打开
    }

    private func presentEditor(_ existing: Alarm?) {
        guard let window else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = existing == nil ? "添加闹钟" : "编辑闹钟"
        alert.informativeText = "到点后铺满所有屏幕，全程静音。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if existing != nil { alert.addButton(withTitle: "删除") }

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 104))

        let timeField = NSTextField(frame: NSRect(x: 0, y: 64, width: 108, height: 30))
        timeField.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular)
        timeField.alignment = .center
        timeField.placeholderString = "08:30"
        timeField.stringValue = existing?.timeText ?? ""
        box.addSubview(timeField)

        let tip = NSTextField(labelWithString: "24 小时制，也可直接输入 830")
        tip.font = NSFont.systemFont(ofSize: 11)
        tip.textColor = .secondaryLabelColor
        tip.frame = NSRect(x: 116, y: 72, width: 190, height: 16)
        box.addSubview(tip)

        let labelField = NSTextField(frame: NSRect(x: 0, y: 32, width: 300, height: 26))
        labelField.font = NSFont.systemFont(ofSize: 13)
        labelField.placeholderString = "显示在屏幕上的文案，例如：起来走走"
        labelField.stringValue = existing?.label ?? ""
        box.addSubview(labelField)

        let check = NSButton(checkboxWithTitle: "启用", target: nil, action: nil)
        check.frame = NSRect(x: 0, y: 6, width: 200, height: 20)
        check.state = (existing?.enabled ?? true) ? .on : .off
        box.addSubview(check)

        alert.accessoryView = box
        alert.window.initialFirstResponder = timeField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                guard let parsed = AppDelegate.parseTime(timeField.stringValue) else {
                    self.retryEditor(existing, reason: "时间填得不对")
                    return
                }
                let text = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let on = check.state == .on
                if var updated = existing {
                    updated.hour = parsed.0
                    updated.minute = parsed.1
                    updated.label = text
                    updated.enabled = on
                    AlarmStore.shared.upsert(updated)
                } else {
                    AlarmStore.shared.upsert(.make(hour: parsed.0, minute: parsed.1, label: text, enabled: on))
                }
                self.reload()
            } else if response == .alertThirdButtonReturn, let target = existing {
                AlarmStore.shared.remove(id: target.id)
                self.reload()
            }
        }
    }

    private func retryEditor(_ existing: Alarm?, reason: String) {
        guard let window else { return }
        let warn = NSAlert()
        warn.messageText = reason
        warn.informativeText = "支持 08:30、8:30、830 这三种写法。"
        warn.addButton(withTitle: "好")
        warn.beginSheetModal(for: window) { [weak self] _ in
            self?.presentEditor(existing)
        }
    }
}
