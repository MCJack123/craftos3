import Lua
import LuaLib

@LuaLibrary(named: "redstone")
internal final class RedstoneAPI {
    private let computer: Computer

    public func getSides() -> LuaTable {
        return LuaTable(from: [.value("top"), .value("bottom"), .value("left"), .value("right"), .value("front"), .value("back")])
    }

    public func getInput(_ side: String) -> Bool {
        return false
    }

    public func getOutput(_ side: String) -> Bool {
        return false
    }

    public func setOutput(_ side: String, _ value: Bool) {

    }

    public func getAnalogInput(_ side: String) -> Int {
        return 0
    }

    public func getAnalogOutput(_ side: String) -> Int {
        return 0
    }

    public func setAnalogOutput(_ side: String, _ value: Int) {
        
    }

    public func getAnalogueInput(_ side: String) -> Int {
        return 0
    }

    public func getAnalogueOutput(_ side: String) -> Int {
        return 0
    }

    public func setAnalogueOutput(_ side: String, _ value: Int) {
        
    }

    public func getBundledInput(_ side: String) -> Int {
        return 0
    }

    public func getBundledOutput(_ side: String) -> Int {
        return 0
    }

    public func setBundledOutput(_ side: String, _ value: Int) {
        
    }

    public func testBundledInput(_ side: String, _ mask: Int) -> Bool {
        return false
    }

    internal init(for computer: Computer) {
        self.computer = computer
    }
}