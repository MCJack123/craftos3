import Lua
import LuaLib
import SDL3
import Foundation

public actor Computer {
    public let id: Int
    public let terminal: any Terminal
    public var luaState: LuaState?

    // TEMP
    public let basePath: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    internal init(with id: Int) async throws {
        self.id = id
        terminal = try await SDLTerminal(size: SDLSize(width: 51, height: 19), named: "CraftOS Terminal")
    }

    internal func run() async {
        luaState = await LuaState(withLibraries: true)
        let state = luaState!
        await state.globalTable.load(library: FSAPI(for: self))
        await state.globalTable.load(library: PeripheralAPI(for: self))
        await state.globalTable.load(library: RedstoneAPI(for: self))
        await state.globalTable.load(library: TermAPI(for: self))
        await state.global(named: "rs", value: state.global(named: "redstone"))
        await state.global(named: "require", value: .nil)
        await state.global(named: "package", value: .nil)
        await state.global(named: "_CC_DEFAULT_SETTINGS", value: .value("bios.use_multishell=false"))
        guard case let .table(os) = await state.global(named: "os") else {return}
        await os.set(index: "queueEvent", value: .value(LuaSwiftFunction.empty))
        do {
            let bios = try Data(contentsOf: URL(fileURLWithPath: "bios.lua", relativeTo: basePath))
            let fn = LuaFunction.lua(try await LuaLoad.load(from: bios.map {$0}, named: "@bios.lua".bytes, mode: .text, environment: .table(state.globalTable!), in: state))
            let thread = await LuaThread(in: state, for: fn)
            var filter = try await thread.resume(in: state)
            while await thread.state != .dead {
                // TODO
                try await Task.sleep(nanoseconds: 1000000000)
            }
        } catch let error {
            await printError(error)
            await terminal.clear(with: 0xFE)
            await terminal.set(cursorBlink: false)
            await terminal.write(text: "Error running computer", colors: 0xFE, at: SDLPoint(x: 1, y: 1))
            if let err = error as? Lua.LuaError {
                switch err {
                    case .luaError(let message):
                        await terminal.write(text: await message.toString, colors: 0xFE, at: SDLPoint(x: 1, y: 2))
                    case .runtimeError(let message):
                        await terminal.write(text: message, colors: 0xFE, at: SDLPoint(x: 1, y: 2))
                    case .vmError:
                        await terminal.write(text: "Internal VM error", colors: 0xFE, at: SDLPoint(x: 1, y: 2))
                    case .internalError:
                        await terminal.write(text: "Internal error", colors: 0xFE, at: SDLPoint(x: 1, y: 2))
                }
            } else {
                await terminal.write(text: error.localizedDescription, colors: 0xFE, at: SDLPoint(x: 1, y: 2))
            }
            await terminal.write(text: "CraftOS-PC may be installed incorrectly", colors: 0xFE, at: SDLPoint(x: 1, y: 3))
        }
        luaState = nil
        return
    }
}
