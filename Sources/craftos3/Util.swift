import SDL3
import Lua
import Foundation

struct StandardError: TextOutputStream, Sendable {
    private static let handle = FileHandle.standardError

    public func write(_ string: String) {
        Self.handle.write(Data(string.utf8))
    }
}

@MainActor var stderr = StandardError()

@MainActor
func printError(_ items: Any...) {
    print(items, to: &stderr)
}