import Lua
import LuaLib
import SDL3

@LuaLibrary(named: "term")
internal final class TermAPI: TermMethods {
    private let computer: Computer
    var terminal: Terminal {get async {return computer.terminal}}

    public func nativePaletteColor(_ state: Lua, _ color: Int) async throws -> (Double, Double, Double) {
        let idx = color.trailingZeroBitCount
        if idx > 15 {
            throw await state.error("bad argument #1 (color out of range)")
        }
        let c = TerminalConstants.defaultPalette[idx]
        return (Double(c.red) / 255.0, Double(c.green) / 255.0, Double(c.blue) / 255.0)
    }

    public func nativePaletteColour(_ state: Lua, _ color: Int) async throws -> (Double, Double, Double) {
        return try await nativePaletteColor(state, color)
    }

    public func write(_ text: [UInt8]) async {
        let cursor = await terminal.cursor
        await terminal.write(text: text, colors: [UInt8](repeating: terminal.termColors, count: text.count), at: cursor)
        await terminal.set(cursor: SDLPoint(x: cursor.x + Int32(text.count), y: cursor.y))
    }

    public func scroll(_ lines: Int) async {
        await terminal.scroll(lines: lines, with: terminal.termColors)
    }

    public func getCursorPos() async -> (Int, Int) {
        let cursor = await terminal.cursor
        return (Int(cursor.x), Int(cursor.y))
    }

    public func setCursorPos(_ x: Int, _ y: Int) async {
        await terminal.set(cursor: SDLPoint(x: Int32(x), y: Int32(y)))
    }

    public func getCursorBlink() async -> Bool {
        return await terminal.canBlink
    }

    public func setCursorBlink(_ value: Bool) async {
        await terminal.set(cursorBlink: value)
    }

    public func getSize() async -> (Int, Int) {
        let size = await terminal.size
        return (Int(size.width), Int(size.height))
    }

    public func clear() async {
        await terminal.clear(with: terminal.termColors)
    }

    public func clearLine() async {
        await terminal.clear(line: Int(await terminal.cursor.y), with: terminal.termColors)
    }

    public func getTextColor() async -> Int {
        return 1 << (await terminal.termColors & 0x0F)
    }

    public func getTextColour() async  -> Int {
        return 1 << (await terminal.termColors & 0x0F)
    }

    public func setTextColor(_ value: Int) async {
        await terminal.set(textColor: UInt8(value.trailingZeroBitCount))
    }

    public func setTextColour(_ value: Int) async {
        await terminal.set(textColor: UInt8(value.trailingZeroBitCount))
    }

    public func getBackgroundColor() async -> Int {
        return 1 << (await terminal.termColors >> 4)
    }

    public func getBackgroundColour() async -> Int {
        return 1 << (await terminal.termColors >> 4)
    }

    public func setBackgroundColor(_ value: Int) async {
        await terminal.set(backgroundColor: UInt8(value.trailingZeroBitCount))
    }

    public func setBackgroundColour(_ value: Int) async {
        await terminal.set(backgroundColor: UInt8(value.trailingZeroBitCount))
    }

    public func isColor() async -> Bool {
        return await !terminal.grayscale
    }

    public func isColour() async -> Bool {
        return await !terminal.grayscale
    }

    public func blit(_ state: Lua, _ text: [UInt8], _ fg: [UInt8], _ bg: [UInt8]) async throws {
        if text.count != fg.count || fg.count != bg.count {
            throw await state.error("Arguments must be the same length")
        }
        var colors = [UInt8](repeating: 0, count: text.count)
        for i in 0..<text.count {
            let fc = fg[i], bc = bg[i]
            var c: UInt8 = 0
            if fc >= 0x30 && fc <= 0x39 {
                c |= (fc - 0x30)
            } else if fc >= 0x41 && fc <= 0x46 {
                c |= (fc - 0x37)
            } else if fc >= 0x61 && fc <= 0x66 {
                c |= (fc - 0x57)
            }
            if bc >= 0x30 && bc <= 0x39 {
                c |= (bc - 0x30) << 4
            } else if bc >= 0x41 && bc <= 0x46 {
                c |= (bc - 0x37) << 4
            } else if bc >= 0x61 && bc <= 0x66 {
                c |= (bc - 0x57) << 4
            }
            colors[i] = c
        }
        let cursor = await terminal.cursor
        await terminal.write(text: text, colors: colors, at: cursor)
        await terminal.set(cursor: SDLPoint(x: cursor.x + Int32(text.count), y: cursor.y))
    }

    public func setPaletteColor(_ state: Lua, _ color: Int, _ r: Double, _ g: Double?, _ b: Double?) async throws {
        let idx = color.trailingZeroBitCount
        if idx > 15 {
            throw await state.error("bad argument #1 (color out of range)")
        }
        if g == nil && b == nil {
            await terminal.setPalette(color: UInt8(idx), to: SDLColor(rgb: UInt32(r)))
        } else {
            guard let g = g, let b = b else {
                throw await state.error("bad argument (number expected, got nil)")
            }
            await terminal.setPalette(color: UInt8(idx), to: SDLColor(red: UInt8(r * 255), green: UInt8(g * 255), blue: UInt8(b * 255)))
        }
    }

    public func setPaletteColour(_ state: Lua, _ color: Int, _ r: Double, _ g: Double?, _ b: Double?) async throws {
        return try await setPaletteColor(state, color, r, g, b)
    }

    public func getPaletteColor(_ state: Lua, _ color: Int) async throws -> (Double, Double, Double) {
        let idx = color.trailingZeroBitCount
        if idx > 15 {
            throw await state.error("bad argument #1 (color out of range)")
        }
        let c = await terminal.palette[idx]
        return (Double(c.red) / 255.0, Double(c.green) / 255.0, Double(c.blue) / 255.0)
    }

    public func getPaletteColour(_ state: Lua, _ color: Int) async throws -> (Double, Double, Double) {
        return try await getPaletteColor(state, color)
    }

    internal init(for computer: Computer) {
        self.computer = computer
    }
}
