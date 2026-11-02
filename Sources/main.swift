import Cocoa
import ServiceManagement

// MARK: - 数据模型

struct Alarm: Codable, Equatable {
    var id: String
    var hour: Int
    var minute: Int
    var label: String
    var enabled: Bool

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    static func make(hour: Int, minute: Int, label: String, enabled: Bool = true) -> Alarm {
        Alarm(id: UUID().uuidString, hour: hour, minute: minute, label: label, enabled: enabled)
    }
}

final class AlarmStore {
    static let shared = AlarmStore()
    private let key = "com.oxo.screenalarm.alarms.v1"
    private(set) var alarms: [Alarm] = []

    private init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Alarm].self, from: data) else { return }
        alarms = list
    }

    func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func upsert(_ alarm: Alarm) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx] = alarm
        } else {
            alarms.append(alarm)
        }
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        save()
    }

    func remove(id: String) {
        alarms.removeAll { $0.id == id }
        save()
    }

    /// 仅用于渲染预览，不写盘
    func loadDemo() {
        alarms = [
            Alarm.make(hour: 7, minute: 30, label: "起床", enabled: true),
            Alarm.make(hour: 9, minute: 0, label: "站会", enabled: true),
            Alarm.make(hour: 12, minute: 20, label: "午休结束", enabled: false),
            Alarm.make(hour: 18, minute: 45, label: "起来走走 · 已经坐了两个小时", enabled: true),
        ]
    }

    func alarm(withID id: String) -> Alarm? {
        alarms.first { $0.id == id }
    }

    /// 下一次会触发的闹钟
    var upcoming: (alarm: Alarm, date: Date)? {
        let cal = Calendar.current
        let now = Date()
        var best: (alarm: Alarm, date: Date)?
        for a in alarms where a.enabled {
            guard var target = cal.date(bySettingHour: a.hour, minute: a.minute, second: 0, of: now) else { continue }
            if target <= now {
                target = cal.date(byAdding: .day, value: 1, to: target) ?? target
            }
            if best == nil || target < best!.date { best = (a, target) }
        }
        return best
    }
}

// MARK: - 全屏遮罩

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SolidView: NSView {
    var color: NSColor = .black
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

final class DotView: NSView {
    var color: NSColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.55)
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

final class MockWallpaperView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        NSColor(srgbRed: 0.88, green: 0.90, blue: 0.94, alpha: 1).setFill()
        b.fill()
        guard let base = NSGradient(colors: [
            NSColor(srgbRed: 0.84, green: 0.88, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.93, blue: 0.92, alpha: 1),
            NSColor(srgbRed: 0.90, green: 0.93, blue: 0.97, alpha: 1),
        ]) else { return }
        base.draw(in: b, angle: 90)

    }
}

final class SheenView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let b = bounds

        // 白底上不做亮高光，改为极淡的底部体积阴影
        if let bottom = NSGradient(colors: [
            NSColor(srgbRed: 0.42, green: 0.44, blue: 0.50, alpha: 0.085),
            NSColor(srgbRed: 0.42, green: 0.44, blue: 0.50, alpha: 0.0),
        ]) {
            let band = min(b.height * 0.30, 320)
            bottom.draw(in: NSRect(x: 0, y: 0, width: b.width, height: band), angle: 90)
        }

    }
}

final class OverlayView: NSView {
    var onClose: (() -> Void)?

