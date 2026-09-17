// Life Wallpaper — Conway's Game of Life as a living desktop background for macOS.
// Runs at desktop-window level: above your wallpaper, below your icons.

import Cocoa
import ImageIO
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Config

typealias RGB = (Double, Double, Double)

struct Config {
    var cell: Int = 14          // screen points per cell
    var fps: Double = 8         // generations per second
    var density: Double = 0.16  // initial density
    var trail: Int = 10         // generations a dead cell keeps glowing
    var fade: Double = -1       // crossfade seconds between generations; -1 = auto
    var bg: RGB = (0.043, 0.055, 0.067)
    var fg: RGB = (0.40, 0.92, 0.75)
    var showMenu = true
}

func parseHex(_ s: String) -> RGB? {
    var t = s.hasPrefix("#") ? String(s.dropFirst()) : s
    if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
    guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
    return (Double((v >> 16) & 0xff) / 255.0,
            Double((v >> 8) & 0xff) / 255.0,
            Double(v & 0xff) / 255.0)
}

func hex(_ c: RGB) -> String {
    String(format: "%02X%02X%02X", Int(c.0 * 255 + 0.5), Int(c.1 * 255 + 0.5), Int(c.2 * 255 + 0.5))
}

// Settings live in UserDefaults, so the menu remembers your choices.
// `defaults write io.github.psych0bunny01.LifeWallpaper fps 4` works too.
enum Settings {
    static let d = UserDefaults.standard

    static func load() -> Config {
        var c = Config()
        if d.object(forKey: "cell") != nil { c.cell = d.integer(forKey: "cell") }
        if d.object(forKey: "fps") != nil { c.fps = d.double(forKey: "fps") }
        if d.object(forKey: "density") != nil { c.density = d.double(forKey: "density") }
        if d.object(forKey: "trail") != nil { c.trail = d.integer(forKey: "trail") }
        if d.object(forKey: "fade") != nil { c.fade = d.double(forKey: "fade") }
        if let s = d.string(forKey: "color"), let v = parseHex(s) { c.fg = v }
        if let s = d.string(forKey: "bg"), let v = parseHex(s) { c.bg = v }
        if d.bool(forKey: "hideMenuBarIcon") { c.showMenu = false }
        return clamp(c)
    }

    static func save(_ c: Config) {
        d.set(c.cell, forKey: "cell"); d.set(c.fps, forKey: "fps")
        d.set(c.density, forKey: "density"); d.set(c.trail, forKey: "trail")
        d.set(c.fade, forKey: "fade")
        d.set(hex(c.fg), forKey: "color"); d.set(hex(c.bg), forKey: "bg")
    }

    static func clamp(_ c: Config) -> Config {
        var c = c
        c.cell = max(3, min(80, c.cell))
        c.fps = min(30, max(0.5, c.fps))
        c.density = min(0.9, max(0.02, c.density))
        c.trail = max(0, min(60, c.trail))
        c.fade = c.fade < 0 ? -1 : min(5, c.fade)
        return c
    }
}

// MARK: - Simulation

final class World {
    let w: Int, h: Int
    let trailMax: UInt8
    private var cur: [UInt8]
    private var nxt: [UInt8]
    private(set) var age: [UInt8]      // 0 = cold, trailMax = alive
    private var recent: [UInt64] = []
    private var seen = Set<UInt64>()
    private let density: Double

    init(w: Int, h: Int, density: Double, trail: Int) {
        self.w = max(8, w); self.h = max(8, h)
        self.density = density
        self.trailMax = UInt8(max(1, min(200, trail + 1)))
        cur = [UInt8](repeating: 0, count: self.w * self.h)
        nxt = cur
        age = cur
        seedAll()
    }

    func seedAll() {
        for i in 0..<cur.count {
            let alive = Double.random(in: 0..<1) < density
            cur[i] = alive ? 1 : 0
            age[i] = alive ? trailMax : 0
        }
        recent.removeAll(); seen.removeAll()
    }

    /// Drop a block of fresh soup somewhere, so the board never goes stale.
    func sprinkle() {
        let bw = max(10, w / 5), bh = max(10, h / 5)
        let x0 = Int.random(in: 0..<w), y0 = Int.random(in: 0..<h)
        for dy in 0..<bh {
            let y = (y0 + dy) % h
            for dx in 0..<bw where Double.random(in: 0..<1) < 0.32 {
                let i = y * w + (x0 + dx) % w
                cur[i] = 1
                age[i] = trailMax
            }
        }
        recent.removeAll(); seen.removeAll()
    }

