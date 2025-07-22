import Lua
import LuaLib
import Foundation

@LuaLibrary(named: "fs")
internal final class FSAPI {
    private let computer: Computer

    private func fixpath(_ path: String) async throws -> URL {
        return URL(fileURLWithPath: String(path.drop {$0 == "/"}), relativeTo: computer.basePath)
    }

    public func list(_ state: Lua, _ path: String) async throws -> LuaTable {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: try await fixpath(path), includingPropertiesForKeys: nil)
            return LuaTable(from: contents.map {$0.lastPathComponent}.sorted().map {.value($0)})
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func combine(_ state: Lua, _ args: LuaArgs) async throws -> String {
        var url = URL(string: try await args.checkString(at: 1) + "/", relativeTo: URL(string: "virtual:///"))!
        if args.count > 1 {
            for i in 2...args.count {
                let str = try await args.checkString(at: i)
                if str != "" {
                    url = URL(string: str + "/", relativeTo: url)!
                }
            }
        }
        return String(url.path.drop {$0 == "/"})
    }

    public func getName(_ state: Lua, _ path: String) async throws -> String {
        return URL(fileURLWithPath: path, relativeTo: nil).lastPathComponent
    }

    public func getDir(_ state: Lua, _ path: String) async throws -> String {
        return URL(string: path, relativeTo: URL(string: "virtual:///")!)!.deletingLastPathComponent().path
    }

    public func getSize(_ state: Lua, _ path: String) async throws -> Int {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: try await fixpath(path).path)
            return (attr[.size]! as! NSNumber).intValue
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func exists(_ state: Lua, _ path: String) async throws -> Bool {
        return FileManager.default.fileExists(atPath: try await fixpath(path).path)
    }

    public func isDir(_ state: Lua, _ path: String) async throws -> Bool {
        var isDir = false
        if !FileManager.default.fileExists(atPath: try await fixpath(path).path, isDirectory: &isDir) {
            return false
        }
        return isDir
    }

    public func isReadOnly(_ state: Lua, _ path: String) async throws -> Bool {
        return FileManager.default.isWritableFile(atPath: try await fixpath(path).path)
    }

    public func makeDir(_ state: Lua, _ path: String) async throws {
        do {
            try FileManager.default.createDirectory(at: try await fixpath(path), withIntermediateDirectories: true)
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func move(_ state: Lua, _ from: String, _ to: String) async throws {
        do {
            try FileManager.default.moveItem(at: try await fixpath(from), to: try await fixpath(to))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func copy(_ state: Lua, _ from: String, _ to: String) async throws {
        do {
            try FileManager.default.copyItem(at: try await fixpath(from), to: try await fixpath(to))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func delete(_ state: Lua, _ path: String) async throws {
        do {
            try FileManager.default.removeItem(at: try await fixpath(path))
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func open(_ state: Lua, _ path: String, _ mode: String) async throws -> LuaTable {
        let url = try await fixpath(path)
        do {
            if mode.contains("+") {
                if mode.contains("r") {
                    return try ReadWriteHandle(with: url, atEnd: false, truncate: false).table()
                } else if mode.contains("w") {
                    return try ReadWriteHandle(with: url, atEnd: false, truncate: true).table()
                } else if mode.contains("a") {
                    return try ReadWriteHandle(with: url, atEnd: true, truncate: false).table()
                }
            } else if mode.contains("r") {
                return try ReadHandle(with: url).table()
            } else if mode.contains("w") {
                return try WriteHandle(with: url, atEnd: false).table()
            } else if mode.contains("a") {
                return try WriteHandle(with: url, atEnd: true).table()
            }
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
        throw await state.error("bad argument #2 (invalid mode)")
    }

    public func getDrive(_ state: Lua, _ path: String) async throws -> String {
        return "hdd"
    }
    
    public func getFreeSpace(_ state: Lua, _ path: String) async throws -> Int {
        do {
            return (try FileManager.default.attributesOfFileSystem(forPath: try await fixpath(path).path)[.systemFreeSize]! as! NSNumber).intValue
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func getCapacity(_ state: Lua, _ path: String) async throws -> Int {
        do {
            return (try FileManager.default.attributesOfFileSystem(forPath: try await fixpath(path).path)[.systemSize]! as! NSNumber).intValue
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    public func attributes(_ state: Lua, _ path: String) async throws -> LuaTable? {
        if !FileManager.default.fileExists(atPath: try await fixpath(path).path) {
            return nil
        }
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: try await fixpath(path).path)
            return LuaTable(from: [
                .value("size"): .value((attr[.size]! as! NSNumber).intValue),
                .value("isDir"): .value((attr[.type]! as! NSString as String) == FileAttributeType.typeDirectory.rawValue),
                .value("isReadOnly"): .value((attr[.appendOnly]! as! NSNumber).intValue != 0),
                .value("created"): .value((attr[.creationDate]! as! NSDate).timeIntervalSince1970 * 1000),
                .value("modified"): .value((attr[.modificationDate]! as! NSDate).timeIntervalSince1970 * 1000)
            ])
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    internal init(for computer: Computer) {
        self.computer = computer
    }
}