    private let backdrop = NSVisualEffectView()
    private let tint = SolidView()
    private let sheen = SheenView()
    private let container = NSStackView()
    private let dot = DotView()
    private let kicker = NSTextField(labelWithString: "ALARM")
    private let timeLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "点击任意位置   或   按 ESC 关闭")

    private var clockTimer: Timer?
    private var armedAt = Date()
    private var dotLit = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let desc = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: desc, size: size) ?? base
    }

    init(frame: NSRect, note: String, renderMode: Bool = false) {
        super.init(frame: frame)
        build(note: note, unit: min(frame.width, frame.height), renderMode: renderMode)
        startClock()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(note: String, unit: CGFloat, renderMode: Bool) {
        let b = bounds

        if renderMode {
            // 离屏渲染时 NSVisualEffectView 采不到窗口后方内容，用模拟壁纸代替
            let mock = MockWallpaperView(frame: b)
            mock.autoresizingMask = [.width, .height]
            addSubview(mock)
        } else {
            // 真实运行：液态玻璃直接采样并模糊桌面
            backdrop.frame = b
            backdrop.autoresizingMask = [.width, .height]
            backdrop.material = .underWindowBackground
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.appearance = NSAppearance(named: .aqua)
            addSubview(backdrop)
        }

        // 压暗层：保证白字在任何壁纸上都能读（iOS 27 的"扩散复杂内容"）
        tint.frame = b
        tint.autoresizingMask = [.width, .height]
        tint.color = NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 0.90)
        addSubview(tint)

        sheen.frame = b
        sheen.autoresizingMask = [.width, .height]
        addSubview(sheen)

        let tiny = max(10.0, unit * 0.0135)
        let huge = unit * 0.175
        let mid = max(13.0, unit * 0.030)

        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: unit * 0.0072),
            dot.heightAnchor.constraint(equalToConstant: unit * 0.0072),
        ])

        kicker.attributedStringValue = NSAttributedString(
            string: "ALARM",
            attributes: [
                .font: Self.rounded(tiny, .semibold),
                .foregroundColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.45),
                .kern: unit * 0.0050,
            ]
        )

        let kickerRow = NSStackView(views: [dot, kicker])
        kickerRow.orientation = .horizontal
        kickerRow.alignment = .centerY
        kickerRow.spacing = unit * 0.010

        timeLabel.font = Self.rounded(huge, .thin)
        timeLabel.textColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        timeLabel.stringValue = Self.timeFormatter.string(from: Date())

        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(kickerRow)
        container.setCustomSpacing(unit * 0.022, after: kickerRow)
        container.addArrangedSubview(timeLabel)

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            noteLabel.font = Self.rounded(mid, .regular)
            noteLabel.textColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.62)
            noteLabel.stringValue = trimmed
            noteLabel.alignment = .center
            noteLabel.maximumNumberOfLines = 3
            noteLabel.preferredMaxLayoutWidth = unit * 0.60
            container.addArrangedSubview(noteLabel)
            container.setCustomSpacing(unit * 0.034, after: timeLabel)
        }

        addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -unit * 0.012),
        ])

        buildHintPill(unit: unit)
    }

    private func buildHintPill(unit: CGFloat) {
        hintLabel.font = Self.rounded(max(12.0, unit * 0.0165), .medium)
        hintLabel.textColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.68)
        hintLabel.alignment = .center
        hintLabel.sizeToFit()

        let pillH = unit * 0.062
        let pillW = hintLabel.intrinsicContentSize.width + pillH * 1.30

        if #available(macOS 26.0, *) {
            let pill = NSGlassEffectView()
            pill.style = .regular
            pill.cornerRadius = pillH / 2
            pill.translatesAutoresizingMaskIntoConstraints = false

            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            hintLabel.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(hintLabel)
            NSLayoutConstraint.activate([
                hintLabel.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                hintLabel.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            ])
            pill.contentView = holder
            addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -unit * 0.085),
                pill.widthAnchor.constraint(equalToConstant: pillW),
                pill.heightAnchor.constraint(equalToConstant: pillH),
            ])
        } else {
            let pill = NSView()
            pill.wantsLayer = true
            pill.layer?.backgroundColor = NSColor(white: 1, alpha: 0.72).cgColor
            pill.layer?.cornerRadius = pillH / 2
            pill.layer?.borderWidth = 0.5
            pill.layer?.borderColor = NSColor(white: 0, alpha: 0.10).cgColor
            pill.translatesAutoresizingMaskIntoConstraints = false
            hintLabel.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(hintLabel)
            addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -unit * 0.085),
                pill.widthAnchor.constraint(equalToConstant: pillW),
                pill.heightAnchor.constraint(equalToConstant: pillH),
                hintLabel.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
                hintLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            ])
        }
    }

    private func startClock() {
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let text = Self.timeFormatter.string(from: Date())
            if self.timeLabel.stringValue != text { self.timeLabel.stringValue = text }
            self.dotLit.toggle()
            self.dot.alphaValue = self.dotLit ? 1.0 : 0.30
        }
        RunLoop.main.add(t, forMode: .common)
        clockTimer = t
    }

    func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard Date().timeIntervalSince(armedAt) > 1.2 else { return }
        onClose?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - 遮罩控制器