    func step() {
        let W = w, H = h
        cur.withUnsafeBufferPointer { c in
            nxt.withUnsafeMutableBufferPointer { n in
                for y in 0..<H {
                    let up = ((y - 1 + H) % H) * W
                    let dn = ((y + 1) % H) * W
                    let md = y * W
                    for x in 0..<W {
                        let xl = (x - 1 + W) % W
                        let xr = (x + 1) % W
                        // All eight neighbours, read from the PREVIOUS generation (torus edges).
                        let s = c[up + xl] + c[up + x] + c[up + xr]
                              + c[md + xl]             + c[md + xr]
                              + c[dn + xl] + c[dn + x] + c[dn + xr]
                        let alive = c[md + x] == 1
                        n[md + x] = (s == 3 || (alive && s == 2)) ? 1 : 0
                    }
                }
            }
        }
        swap(&cur, &nxt)

        var pop = 0
        var hv: UInt64 = 0xcbf2_9ce4_8422_2325
        for i in 0..<cur.count {
            let a = cur[i]
            if a == 1 { age[i] = trailMax; pop += 1 }
            else if age[i] > 0 { age[i] -= 1 }
            hv = (hv ^ UInt64(a)) &* 0x100_0000_01b3
        }

        // Died out, or stuck in a loop? Add fresh soup.
        if pop == 0 { seedAll(); return }
        if seen.contains(hv) { sprinkle(); return }
        seen.insert(hv); recent.append(hv)
        if recent.count > 80 { seen.remove(recent.removeFirst()) }
    }
}

// MARK: - Renderer (a bitmap at cell resolution; the GPU scales it up)

final class Renderer {
    private let gw: Int, gh: Int
    private let px = 4                 // bitmap pixels per cell; 3x3 filled = grid lines
    private let ctx: CGContext
    private let buf: UnsafeMutablePointer<UInt8>
    private let bpr: Int
    private var lut = [(UInt8, UInt8, UInt8)]()
    private let bg: RGB

