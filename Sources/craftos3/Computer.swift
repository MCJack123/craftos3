import Lua
import LuaLib
import SDL3
import Foundation
import Collections

public actor Computer {
    private class WeakReference {
        public weak var computer: Computer?
        fileprivate init(_ computer: Computer) {self.computer = computer}
    }

    @MainActor
    private static var computers = [WeakReference]()

    public static func computerPath(for id: Int) -> URL {
        return FSManager.basePath.appending(path: "computer/\(id)", directoryHint: .isDirectory)
    }

    @MainActor
    internal static func post(event: [LuaValue], for terminal: any Terminal) async {
        for ref in computers {
            if let computer = ref.computer {
                if await computer.terminal.id == terminal.id {
                    await computer.push(event: event)
                    return
                }
                // TODO: peripherals
            }
        }
    }

    @MainActor
    private static func cleanupComputers() {
        computers = computers.filter {$0.computer != nil}
    }

    public let id: Int
    public let terminal: any Terminal
    public var luaState: LuaState?
    public let filesystem: FSManager
    private var eventQueue = Deque<[LuaValue]>()
    private var eventQueueWait: CheckedContinuation<Void, any Error>?

    internal init(with id: Int) async throws {
        self.id = id
        filesystem = try FSManager(withRoot: Computer.computerPath(for: id))
        try await filesystem.add(fileMountAtPath: "rom", for: FSManager.romPath.appending(component: "rom", directoryHint: .isDirectory), readOnly: true)
        terminal = try await SDLTerminal(size: SDLSize(width: 51, height: 19), named: "CraftOS Terminal")
        try await terminal.set(title: "CraftOS Terminal: Computer \(id)")
        await addSelf()
    }

    deinit {
        Task {
            await Computer.cleanupComputers()
        }
    }

    @MainActor
    private func addSelf() {
        Computer.computers.append(WeakReference(self))
    }

    private func push(event: [LuaValue]) {
        if eventQueue.count >= 255 {
            return // TODO: standards mode?
        }
        eventQueue.append(event)
        if let continuation = eventQueueWait {
            eventQueueWait = nil
            continuation.resume()
        }
    }

    internal func waitForEvent() async throws -> [LuaValue] {
        while eventQueue.isEmpty {
            try await withCheckedThrowingContinuation { continuation in
                self.eventQueueWait = continuation
            }
        }
        return eventQueue.popFirst()!
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
        await state.global(named: "_CC_DEFAULT_SETTINGS", value: .value("bios.use_multishell=false,shell.autocomplete=false"))
        await state.global(named: "_HOST", value: .value("ComputerCraft 1.116.1 (CraftOS-PC v3.0)"))
        guard case let .table(os) = await state.global(named: "os") else {return}
        await os.set(index: "queueEvent", value: .value(LuaSwiftFunction.empty))
        await os.set(index: "shutdown", value: .value(LuaSwiftFunction.empty))
        do {
            let bios = try Data(contentsOf: URL(fileURLWithPath: "bios.lua", relativeTo: FSManager.romPath))
            let fn = LuaFunction.lua(try await LuaLoad.load(from: bios.map {$0}, named: "@bios.lua".bytes, mode: .text, environment: .table(state.globalTable!), in: state))
            let thread = await LuaThread(in: state, for: fn)
            var filter = try await thread.resume(in: state).first?.optional
            while await thread.state != .dead {
                var args: [LuaValue]
                repeat {
                    args = try await waitForEvent()
                } while args.first?.optional != nil && filter != nil && args.first?.optional != filter && args.first?.optional != .value("terminate")
                filter = try await thread.resume(in: state, with: args).first?.optional
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