final class OverlayController {
    static let shared = OverlayController()
    private(set) var isShowing = false
    private var windows: [OverlayWindow] = []
    private var monitors: [Any] = []

    private init() {}

    func show(note: String) {
        guard !isShowing else { return }
        isShowing = true

        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        let behaviour: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]

        for screen in NSScreen.screens {
            let win = OverlayWindow(contentRect: screen.frame,
                                    styleMask: [.borderless],
                                    backing: .buffered,
                                    defer: false)
            win.level = level
            win.collectionBehavior = behaviour
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.isMovable = false
            win.ignoresMouseEvents = false
            win.alphaValue = 0
            let overlay = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), note: note)
            overlay.onClose = { [weak self] in self?.dismiss() }
            win.contentView = overlay
            win.setFrame(screen.frame, display: true)
            win.orderFrontRegardless()
            windows.append(win)
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        if let main = NSScreen.main, let win = windows.first(where: { $0.frame == main.frame }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            windows.first?.makeKeyAndOrderFront(nil)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for w in windows { w.animator().alphaValue = 1.0 }
        }

        let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            // ESC / Return / Space 关闭
            if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 49 {
                self.dismiss()
                return nil
            }
            return event
        }
        if let m { monitors.append(m) }
    }

    func dismiss() {
        guard isShowing else { return }
        isShowing = false
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()

        let closing = windows
        windows = []
        for w in closing {
            (w.contentView as? OverlayView)?.stopClock()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            for w in closing { w.animator().alphaValue = 0 }
        }, completionHandler: {
            for w in closing { w.orderOut(nil) }
        })
    }
}

// MARK: - 启动提示

final class ToastWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ToastController {
    static let shared = ToastController()
    private var window: NSWindow?
    private var lastShown = Date.distantPast

    /// 提示用户"我在菜单栏"，避免双击应用后以为没反应
    func showRunningHint(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastShown) > 8 else { return }
        lastShown = Date()

        window?.orderOut(nil)
        guard let screen = NSScreen.main else { return }

        let w: CGFloat = 486
        let h: CGFloat = 62
        let rect = NSRect(x: screen.frame.midX - w / 2,
                          y: screen.frame.maxY - h - 92,
                          width: w, height: h)

        let win = ToastWindow(contentRect: rect, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let root = NSView(frame: NSRect(origin: .zero, size: rect.size))

        let bg = NSVisualEffectView(frame: root.bounds)
        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.appearance = NSAppearance(named: .aqua)
        bg.wantsLayer = true
        bg.layer?.cornerRadius = h / 2
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor(white: 0, alpha: 0.08).cgColor
        root.addSubview(bg)

        let label = NSTextField(labelWithString: "ScreenAlarm 已在菜单栏运行   ·   点右上角 ⏰ 添加闹钟")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.88)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (h - 20) / 2, width: w, height: 20)
        root.addSubview(label)

        win.contentView = root
        win.alphaValue = 0
        win.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            win.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
                if self?.window === win { self?.window = nil }
            })
        }
        window = win
    }
}

