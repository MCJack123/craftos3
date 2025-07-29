import SDL3

class RenderEvent: SDLUserEventBase, SDLUserEvent {
    nonisolated(unsafe) static var _type: UInt32!
    public convenience init(for term: SDLTerminal) {
        self.init()
        self.data1 = Unmanaged<SDLTerminal>.passRetained(term).toOpaque()
    }
    public var term: SDLTerminal {
        return Unmanaged<SDLTerminal>.fromOpaque(data1!).takeRetainedValue()
    }
}

internal actor SDLTerminal: Terminal {
    private static var fontScale: Int32 = 2
    private static var font: SDLSurface!
    private static var idGenerator = SystemRandomNumberGenerator()

    @MainActor
    static func initialize() async throws {
        try SDLInit(for: [.video, .audio])
        let bmp = try SDLSurface(width: 128, height: 175, format: .rgb565, from: font_image, pitch: 256)
        font = try await bmp.convert(to: .rgba32)
        try await font.set(colorKey: SDLColor(rgb: 0))
    }

    @MainActor
    static func pollEvents() async throws -> Bool {
        while true {
            if let ev = SDLEvent.poll() {
                if ev is SDLQuitEvent {
                    return true
                } else if let rev = ev as? RenderEvent {
                    await rev.term.update()
                } else if let windowEvent = ev as? SDLWindowedEvent, let terminal = try TerminalConstants.terminals.first(where: {try ($0.terminal as? SDLTerminal)?.window.id == windowEvent.windowID})?.terminal {
                    if let keyEvent = ev as? SDLKeyboardEvent, let key = keymap[keyEvent.key] {
                        if keyEvent.pressed {
                            await Computer.post(event: [.value("key"), .value(key), .value(keyEvent.repeat)], for: terminal)
                        } else {
                            await Computer.post(event: [.value("key_up"), .value(key)], for: terminal)
                        }
                    } else if let textEvent = ev as? SDLTextInputEvent, textEvent.text.allSatisfy({!$0.isASCII || ($0.asciiValue! >= 0x20 && $0.asciiValue! < 0x7F)}) {
                        await Computer.post(event: [.value("char"), .value(textEvent.text)], for: terminal)
                    }
                }
            }
            try await Task.sleep(nanoseconds: 1000000)
        }
    }

    @MainActor
    static func quit() {
        font = nil
        SDLQuit()
    }

    public let id: Int
    public var size: SDLSize
    public var cursor: SDLPoint = SDLPoint(x: 1, y: 1)
    public var canBlink: Bool = true
    public var termColors: UInt8 = 0xF0
    public var grayscale: Bool = false
    public var palette: [SDLColor] = TerminalConstants.defaultPalette
    public var screen: [[UInt8]]
    public var colors: [[UInt8]]
    private var blink: Bool = true
    private var changed: Bool = true

    private let window: SDLWindow
    private var surf: SDLSurface?
    private var charScale: Int32 = 2
    private var charWidth: Int32 {return TerminalConstants.fontWidth * charScale}
    private var charHeight: Int32 {return TerminalConstants.fontHeight * charScale}
    private var dpiScale: Int32 = 1
    // TEMP
    private var renderTask: Task<(), Never>!
    private var blinkTimer = 0

    init(size: SDLSize, named title: String) async throws {
        id = Int(truncatingIfNeeded: SDLTerminal.idGenerator.next())
        self.size = size
        screen = [[UInt8]](repeating: [UInt8](repeating: 0x20, count: Int(size.width)), count: Int(size.height))
        colors = [[UInt8]](repeating: [UInt8](repeating: 0xF0, count: Int(size.width)), count: Int(size.height))

        let charScale = charScale
        window = try await MainActor.run {return try SDLWindow(named: title, width: (size.width * Int32(TerminalConstants.fontWidth) + 4) * charScale, height: (size.height * Int32(TerminalConstants.fontHeight) + 4) * charScale, flags: [.resizable, .inputFocus, .highPixelDensity])}
        try await window.startTextInput()
    
        // TEMP
        renderTask = Task { [weak self] in
            while self != nil {
                await self?.render()
                await self?.doBlink()
                try! await Task.sleep(nanoseconds: 50000000)
            }
        }

        await addSelf()
    }

    deinit {
        Task {
            await TerminalConstants.cleanupTerminals()
        }
    }

    // TEMP
    private func doBlink() {
        if self.canBlink {
            blinkTimer += 1
            if blinkTimer > 7 {
                blinkTimer = 0
                self.blink = !self.blink
                self.changed = true
            }
        } else {
            blinkTimer = 0
        }
    }

    private func grayscalify(color: SDLColor) -> SDLColor {
        if grayscale {
            let y = (color.red + color.green + color.blue) / 3
            return SDLColor(red: y, green: y, blue: y)
        }
        return color
    }

    private func getCharacterRect(for c: UInt8) -> SDLRect {
        let scale = 2/SDLTerminal.fontScale
        let x: Int32 = ((TerminalConstants.fontWidth + 2) * scale) * Int32(c & 0x0F) + scale
        let y: Int32 = ((TerminalConstants.fontHeight + 2) * scale) * Int32(c >> 4) + scale
        return SDLRect(
            x: x,
            y: y,
            width: TerminalConstants.fontWidth * scale,
            height: TerminalConstants.fontHeight * scale
        )
    }

    private func drawChar(_ c: UInt8, x: Int, y: Int, fg: SDLColor, bg: SDLColor, transparent: Bool) async -> Bool {
        let srcrect = getCharacterRect(for: c)
        let destrect = SDLRect(
            x: (Int32(x) * charWidth + 2 * charScale) * dpiScale,
            y: (Int32(y) * charHeight + 2 * charScale) * dpiScale,
            width: charWidth * dpiScale,
            height: charHeight * dpiScale
        )
        if !transparent && bg != self.palette[15] {
            do {
                try await surf!.fill(in: destrect, with: grayscalify(color: bg))
            } catch {
                await printError(error)
                return false
            }
        }
        if c != 0 && c != 0x20 {
            do {
                // TODO: data race safety
                try await SDLTerminal.font.set(colorMod: grayscalify(color: fg))
                try await surf!.blitScaled(from: SDLTerminal.font, in: srcrect, to: destrect, with: .nearest)
            } catch {
                await printError(error)
                return false
            }
        }
        return true
    }

    func render() async {
        if !changed {return}
        changed = false
        let surf: SDLSurface
        if let m_surf = self.surf {
            surf = m_surf
        } else {
            do {
                let winSize = try await window.size
                surf = try SDLSurface(width: winSize.width, height: winSize.height, format: .rgb24)
                self.surf = surf
            } catch let error {
                await printError(error)
                return
            }
        }
        do {
            try await surf.fill(in: nil, with: palette[15])
        } catch {
            await printError(error)
            return
        }
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                if await !drawChar(screen[y][x], x: x, y: y, fg: palette[Int(colors[y][x] & 0x0F)], bg: palette[Int(colors[y][x] >> 4)], transparent: false) {
                    return
                }
            }
        }
        if blink && cursor.x >= 1 && cursor.x <= size.width && cursor.y >= 1 && cursor.y <= size.height {
            if await !drawChar(0x5F, x: Int(cursor.x) - 1, y: Int(cursor.y) - 1, fg: palette[Int(termColors & 0x0F)], bg: SDLColor(rgb: 0), transparent: true) {
                return
            }
        }
        try! RenderEvent(for: self).push()
    }

    func update() async {
        if let surf = surf {
            do {
                let winsurf = try await window.surface
                try await winsurf.blit(from: surf, in: nil, to: nil)
                try await window.updateSurface()
            } catch let error {
                await printError(error)
            }
        }
    }

    func showMessage(named: String, message: String, type: SDLMessageBox.BoxType) async {
        do {
            try await window.showSimpleMessageBox(with: type, title: named, message: message)
        } catch {}
    }

    func set(title: String) async throws {
        try await window.set(title: title)
    }

    func resize(to: SDLSize) async throws {
        
    }

    func set(textColor: UInt8) async {
        termColors = (termColors & 0xF0) | (textColor & 0x0F)
        changed = true
    }

    func set(backgroundColor: UInt8) async {
        termColors = (termColors & 0x0F) | (backgroundColor & 0x0F) << 4
    }

    func set(cursor: SDLPoint) {
        self.cursor = cursor
        changed = true
    }

    func set(cursorBlink: Bool) {
        self.canBlink = cursorBlink
        if !cursorBlink {
            blink = false
        }
        changed = true
    }

    func write(text: [UInt8], colors: [UInt8], at: SDLPoint) {
        if at.y < 1 || at.y > size.height {
            return
        }
        var x = Int(at.x) - 1
        var start = 0
        if x < 0 {
            start -= x
            x = 0
            if start >= text.count {
                return
            }
        }
        var length = text.count
        if x + length >= size.width {
            length = Int(size.width) - x
        }
        screen[Int(at.y)-1].replaceSubrange(x..<(x + length), with: text[start..<(start + length)])
        self.colors[Int(at.y)-1].replaceSubrange(x..<(x + length), with: colors[start..<(start + length)])
        changed = true
    }

    func clear(with colors: UInt8) {
        screen = [[UInt8]](repeating: [UInt8](repeating: 0x20, count: Int(size.width)), count: Int(size.height))
        self.colors = [[UInt8]](repeating: [UInt8](repeating: colors, count: Int(size.width)), count: Int(size.height))
        changed = true
    }

    func clear(line: Int, with colors: UInt8) {
        if line < 1 || line > size.height {
            return
        }
        screen[line - 1] = [UInt8](repeating: 0x20, count: Int(size.width))
        self.colors[line - 1] = [UInt8](repeating: colors, count: Int(size.width))
        changed = true
    }

    func scroll(lines: Int, with colors: UInt8) {
        
    }

    func setPalette(color: UInt8, to: SDLColor) {
        if color > 15 {return}
        palette[Int(color)] = to
        changed = true
    }
}

