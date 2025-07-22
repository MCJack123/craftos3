import Lua
import LuaLib

@LuaLibrary(named: "peripheral")
internal final class PeripheralAPI {
    private let computer: Computer

    public func isPresent(_ name: String) -> Bool {
        return false
    }

    public func getType(_ state: Lua, _ name: String) async throws -> [LuaValue] {
        throw await state.error("No such peripheral")
    }

    public func hasType(_ state: Lua, _ name: String, _ type: String) async throws -> Bool {
        throw await state.error("No such peripheral")
    }

    public func getMethods(_ state: Lua, _ name: String) async throws -> LuaTable {
        throw await state.error("No such peripheral")
    }

    public func call(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        let name = try await args.checkString(at: 1)
        let method = try await args.checkString(at: 2)
        throw await state.error("No such peripheral")
    }

    internal init(for computer: Computer) {
        self.computer = computer
    }
}
