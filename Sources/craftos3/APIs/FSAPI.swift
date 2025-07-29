import Lua
import LuaLib
import Foundation

@LuaLibrary(named: "fs")
internal final class FSAPI {
    private let computer: Computer

    private static let specialChars: Set<Character> = ["\"", "*", ":", "<", ">", "?", "|"]

    private static func sanitize(_ path: String, allowWildcards: Bool = false) -> String {
        return path
            // replace \ with /
            .replacing("\\", with: "/")
            // remove leading slash so we don't get funny absolute URL issues
            .drop {$0 == "/"}
            // remove special characters
            .filter {!FSAPI.specialChars.contains($0) || (allowWildcards && $0 == "*")}
            // trim components
            .replacing(/\/ +/, with: "/")
            .replacing(/\ +\//, with: "/")
            .replacing(/^ +/, with: "")
            .replacing(/\ +$/, with: "")
            // replace ... with .
            .replacing(/\/\.{3,}\//, with: "/./")
            .replacing(/^\.{3,}\//, with: "./")
            .replacing(/\/\.{3,}$/, with: "/.")
            .replacing(/^\.{3,}$/, with: ".")
            // trim last component if # >= 255
            .replacing(/[^\/]{255,}$/, with: {$0.0[..<$0.0.index($0.0.startIndex, offsetBy: 255)]})
    }

    public func list(_ state: Lua, _ path: String) async throws -> LuaTable {
        do {
            let contents = try await computer.filesystem.list(at: FSAPI.sanitize(path))
            return LuaTable(from: contents.map {.value($0)})
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func combine(_ state: Lua, _ args: LuaArgs) async throws -> String {
        var url = URL(string: FSAPI.sanitize(try await args.checkString(at: 1), allowWildcards: true) + "/", relativeTo: URL(string: "virtual:///"))!
        if args.count > 1 {
            for i in 2...args.count {
                let str = FSAPI.sanitize(try await args.checkString(at: i), allowWildcards: true)
                if str != "" {
                    url = URL(string: str + "/", relativeTo: url)!
                }
            }
        }
        return String(url.path.drop {$0 == "/"})
    }

    public func getName(_ state: Lua, _ path: String) async throws -> String {
        return URL(fileURLWithPath: FSAPI.sanitize(path, allowWildcards: true), relativeTo: nil).lastPathComponent
    }

    public func getDir(_ state: Lua, _ path: String) async throws -> String {
        return URL(string: FSAPI.sanitize(path, allowWildcards: true), relativeTo: URL(string: "virtual:///")!)!.deletingLastPathComponent().path
    }

    public func getSize(_ state: Lua, _ path: String) async throws -> Int {
        do {
            guard let attr = try await computer.filesystem.stat(at: FSAPI.sanitize(path)) else {
                throw FSManager.FilesystemError(message: "No such file")
            }
            return attr.size
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func exists(_ state: Lua, _ path: String) async throws -> Bool {
        do {
            return try await computer.filesystem.stat(at: FSAPI.sanitize(path)) != nil
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func isDir(_ state: Lua, _ path: String) async throws -> Bool {
        do {
            guard let attr = try await computer.filesystem.stat(at: FSAPI.sanitize(path)) else {
                return false
            }
            return attr.isDir
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func isReadOnly(_ state: Lua, _ path: String) async throws -> Bool {
        do {
            guard let attr = try await computer.filesystem.stat(at: FSAPI.sanitize(path)) else {
                throw FSManager.FilesystemError(message: "No such file")
            }
            return attr.isReadOnly
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func makeDir(_ state: Lua, _ path: String) async throws {
        do {
            try await computer.filesystem.makeDir(at: FSAPI.sanitize(path))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func move(_ state: Lua, _ from: String, _ to: String) async throws {
        do {
            try await computer.filesystem.move(from: FSAPI.sanitize(from), to: FSAPI.sanitize(to))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func copy(_ state: Lua, _ from: String, _ to: String) async throws {
        do {
            try await computer.filesystem.copy(from: FSAPI.sanitize(from), to: FSAPI.sanitize(to))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func delete(_ state: Lua, _ path: String) async throws {
        do {
            try await computer.filesystem.delete(FSAPI.sanitize(path))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func open(_ state: Lua, _ path: String, _ mode: String) async throws -> LuaTable {
        guard let mode = FSManager.OpenFlags(from: mode) else {
            throw await state.error("bad argument #2 (invalid mode)")
        }
        do {
            return try await computer.filesystem.open(FSAPI.sanitize(path), mode: mode)
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func getDrive(_ state: Lua, _ path: String) async throws -> String {
        let (mount, _) = try await computer.filesystem.findMount(for: FSAPI.sanitize(path))
        if mount.mountLocation.count == 0 {
            return "hdd"
        } else {
            return mount.mountLocation.joined(separator: "/")
        }
    }
    
    public func getFreeSpace(_ state: Lua, _ path: String) async throws -> Int {
        do {
            return try await computer.filesystem.findMount(for: FSAPI.sanitize(path)).0.freeSpace
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func getCapacity(_ state: Lua, _ path: String) async throws -> Int {
        do {
            return try await computer.filesystem.findMount(for: FSAPI.sanitize(path)).0.capacity
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func attributes(_ state: Lua, _ path: String) async throws -> LuaTable? {
        do {
            guard let attr = try await computer.filesystem.stat(at: FSAPI.sanitize(path)) else {
                return nil
            }
            return LuaTable(from: [
                .value("size"): .value(attr.size),
                .value("isDir"): .value(attr.isDir),
                .value("isReadOnly"): .value(attr.isReadOnly),
                .value("created"): .value(attr.created),
                .value("modified"): .value(attr.modified)
            ])
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    internal init(for computer: Computer) {
        self.computer = computer
    }
}