fileprivate let keymap: [SDLKeycode: Int] = [
    .one: 2,
    .two: 3,
    .three: 4,
    .four: 5,
    .five: 6,
    .six: 7,
    .seven: 8,
    .eight: 9,
    .nine: 10,
    .zero: 11,
    .minus: 12,
    .equals: 13,
    .backspace: 14,
    .tab: 15,
    .q: 16,
    .w: 17,
    .e: 18,
    .r: 19,
    .t: 20,
    .y: 21,
    .u: 22,
    .i: 23,
    .o: 24,
    .p: 25,
    .leftbracket: 26,
    .rightbracket: 27,
    .return: 28,
    .lctrl: 29,
    .a: 30,
    .s: 31,
    .d: 32,
    .f: 33,
    .g: 34,
    .h: 35,
    .j: 36,
    .k: 37,
    .l: 38,
    .semicolon: 39,
    .quote: 40,
    .backquote: 41,
    .lshift: 42,
    .backslash: 43,
    .z: 44,
    .x: 45,
    .c: 46,
    .v: 47,
    .b: 48,
    .n: 49,
    .m: 50,
    .comma: 51,
    .period: 52,
    .slash: 53,
    .rshift: 54,
    .kp_multiply: 55,
    .lalt: 56,
    .space: 57,
    .capslock: 58,
    .f1: 59,
    .f2: 60,
    .f3: 61,
    .f4: 62,
    .f5: 63,
    .f6: 64,
    .f7: 65,
    .f8: 66,
    .f9: 67,
    .f10: 68,
    .numlockclear: 69,
    .scrolllock: 70,
    .kp_7: 71,
    .kp_8: 72,
    .kp_9: 73,
    .kp_minus: 74,
    .kp_4: 75,
    .kp_5: 76,
    .kp_6: 77,
    .kp_plus: 78,
    .kp_1: 79,
    .kp_2: 80,
    .kp_3: 81,
    .kp_0: 82,
    .kp_decimal: 83,
    .f11: 87,
    .f12: 88,
    .f13: 100,
    .f14: 101,
    .f15: 102,
    .kp_equals: 141,
    .kp_at: 145,
    .kp_colon: 146,
    .stop: 149,
    .kp_enter: 156,
    .rctrl: 157,
    .kp_comma: 179,
    .kp_divide: 181,
    .ralt: 184,
    .pause: 197,
    .home: 199,
    .up: 200,
    .pageup: 201,
    .left: 203,
    .right: 205,
    .end: 207,
    .down: 208,
    .pagedown: 209,
    .insert: 210,
    .delete: 211,
]
