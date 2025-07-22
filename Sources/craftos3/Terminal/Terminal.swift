import SDL3

public protocol Terminal: Actor {
    var size: SDLSize {get async}
    var cursor: SDLPoint {get async}
    var canBlink: Bool {get async}
    var grayscale: Bool {get async}
    var palette: [SDLColor] {get async}
    var termColors: UInt8 {get async}

    func render() async
    func showMessage(named: String, message: String, type: SDLMessageBox.BoxType) async
    func set(title: String) async throws
    func resize(to: SDLSize) async throws
    func set(textColor: UInt8) async
    func set(backgroundColor: UInt8) async
    func set(cursor: SDLPoint) async
    func set(cursorBlink: Bool) async
    func write(text: [UInt8], colors: [UInt8], at: SDLPoint) async
    func clear(with: UInt8) async
    func clear(line: Int, with: UInt8) async
    func scroll(lines: Int, with: UInt8) async
    func setPalette(color: UInt8, to: SDLColor) async

    @MainActor static func initialize() async throws
    @MainActor static func pollEvents() async throws -> Bool
    @MainActor static func quit()
}

public extension Terminal {
    func write(text: String, colors: UInt8, at: SDLPoint) async {
        await write(text: text.bytes, colors: [UInt8](repeating: colors, count: text.bytes.count), at: at)
    }
}

public enum TerminalConstants {
    public static let defaultPalette: [SDLColor] = [
        SDLColor(rgb: 0xf0f0f0),
        SDLColor(rgb: 0xf2b233),
        SDLColor(rgb: 0xe57fd8),
        SDLColor(rgb: 0x99b2f2),
        SDLColor(rgb: 0xdede6c),
        SDLColor(rgb: 0x7fcc19),
        SDLColor(rgb: 0xf2b2cc),
        SDLColor(rgb: 0x4c4c4c),
        SDLColor(rgb: 0x999999),
        SDLColor(rgb: 0x4c99b2),
        SDLColor(rgb: 0xb266e5),
        SDLColor(rgb: 0x3366cc),
        SDLColor(rgb: 0x7f664c),
        SDLColor(rgb: 0x57a64e),
        SDLColor(rgb: 0xcc4c4c),
        SDLColor(rgb: 0x111111)
    ]

    public static let fontWidth: Int32 = 6
    public static let fontHeight: Int32 = 9
}
