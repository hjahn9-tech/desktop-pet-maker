// PetRuntime — 다마고치 메이커가 만든 앱 안에서 실제로 화면에 다마고치를 띄우는 실행 파일.
// 같은 앱 번들의 Resources/sheet.png(스프라이트 시트)와 pet.json(설정)을 읽는다.
import AppKit
import SwiftUI

// MARK: - 설정 파일

struct PetConfig: Decodable {
    var name: String
    var cell: Int                // 스프라이트 한 칸 크기(px)
    var smooth: Bool             // true = 부드럽게 확대, false = 도트(픽셀) 그대로
    var facing: String           // 원본 그림이 보는 방향: right / left / front
    var displaySize: Double      // 화면에 보일 기본 크기(pt)
    var messages: [String]       // 클릭했을 때 말풍선 문구
    var features: [String]?      // 켤 기능 이름들 (Features/Feature.swift 의 featureRegistry)
}

enum Anim: Int, CaseIterable {
    case idle, walk, happy, sleep
    var frames: Int { [4, 4, 4, 2][rawValue] }
    var interval: Double { [0.40, 0.13, 0.14, 0.70][rawValue] }
}

// MARK: - 사용자 설정 (메뉴바에서 바꿈)

final class Prefs {
    static let d = UserDefaults.standard
    static var sizeFactor: Double {
        get { d.object(forKey: "size") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "size") }
    }
    static var speed: Double {
        get { d.object(forKey: "speed") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "speed") }
    }
    static var sleepWhileWorking: Bool {
        get { d.object(forKey: "sleepWhileWorking") as? Bool ?? true }
        set { d.set(newValue, forKey: "sleepWhileWorking") }
    }
}

// MARK: - 로그인 시 자동 실행 (LaunchAgent)