    init?(gw: Int, gh: Int, cfg: Config, trailMax: UInt8) {
        self.gw = gw; self.gh = gh
        self.bpr = gw * px * 4
        self.bg = cfg.bg
        guard let c = CGContext(data: nil, width: gw * px, height: gh * px,
                                bitsPerComponent: 8, bytesPerRow: bpr,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let d = c.data else { return nil }
        ctx = c
        buf = d.bindMemory(to: UInt8.self, capacity: bpr * gh * px)
        for a in 0...Int(trailMax) {
            let t = Double(a) / Double(trailMax)
            let e = a == Int(trailMax) ? 1.0 : t * t * 0.85   // the afterglow fades fast
            lut.append((UInt8((cfg.bg.0 + (cfg.fg.0 - cfg.bg.0) * e) * 255),
                        UInt8((cfg.bg.1 + (cfg.fg.1 - cfg.bg.1) * e) * 255),
                        UInt8((cfg.bg.2 + (cfg.fg.2 - cfg.bg.2) * e) * 255)))
        }
    }

    func image(age: [UInt8]) -> CGImage? {
        let br = UInt8(bg.0 * 255), bgc = UInt8(bg.1 * 255), bb = UInt8(bg.2 * 255)
        for gy in 0..<gh {
            for gx in 0..<gw {
                let (r, g, b) = lut[Int(age[gy * gw + gx])]
                for sy in 0..<px {
                    var o = (gy * px + sy) * bpr + gx * px * 4
                    for sx in 0..<px {
                        let gap = (sx == px - 1) || (sy == px - 1)   // 1px seam = grid look
                        buf[o] = gap ? br : r
                        buf[o + 1] = gap ? bgc : g
                        buf[o + 2] = gap ? bb : b
                        o += 4
                    }
                }
            }
        }
        return ctx.makeImage()
    }
}

// MARK: - View & window

final class LifeView: NSView {
    override init(frame f: NSRect) {
        super.init(frame: f)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
        layer?.isOpaque = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { true }

    /// Crossfade to the next generation instead of snapping.
    /// The fade runs on the GPU, so it costs no extra CPU.
    func show(_ img: CGImage, fade: Double) {
        guard let layer = layer else { return }
        let old = layer.contents
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = img
        CATransaction.commit()
        if let old = old, fade > 0.02 {
            let a = CABasicAnimation(keyPath: "contents")
            a.fromValue = old
            a.toValue = img
            a.duration = fade
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(a, forKey: "xfade")
        }
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Panel {
    let window: DesktopWindow
    let view: LifeView
    let world: World
    var renderer: Renderer?

    init(screen: NSScreen, cfg: Config) {
        let f = screen.frame
        let gw = max(8, Int(f.width) / cfg.cell)
        let gh = max(8, Int(f.height) / cfg.cell)
        world = World(w: gw, h: gh, density: cfg.density, trail: cfg.trail)
        renderer = Renderer(gw: gw, gh: gh, cfg: cfg, trailMax: world.trailMax)
        view = LifeView(frame: NSRect(origin: .zero, size: f.size))
        window = DesktopWindow(contentRect: f, styleMask: [.borderless],
                               backing: .buffered, defer: false)
        // Swift owns this window. Without this, close() releases it a second time and
        // the app crashes after any settings change.
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = NSColor(srgbRed: cfg.bg.0, green: cfg.bg.1, blue: cfg.bg.2, alpha: 1)
        window.contentView = view
        window.orderFrontRegardless()
        if let img = renderer?.image(age: world.age) { view.show(img, fade: 0) }
    }

    func tick(fade: Double) {
        world.step()
        if let img = renderer?.image(age: world.age) { view.show(img, fade: fade) }
    }

    /// New colors without reseeding the board.
    func recolor(cfg: Config) {
        renderer = Renderer(gw: world.w, gh: world.h, cfg: cfg, trailMax: world.trailMax)
        window.backgroundColor = NSColor(srgbRed: cfg.bg.0, green: cfg.bg.1, blue: cfg.bg.2, alpha: 1)
        if let img = renderer?.image(age: world.age) { view.show(img, fade: 0) }
    }

    func close() { window.orderOut(nil); window.close() }
}

// MARK: - Settings window

final class SettingsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    unowned let controller: Controller

    private let fgWell = NSColorWell()
    private let bgWell = NSColorWell()
    private let speed = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let cell = NSSlider(value: 14, minValue: 4, maxValue: 40, target: nil, action: nil)
    private let density = NSSlider(value: 0.16, minValue: 0.02, maxValue: 0.6, target: nil, action: nil)
    private let trail = NSSlider(value: 10, minValue: 0, maxValue: 30, target: nil, action: nil)
    private let smooth = NSButton(checkboxWithTitle: "Crossfade between generations", target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let cellLabel = NSTextField(labelWithString: "")
    private let densityLabel = NSTextField(labelWithString: "")
    private let trailLabel = NSTextField(labelWithString: "")

    // The speed slider is logarithmic: 0.5 … 30 generations per second.
    private static let fpsMin = 0.5, fpsMax = 30.0
    private static func fps(from t: Double) -> Double { fpsMin * pow(fpsMax / fpsMin, t) }
    private static func position(for fps: Double) -> Double { log(fps / fpsMin) / log(fpsMax / fpsMin) }

    init(controller: Controller) {
        self.controller = controller
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Life Wallpaper Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self

        for w in [fgWell, bgWell] {
            w.target = self; w.action = #selector(colorsChanged)
            w.widthAnchor.constraint(equalToConstant: 60).isActive = true
        }
        for (s, sel) in [(speed, #selector(speedChanged)), (cell, #selector(boardChanged(_:))),
                         (density, #selector(boardChanged(_:))), (trail, #selector(boardChanged(_:)))] {
            s.target = self; s.action = sel; s.isContinuous = true
            s.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        }
        cell.numberOfTickMarks = 0
        smooth.target = self; smooth.action = #selector(smoothChanged)
        for l in [speedLabel, cellLabel, densityLabel, trailLabel] {
            l.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            l.textColor = .secondaryLabelColor
            l.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }

        let empty = NSGridCell.emptyContentView
        let grid = NSGridView(views: [
            [label("Cells"), fgWell, empty],
            [label("Background"), bgWell, empty],
            [label("Speed"), speed, speedLabel],
            [label("Cell size"), cell, cellLabel],
            [label("Density"), density, densityLabel],
            [label("Afterglow"), trail, trailLabel],
            [empty, smooth, empty],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for r in 0..<2 { grid.row(at: r).yPlacement = .center; grid.row(at: r).rowAlignment = .none }

        let soup = NSButton(title: "New Soup", target: self, action: #selector(newSoup))
        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults))
        let buttons = NSStackView(views: [soup, reset])
        buttons.spacing = 8

        let note = NSTextField(wrappingLabelWithString:
            "Changing cell size, density or afterglow starts a fresh board.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [grid, note, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        refresh()
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private func color(_ c: RGB) -> NSColor { NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1) }

    private func rgb(_ c: NSColor) -> RGB {
        let s = c.usingColorSpace(.sRGB) ?? NSColor.white
        // Wide-gamut picks can land outside 0…1 in sRGB; the renderer needs bytes.
        let f = { (v: CGFloat) in min(1, max(0, Double(v))) }
        return (f(s.redComponent), f(s.greenComponent), f(s.blueComponent))
    }

    /// Pull the current settings into the controls.
    func refresh() {
        let c = controller.cfg
        fgWell.color = color(c.fg)
        bgWell.color = color(c.bg)
        speed.doubleValue = Self.position(for: c.fps)
        cell.integerValue = c.cell
        density.doubleValue = c.density
        trail.integerValue = c.trail
        smooth.state = c.fade == 0 ? .off : .on
        updateLabels()
    }

    private func updateLabels() {
        let f = Self.fps(from: speed.doubleValue)
        speedLabel.stringValue = f < 10 ? String(format: "%.1f gen/s", f) : String(format: "%.0f gen/s", f)
        cellLabel.stringValue = "\(cell.integerValue) pt"
        densityLabel.stringValue = "\(Int((density.doubleValue * 100).rounded())) %"
        trailLabel.stringValue = trail.integerValue == 0 ? "off" : "\(trail.integerValue) gen"
    }

    func show() {
        refresh()
        NSColorPanel.shared.showsAlpha = false
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func colorsChanged() {
        controller.setColors(fg: rgb(fgWell.color), bg: rgb(bgWell.color))
    }

    @objc private func speedChanged() {
        updateLabels()
        controller.changeSpeed(to: Self.fps(from: speed.doubleValue))
    }

    // Rebuilding the board is visible, so wait until the slider is released.
    @objc private func boardChanged(_ s: NSSlider) {
        updateLabels()
        let dragging = NSApp.currentEvent?.type == .leftMouseDragged
        if dragging { return }
        controller.update { c in
            c.cell = cell.integerValue
            c.density = (density.doubleValue * 100).rounded() / 100
            c.trail = trail.integerValue
        }
    }

    @objc private func smoothChanged() {
        controller.update { c in c.fade = smooth.state == .on ? -1 : 0 }
    }

    @objc private func newSoup() { controller.reseed() }

    @objc private func resetDefaults() {
        controller.update { c in
            let keep = c.showMenu
            c = Config()
            c.showMenu = keep
        }
        refresh()
    }

    func windowWillClose(_ n: Notification) {
        NSColorPanel.shared.orderOut(nil)
    }
}

// MARK: - Menu bar presets

let showMenuNote = Notification.Name("io.github.psych0bunny01.LifeWallpaper.showMenu")

let speeds: [(String, Double)] = [("Slow — 1 gen/s", 1), ("Calm — 4 gen/s", 4),
                                  ("Normal — 8 gen/s", 8), ("Fast — 15 gen/s", 15)]
let sizes: [(String, Int)] = [("Small", 8), ("Medium", 14), ("Large", 24)]
let palettes: [(String, String, String)] = [
    ("Mint", "66EBBF", "0B0E11"), ("Amber", "FFB547", "120D08"), ("Ice", "8CC8FF", "080C14"),
    ("Rose", "FF7A9A", "130A0E"), ("Mono", "D8D8D8", "0E0E0E"),
]

// MARK: - Controller

final class Controller: NSObject, NSApplicationDelegate {
    var cfg: Config
    var panels: [Panel] = []
    var timer: Timer?
    var paused = false
    var statusItem: NSStatusItem?
    var settings: SettingsWindow?

    var fade: Double { cfg.fade >= 0 ? cfg.fade : min(3.0, 0.9 / cfg.fps) }

    init(cfg: Config) { self.cfg = cfg }

    func applicationDidFinishLaunching(_ n: Notification) {
        build()
        if cfg.showMenu { setupMenu() }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(occlusionChanged),
                       name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showMenuAgain),
                                                            name: showMenuNote, object: nil)
    }

    /// Opening the app while it already runs brings back the icon and shows the settings.
    @objc func showMenuAgain() {
        if statusItem == nil { setupMenu() }
        openSettings()
    }

    @objc func openSettings() {
        if settings == nil { settings = SettingsWindow(controller: self) }
        settings?.show()
    }

    // MARK: Changes from the settings window

    func setColors(fg: RGB, bg: RGB) {
        cfg.fg = fg; cfg.bg = bg
        Settings.save(cfg)
        panels.forEach { $0.recolor(cfg: cfg) }
        rebuildMenu()
    }

    func changeSpeed(to fps: Double) {
        cfg.fps = fps
        cfg = Settings.clamp(cfg)
        Settings.save(cfg)
        if !paused, timer != nil { startTimer() }
        rebuildMenu()
    }

    func update(_ change: (inout Config) -> Void) {
        change(&cfg)
        apply()
    }

    func build() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { Panel(screen: $0, cfg: cfg) }
        if !paused { startTimer() }
    }

    func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / cfg.fps, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            for p in s.panels where p.window.occlusionState.contains(.visible) {
                p.tick(fade: s.fade)
            }
        }
        t.tolerance = 0.02   // keep a tight beat
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func screensChanged() { build() }

    @objc func occlusionChanged() {
        // Fully covered or display asleep? Don't compute anything.
        let visible = panels.contains { $0.window.occlusionState.contains(.visible) }
        if visible, timer == nil, !paused { startTimer() }
        if !visible { timer?.invalidate(); timer = nil }
    }

    // MARK: Menu

    func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill",
                                     accessibilityDescription: "Life Wallpaper")
        statusItem = item
        rebuildMenu()
    }

    func rebuildMenu() {
        let m = NSMenu()
        m.addItem(action(paused ? "Resume" : "Pause", #selector(togglePause), key: "p"))
        m.addItem(action("New Soup", #selector(reseed), key: "r"))
        m.addItem(.separator())

        m.addItem(submenu("Speed", speeds.enumerated().map { i, s in
            action(s.0, #selector(setSpeed(_:)), tag: i, on: cfg.fps == s.1)
        }))
        m.addItem(submenu("Cell Size", sizes.enumerated().map { i, s in
            action(s.0, #selector(setSize(_:)), tag: i, on: cfg.cell == s.1)
        }))
        m.addItem(submenu("Color", palettes.enumerated().map { i, p in
            action(p.0, #selector(setPalette(_:)), tag: i, on: hex(cfg.fg) == p.1 && hex(cfg.bg) == p.2)
        }))
        let snap = cfg.fade == 0 && cfg.trail == 0
        m.addItem(submenu("Motion", [
            action("Smooth — crossfade and afterglow", #selector(setMotion(_:)), tag: 0, on: !snap),
            action("Snap — one hard step per generation", #selector(setMotion(_:)), tag: 1, on: snap),
        ]))
        m.addItem(action("Settings…", #selector(openSettings), key: ","))
        m.addItem(.separator())
        m.addItem(action("Launch at Login", #selector(toggleLogin),
                         on: SMAppService.mainApp.status == .enabled))
        m.addItem(action("Hide Menu Bar Icon", #selector(hideIcon)))
        m.addItem(.separator())
        m.addItem(action("Quit Life Wallpaper", #selector(quit), key: "q"))
        statusItem?.menu = m
    }

    func action(_ title: String, _ sel: Selector, key: String = "", tag: Int = 0, on: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self; i.tag = tag; i.state = on ? .on : .off
        return i
    }

    func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach { sub.addItem($0) }
        i.submenu = sub
        return i
    }

    func apply() {
        cfg = Settings.clamp(cfg)
        Settings.save(cfg)
        build()
        rebuildMenu()
        settings?.refresh()
    }

    @objc func togglePause() {
        paused.toggle()
        if paused { timer?.invalidate(); timer = nil } else { startTimer() }
        rebuildMenu()
    }

    @objc func reseed() {
        panels.forEach { $0.world.seedAll(); $0.tick(fade: 0) }
    }

    @objc func setSpeed(_ s: NSMenuItem) { cfg.fps = speeds[s.tag].1; apply() }
    @objc func setSize(_ s: NSMenuItem) { cfg.cell = sizes[s.tag].1; apply() }

    @objc func setPalette(_ s: NSMenuItem) {
        let p = palettes[s.tag]
        cfg.fg = parseHex(p.1)!; cfg.bg = parseHex(p.2)!
        apply()
    }

    @objc func setMotion(_ s: NSMenuItem) {
        if s.tag == 1 { cfg.fade = 0; cfg.trail = 0 } else { cfg.fade = -1; cfg.trail = 10 }
        apply()
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = "\(error.localizedDescription)\n\nMove Life Wallpaper.app into Applications and try again, or add it under System Settings › General › Login Items."
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
        rebuildMenu()
    }

    @objc func hideIcon() {
        let a = NSAlert()
        a.messageText = "Hide the menu bar icon?"
        a.informativeText = "The wallpaper keeps running. To get the icon back, just open Life Wallpaper again from Applications."
        a.addButton(withTitle: "Hide")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Settings.d.set(true, forKey: "hideMenuBarIcon")
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - GIF export (used for the README preview)

func exportGIF(cfg: Config, path: String, width: Int, height: Int, frames: Int) -> Int32 {
    let gw = width / cfg.cell, gh = height / cfg.cell
    let world = World(w: gw, h: gh, density: cfg.density, trail: cfg.trail)
    guard let r = Renderer(gw: gw, gh: gh, cfg: cfg, trailMax: world.trailMax),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                     UTType.gif.identifier as CFString, frames, nil)
    else { return 1 }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProps = [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFDelayTime: 1.0 / cfg.fps]] as CFDictionary
    // Scale the cell bitmap up to the requested size without smoothing, like the wallpaper does.
    guard let big = CGContext(data: nil, width: gw * cfg.cell, height: gh * cfg.cell, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return 1 }
    big.interpolationQuality = .none
    for _ in 0..<60 { world.step() }   // skip the noisy first generations
    for _ in 0..<frames {
        if let img = r.image(age: world.age) {
            big.draw(img, in: CGRect(x: 0, y: 0, width: big.width, height: big.height))
            if let scaled = big.makeImage() { CGImageDestinationAddImage(dest, scaled, frameProps) }
        }
        world.step()
    }
    return CGImageDestinationFinalize(dest) ? 0 : 1
}

// MARK: - Start

// Command-line flags override saved settings for this run only.
var cfg = Settings.load()
var gifPath: String?
var gifFrames = 90, gifW = 720, gifH = 420
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--cell":    if let v = it.next(), let n = Int(v) { cfg.cell = n }
    case "--fps":     if let v = it.next(), let n = Double(v) { cfg.fps = n }
    case "--density": if let v = it.next(), let n = Double(v) { cfg.density = n }
    case "--trail":   if let v = it.next(), let n = Int(v) { cfg.trail = n }
    case "--fade":    if let v = it.next(), let n = Double(v) { cfg.fade = n }
    case "--color":   if let v = it.next(), let c = parseHex(v) { cfg.fg = c }
    case "--bg":      if let v = it.next(), let c = parseHex(v) { cfg.bg = c }
    case "--no-menu": cfg.showMenu = false
    case "--export-gif": gifPath = it.next()
    case "--frames":  if let v = it.next(), let n = Int(v) { gifFrames = n }
    case "--size":    if let v = it.next() {
                          let p = v.split(separator: "x").compactMap { Int($0) }
                          if p.count == 2 { gifW = p[0]; gifH = p[1] }
                      }
    case "--help", "-h":
        print("""
        Life Wallpaper — Conway's Game of Life on your desktop

          --cell N        points per cell (3–80, default 14)
          --fps N         generations per second (0.5–30, default 8)
          --density N     initial density (0.02–0.9, default 0.16)
          --trail N       afterglow generations for dead cells (0–60, default 10)
          --fade N        crossfade seconds between generations (default: auto)
          --color HEX     live cell color (default 66EBBF)
          --bg HEX        background color (default 0B0E11)
          --no-menu       run without the menu bar icon
          --export-gif P  render an animated GIF to P and exit (--frames N, --size WxH)
        """)
        exit(0)
    default: break
    }
}
cfg = Settings.clamp(cfg)

if let p = gifPath { exit(exportGIF(cfg: cfg, path: p, width: gifW, height: gifH, frames: gifFrames)) }

// One instance at a time: take a file lock, or quit right away.
let lockPath = NSHomeDirectory() + "/.life-wallpaper.lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    // Opening the app again brings a hidden menu bar icon back.
    Settings.d.removeObject(forKey: "hideMenuBarIcon")
    DistributedNotificationCenter.default().postNotificationName(showMenuNote, object: nil,
                                                                 userInfo: nil, deliverImmediately: true)
    FileHandle.standardError.write(Data("life-wallpaper is already running — this instance quits\n".utf8))
    exit(0)
}

let app = NSApplication.shared
let controller = Controller(cfg: cfg)
app.delegate = controller
app.setActivationPolicy(.accessory)   // no Dock icon, no app menu
app.run()