// MARK: - 应用代理

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var ticker: Timer?
    private var firedKeys: Set<String> = []
    private var currentDayKey = ""
    private var lastStatusText = ""
    private var isScreenLocked = false
    private var pendingAlarm: Alarm?
    private var lockObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: "闹钟")
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
        }

        menu.delegate = self
        statusItem.menu = menu
        refreshStatusTitle()

        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        tick()

        AlarmPanelController.shared.show()

        // 调试入口：ScreenAlarm --preview 启动即显示遮罩
        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                OverlayController.shared.show(note: "这是一次预览 · 到点后就是这个样子")
            }
        }
    }

    /// 关掉窗口不退出，点 Dock 图标重新打开
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AlarmPanelController.shared.show()
        return true
    }

    /// 关掉最后一个窗口时继续在菜单栏常驻，闹钟才不会被中断
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: 计时

    private func tick() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        guard let y = comps.year, let mo = comps.month, let d = comps.day,
              let h = comps.hour, let mi = comps.minute else { return }

        let dayKey = String(format: "%04d-%02d-%02d", y, mo, d)
        if dayKey != currentDayKey {
            currentDayKey = dayKey
            firedKeys.removeAll()
        }

        for alarm in AlarmStore.shared.alarms where alarm.enabled {
            guard alarm.hour == h, alarm.minute == mi else { continue }
            let fireKey = "\(alarm.id)|\(dayKey)|\(alarm.timeText)"
            guard !firedKeys.contains(fireKey) else { continue }
            firedKeys.insert(fireKey)
            fire(alarm)
            break
        }

        refreshStatusTitle()
    }

    private func fire(_ alarm: Alarm) {
        OverlayController.shared.show(note: alarm.label)
    }

    @objc private func handleWake() {
        tick()
    }

    private func refreshStatusTitle() {
        guard let button = statusItem.button else { return }
        let text: String
        if let up = AlarmStore.shared.upcoming {
            text = " " + up.alarm.timeText
        } else {
            text = ""
        }
        if text != lastStatusText {
            button.title = text
            lastStatusText = text
        }
        button.toolTip = AlarmStore.shared.upcoming.map {
            "下一次 \($0.alarm.timeText) · \(relativeText($0.date))"
        } ?? "还没有启用的闹钟"
    }

    private func relativeText(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let minutes = seconds / 60
        if minutes < 1 { return "立刻" }
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 24 {
            return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
        }
        return "\(hours / 24) 天后"
    }

    // MARK: 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let up = AlarmStore.shared.upcoming {
            let head = NSMenuItem(title: "下一次  \(up.alarm.timeText)   ·   \(relativeText(up.date))", action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
        } else {
            let head = NSMenuItem(title: "还没有启用的闹钟", action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "打开闹钟面板", action: #selector(openPanel), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let preview = NSMenuItem(title: "预览全屏效果", action: #selector(previewOverlay), keyEquivalent: "p")
        preview.target = self
        menu.addItem(preview)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "退出 ScreenAlarm", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: 动作

    @objc private func openPanel() {
        AlarmPanelController.shared.show()
    }

    @objc private func previewOverlay() {
        OverlayController.shared.show(note: "这是一次预览 · 到点后就是这个样子")
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: 开机自启

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "开机自启设置失败"
            alert.informativeText = "请先把 ScreenAlarm.app 拖进「应用程序」文件夹再试一次。\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    static func parseTime(_ raw: String) -> (Int, Int)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "点", with: ":")
        guard !text.isEmpty else { return nil }

        if text.contains(":") {
            let parts = text.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  let h = Int(parts[0]), let m = Int(parts[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            return (h, m)
        }

        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4, let value = Int(digits) else { return nil }

        if digits.count <= 2 {
            guard (0...23).contains(value) else { return nil }
            return (value, 0)
        }

        let h = value / 100
        let m = value % 100
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}

// MARK: - 入口

let application = NSApplication.shared

// 调试入口：把遮罩渲染成 PNG（离屏，不需要录屏权限）
if let idx = CommandLine.arguments.firstIndex(of: "--render"),
   idx + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[idx + 1]
    let size = NSSize(width: 1512, height: 982)
    let v = OverlayView(frame: NSRect(origin: .zero, size: size),
                        note: "起来走走 · 已经坐了两个小时",
                        renderMode: true)
    v.layoutSubtreeIfNeeded()
    let image = NSImage(size: size)
    image.lockFocusFlipped(false)
    if let ctx = NSGraphicsContext.current {
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        v.displayIgnoringOpacity(v.bounds, in: ctx)
    }
    image.unlockFocus()
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered -> \(path)")
    }
    exit(0)
}

// 调试入口：渲染闹钟面板
if CommandLine.arguments.contains("--render-panel") {
    AlarmStore.shared.loadDemo()
    let size = NSSize(width: 408, height: 664)
    let root = NSView(frame: NSRect(origin: .zero, size: size))
    let veil = SolidView(frame: root.bounds)
    veil.color = NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 1)
    root.addSubview(veil)
    let panel = AlarmPanelView(frame: root.bounds)
    root.addSubview(panel)
    panel.layoutSubtreeIfNeeded()

    let image = NSImage(size: size)
    image.lockFocusFlipped(false)
    if let ctx = NSGraphicsContext.current {
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        root.displayIgnoringOpacity(root.bounds, in: ctx)
    }
    image.unlockFocus()
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/panel_preview.png"))
        print("panel rendered")
    }
    exit(0)
}

let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