enum LoginItem {
    static var label: String { Bundle.main.bundleIdentifier ?? "local.desktoppet" }
    static var plist: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }
    static var enabled: Bool { FileManager.default.fileExists(atPath: plist) }

    static func launchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    static func set(_ on: Bool) {
        let domain = "gui/\(getuid())"
        if on {
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>\(label)</string>
              <key>ProgramArguments</key>
              <array><string>/usr/bin/open</string><string>-a</string><string>\(Bundle.main.bundlePath)</string></array>
              <key>RunAtLoad</key><true/>
            </dict></plist>
            """
            try? FileManager.default.createDirectory(atPath: (plist as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            try? xml.write(toFile: plist, atomically: true, encoding: .utf8)
            launchctl(["bootstrap", domain, plist])
        } else {
            launchctl(["bootout", "\(domain)/\(label)"])
            try? FileManager.default.removeItem(atPath: plist)
        }
    }
}

// MARK: - 펫 그리는 뷰 (클릭·드래그)

final class PetView: NSView {
    let sprite = CALayer()
    var onClick: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    private var downAt = NSPoint.zero
    private var grab: CGFloat = 0
    private var dragged = false

    init(frame: NSRect, smooth: Bool) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.magnificationFilter = smooth ? .linear : .nearest
        sprite.minificationFilter = smooth ? .linear : .nearest
        layer?.addSublayer(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    func show(_ img: CGImage, flipped: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sprite.contents = img
        sprite.transform = flipped ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        downAt = NSEvent.mouseLocation
        grab = downAt.x - (window?.frame.minX ?? 0)
        dragged = false
    }
    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        if abs(p.x - downAt.x) > 4 { dragged = true }
        if dragged { onDrag?(p.x - grab) }
    }
    override func mouseUp(with e: NSEvent) {
        if dragged { onDragEnd?() } else { onClick?() }
    }
}

// MARK: - 말풍선

final class Bubble {
    let window: NSPanel
    private var hideAt = Date.distantPast

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    func say(_ text: String, above petFrame: NSRect) {
        let view = NSHostingView(rootView:
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.15)))
                .fixedSize()
                .padding(4))
        let size = view.fittingSize
        window.contentView = view
        window.setContentSize(size)
        follow(petFrame)
        window.orderFrontRegardless()
        hideAt = Date().addingTimeInterval(3)
    }

    func follow(_ petFrame: NSRect) {
        guard window.isVisible else { return }
        let s = window.frame.size
        var x = petFrame.midX - s.width / 2
        if let scr = NSScreen.main?.visibleFrame { x = min(max(x, scr.minX), scr.maxX - s.width) }
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: petFrame.maxY - 4))
    }

    func tick() {
        if window.isVisible && Date() > hideAt { window.orderOut(nil) }
    }
}

// MARK: - 다마고치

final class Pet {
    let cfg: PetConfig
    let rows: [[CGImage]]
    let window: NSPanel
    let view: PetView
    let bubble = Bubble()
    var x: CGFloat = 0
    var dir: CGFloat = 1
    var anim = Anim.idle
    var frame = 0
    var clock = 0.0
    var until = Date()
    var dragging = false
    var features: [PetFeature] = []
    let popover = NSPopover()

    var size: CGFloat { CGFloat(cfg.displaySize * Prefs.sizeFactor) }
    var screen: NSRect { (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    init(cfg: PetConfig, rows: [[CGImage]]) {
        self.cfg = cfg
        self.rows = rows
        let sz = CGFloat(cfg.displaySize * Prefs.sizeFactor)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        view = PetView(frame: NSRect(x: 0, y: 0, width: sz, height: sz), smooth: cfg.smooth)
        window.contentView = view
        view.onClick = { [weak self] in self?.clicked() }
        view.onDrag = { [weak self] nx in self?.dragging = true; self?.x = nx; self?.place() }
        view.onDragEnd = { [weak self] in self?.dragging = false; self?.set(.idle, 0.6) }
        x = screen.minX + screen.width * CGFloat.random(in: 0.2...0.8)
        place()
        window.orderFrontRegardless()
    }

    func place() {
        let s = screen
        x = min(max(x, s.minX), s.maxX - window.frame.width)
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: s.minY))
        bubble.follow(window.frame)
    }

    func resize() {
        window.setContentSize(NSSize(width: size, height: size))
        place()
    }

    func set(_ a: Anim, _ seconds: Double) {
        anim = a; frame = 0; clock = 0
        until = Date().addingTimeInterval(seconds)
    }

    /// 원본 그림의 방향을 고려해, 지금 걷는 방향으로 보이게 뒤집을지
    var flipped: Bool {
        switch cfg.facing {
        case "left": return dir > 0
        case "front": return false
        default: return dir < 0
        }
    }

    func clicked() {
        if popover.isShown { popover.performClose(nil); return }
        set(.happy, 1.4)
        if features.isEmpty {
            if let m = cfg.messages.filter({ !$0.isEmpty }).randomElement() { bubble.say(m, above: window.frame) }
            return
        }
        // 기능이 있으면 패널을 연다
        features.forEach { $0.refresh() }
        if popover.contentViewController == nil {
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 340, height: 480)
            popover.contentViewController = NSHostingController(rootView: FeaturesPanel(features: features))
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    /// 기능이 알려 줄 게 있으면 폴짝 뛰며 말풍선
    func notify(_ text: String) {
        set(.happy, 1.4)
        bubble.say(text, above: window.frame)
    }

    func tick(dt: Double, working: Bool, justStopped: Bool) {
        bubble.tick()
        let reacting = anim == .happy && Date() < until
        if dragging || reacting || popover.isShown {
            // 반응·드래그 중에는 그대로
        } else if working {
            if anim != .sleep { set(.sleep, 1e9) }
        } else if justStopped {
            set(.idle, 1.0)
        } else if Date() > until {
            if anim == .walk && Double.random(in: 0...1) < 0.35 {
                set(.idle, Double.random(in: 1.5...4))
            } else {
                if anim != .walk && Double.random(in: 0...1) < 0.35 { dir = -dir }
                set(.walk, Double.random(in: 4...10))
            }
        }
        if anim == .walk && !dragging {
            x += dir * 0.35 * size * CGFloat(Prefs.speed) * CGFloat(dt)
            let s = screen
            if x >= s.maxX - size { x = s.maxX - size; dir = -1 }
            if x <= s.minX { x = s.minX; dir = 1 }
            place()
        }
        clock += dt
        if clock >= anim.interval { clock = 0; frame = (frame + 1) % anim.frames }
        let row = rows[anim.rawValue]
        view.show(row[min(frame, row.count - 1)], flipped: flipped)
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: Pet!
    var status: NSStatusItem!
    var last = CACurrentMediaTime()
    var working = true

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let cu = Bundle.main.url(forResource: "pet", withExtension: "json"),
              let data = try? Data(contentsOf: cu),
              let cfg = try? JSONDecoder().decode(PetConfig.self, from: data),
              let su = Bundle.main.url(forResource: "sheet", withExtension: "png"),
              let src = CGImageSourceCreateWithURL(su as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            let a = NSAlert()
            a.messageText = "다마고치 파일(sheet.png, pet.json)을 찾지 못했습니다"
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        let c = cfg.cell
        let rows: [[CGImage]] = Anim.allCases.map { a in
            (0..<a.frames).compactMap { sheet.cropping(to: CGRect(x: $0 * c, y: a.rawValue * c, width: c, height: c)) }
        }
        pet = Pet(cfg: cfg, rows: rows)
        // 기능 켜기: 각자 주기마다 새로 고침, 15초마다 알릴 거리 확인
        pet.features = (cfg.features ?? []).compactMap { featureRegistry[$0]?() }
        for f in pet.features {
            Timer.scheduledTimer(withTimeInterval: f.refreshInterval, repeats: true) { _ in f.refresh() }
        }
        if !pet.features.isEmpty {
            Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                guard let p = self?.pet else { return }
                for f in p.features { if let msg = f.takeAttention() { p.notify(msg); break } }
            }
        }
        buildMenu()
        if CommandLine.arguments.contains("--open-panel") {   // 확인용: 시작 3초 뒤 클릭한 것처럼
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.pet.clicked() }
        }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
    }

    /// 마지막 키보드·마우스 입력 뒤로 흐른 초 (권한 필요 없음)
    var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        let was = working
        let idle = idleSeconds
        if working, idle >= 5 { working = false } else if !working, idle < 1 { working = true }
        let sleepy = Prefs.sleepWhileWorking
        pet.tick(dt: dt, working: sleepy && working, justStopped: sleepy && was && !working)
    }

    func buildMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let f = pet.rows.first?.first {
            status.button?.image = NSImage(cgImage: f, size: NSSize(width: 20, height: 20))
        } else {
            status.button?.title = "🐾"
        }
        let m = NSMenu()
        m.addItem(withTitle: pet.features.isEmpty ? "\(pet.cfg.name)에게 말 걸기" : "패널 열기 (\(pet.features.map { $0.title }.joined(separator: "·")))",
                  action: #selector(poke), keyEquivalent: "")
        m.addItem(.separator())
        for (t, v) in [("작게", 0.7), ("보통", 1.0), ("크게", 1.4)] {
            let i = NSMenuItem(title: "크기: \(t)", action: #selector(pickSize(_:)), keyEquivalent: "")
            i.representedObject = v
            i.state = abs(Prefs.sizeFactor - v) < 0.01 ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        for (t, v) in [("느리게", 0.6), ("보통", 1.0), ("빠르게", 1.6)] {
            let i = NSMenuItem(title: "걷는 속도: \(t)", action: #selector(pickSpeed(_:)), keyEquivalent: "")
            i.representedObject = v
            i.state = abs(Prefs.speed - v) < 0.01 ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        let s = NSMenuItem(title: "키보드·마우스 쓰는 동안 잠자기", action: #selector(toggleSleep(_:)), keyEquivalent: "")
        s.state = Prefs.sleepWhileWorking ? .on : .off
        m.addItem(s)
        let l = NSMenuItem(title: "로그인할 때 자동으로 켜기", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        l.state = LoginItem.enabled ? .on : .off
        m.addItem(l)
        m.addItem(.separator())
        m.addItem(withTitle: "\(pet.cfg.name) 종료", action: #selector(quit), keyEquivalent: "q")
        for i in m.items { i.target = self }
        status.menu = m
    }

    private func check(_ sender: NSMenuItem, group: Selector) {
        sender.menu?.items.filter { $0.action == group }.forEach { $0.state = $0 == sender ? .on : .off }
    }

    @objc func poke() { pet.clicked() }
    @objc func pickSize(_ s: NSMenuItem) {
        Prefs.sizeFactor = s.representedObject as? Double ?? 1
        check(s, group: #selector(pickSize(_:)))
        pet.resize()
    }
    @objc func pickSpeed(_ s: NSMenuItem) {
        Prefs.speed = s.representedObject as? Double ?? 1
        check(s, group: #selector(pickSpeed(_:)))
    }
    @objc func toggleSleep(_ s: NSMenuItem) {
        Prefs.sleepWhileWorking.toggle()
        s.state = Prefs.sleepWhileWorking ? .on : .off
    }
    @objc func toggleLogin(_ s: NSMenuItem) {
        LoginItem.set(!LoginItem.enabled)
        s.state = LoginItem.enabled ? .on : .off
    }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
