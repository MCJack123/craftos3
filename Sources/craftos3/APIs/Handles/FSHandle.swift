import Lua
import LuaLib
import Foundation

internal protocol FSHandle {
    var handle: FileHandle {get}
    func seek(_: Lua, _: String?, _: Int?) async throws -> Int
    func close(_: Lua) async throws
}

internal extension FSHandle {
    func seek(_ state: Lua, _ whence: String?, _ offset: Int?) async throws -> Int {
        let whence = whence ?? "cur"
        let offset = offset ?? 0
        do {
            switch whence {
                case "set":
                    try handle.seek(toOffset: UInt64(offset))
                case "cur":
                    try handle.seek(toOffset: handle.offset() + UInt64(offset))
                case "end":
                    try handle.seekToEnd()
                    try handle.seek(toOffset: handle.offset() - UInt64(offset))
                default:
                    throw await state.error("bad argument #1 (invalid whence)")
            }
            return Int(try handle.offset())
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    func close(_ state: Lua) async throws {
        do {
            try handle.close()
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }
}

internal protocol FSReadableHandle: FSHandle {
    func read(_: Lua, _: Int?) async throws -> LuaValue
    func readAll(_: Lua) async throws -> [UInt8]?
    func readLine(_: Lua, _: Bool?) async throws -> [UInt8]?
}

internal extension FSReadableHandle {
    func read(_ state: Lua, _ count: Int?) async throws -> LuaValue {
        do {
            if let count = count {
                if let data = try handle.read(upToCount: count) {
                    return .value(data.map {$0})
                } else {
                    return .nil
                }
            } else {
                if let data = try handle.read(upToCount: 1), data.count == 1 {
                    return .value(data[0])
                } else {
                    return .nil
                }
            }
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    func readAll(_ state: Lua) async throws -> [UInt8]? {
        do {
            return try handle.readToEnd()?.map {$0}
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    func readLine(_ state: Lua, _ withNewline: Bool?) async throws -> [UInt8]? {
        do {
            var bytes = [UInt8]()
            while true {
                if let data = try handle.read(upToCount: 1) {
                    let byte = data[0]
                    if byte == 0x0A { // \n
                        if withNewline ?? false {
                            bytes.append(byte)
                        }
                        break
                    }
                    bytes.append(byte)
                } else {
                    if bytes.count == 0 {
                        return nil
                    }
                    break
                }
            }
            return bytes
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }
}

internal protocol FSWritableHandle: FSHandle {
    func write(_: Lua, _: LuaValue) async throws
    func writeLine(_: Lua, _: [UInt8]) async throws
    func flush(_: Lua) async throws
}

internal extension FSWritableHandle {
    func write(_ state: Lua, _ value: LuaValue) async throws {
        do {
            switch value {
                case .number(let n):
                    try handle.write(contentsOf: [UInt8(n)])
                case .string(let s):
                    try handle.write(contentsOf: s.bytes)
                default:
                    throw await state.argumentError(at: 1, for: value, expected: "string or number")
            }
        } catch let error as Lua.LuaError {
            throw error
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    func writeLine(_ state: Lua, _ str: [UInt8]) async throws {
        do {
            try handle.write(contentsOf: str)
            try handle.write(contentsOf: [0x0A])
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }

    func flush(_ state: Lua) async throws {
        do {
            try handle.synchronize()
        } catch let error {
            throw await state.error(error.localizedDescription)
        }
    }
}

internal final class ReadHandle: FSReadableHandle, Sendable {
    let handle: FileHandle
    internal init(with url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }
    func table() -> LuaTable {
        return LuaTable(from: [
            .value("seek"): .value(LuaSwiftFunction {_state, _args in
                return [.value(try await self.seek(_state, try? await _args.checkString(at: 1), try? await _args.checkInt(at: 2)))]
            }),
            .value("close"): .value(LuaSwiftFunction {_state, _args in
                try await self.close(_state)
                return []
            }),
            .value("read"): .value(LuaSwiftFunction {_state, _args in
                return [try await self.read(_state, try? await _args.checkInt(at: 1))]
            }),
            .value("readAll"): .value(LuaSwiftFunction {_state, _args in
                let res = try await self.readAll(_state)
                return [res != nil ? .value(res!) : .nil]
            }),
            .value("readLine"): .value(LuaSwiftFunction {_state, _args in
                let res = try await self.readLine(_state, try? await _args.checkBoolean(at: 1))
                return [res != nil ? .value(res!) : .nil]
            })
        ])
    }
}

internal final class WriteHandle: FSWritableHandle, Sendable {
    let handle: FileHandle
    internal init(with url: URL, atEnd: Bool) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            if !FileManager.default.createFile(atPath: url.path, contents: nil) {
                throw Lua.LuaError.runtimeError(message: "Could not create file")
            }
        }
        handle = try FileHandle(forWritingTo: url)
        if atEnd {
            try handle.seekToEnd()
        } else {
            try handle.truncate(atOffset: 0)
        }
    }
    func table() -> LuaTable {
        return LuaTable(from: [
            .value("seek"): .value(LuaSwiftFunction {_state, _args in
                return [.value(try await self.seek(_state, try? await _args.checkString(at: 1), try? await _args.checkInt(at: 2)))]
            }),
            .value("close"): .value(LuaSwiftFunction {_state, _args in
                try await self.close(_state)
                return []
            }),
            .value("write"): .value(LuaSwiftFunction {_state, _args in
                try await self.write(_state, _args[1])
                return []
            }),
            .value("writeLine"): .value(LuaSwiftFunction {_state, _args in
                try await self.writeLine(_state, _args.checkBytes(at: 1))
                return []
            }),
            .value("flush"): .value(LuaSwiftFunction {_state, _args in
                try await self.flush(_state)
                return []
            })
        ])
    }
}

internal final class ReadWriteHandle: FSReadableHandle, FSWritableHandle, Sendable {
    let handle: FileHandle
    internal init(with url: URL, atEnd: Bool, truncate: Bool) throws {
        handle = try FileHandle(forUpdating: url)
        if truncate {
            try handle.truncate(atOffset: 0)
        }
        if atEnd {
            try handle.seekToEnd()
        }
    }
    func table() -> LuaTable {
        return LuaTable(from: [
            .value("seek"): .value(LuaSwiftFunction {_state, _args in
                return [.value(try await self.seek(_state, try? await _args.checkString(at: 1), try? await _args.checkInt(at: 2)))]
            }),
            .value("close"): .value(LuaSwiftFunction {_state, _args in
                try await self.close(_state)
                return []
            }),
            .value("read"): .value(LuaSwiftFunction {_state, _args in
                return [try await self.read(_state, try? await _args.checkInt(at: 1))]
            }),
            .value("readAll"): .value(LuaSwiftFunction {_state, _args in
                let res = try await self.readAll(_state)
                return [res != nil ? .value(res!) : .nil]
            }),
            .value("readLine"): .value(LuaSwiftFunction {_state, _args in
                let res = try await self.readLine(_state, try? await _args.checkBoolean(at: 1))
                return [res != nil ? .value(res!) : .nil]
            }),
            .value("write"): .value(LuaSwiftFunction {_state, _args in
                try await self.write(_state, _args[1])
                return []
            }),
            .value("writeLine"): .value(LuaSwiftFunction {_state, _args in
                try await self.writeLine(_state, _args.checkBytes(at: 1))
                return []
            }),
            .value("flush"): .value(LuaSwiftFunction {_state, _args in
                try await self.flush(_state)
                return []
            })
        ])
    }
}

@LuaLibrary(named: "")
internal actor ReadableDataHandle {
    private let data: Data
    private var pos = 0
    private var closed = false

    public func seek(_ state: Lua, _ whence: String?, _ offset: Int?) async throws -> Int {
        if closed {
            throw await state.error("attempt to use a closed file")
        }
        let whence = whence ?? "cur"
        let offset = offset ?? 0
        switch whence {
            case "set":
                pos = offset
            case "cur":
                pos += offset
            case "end":
                pos = data.count - offset - 1
            default:
                throw await state.error("bad argument #1 (invalid whence)")
        }
        return pos
    }

    public func close(_ state: Lua) async throws {
        if closed {
            throw await state.error("attempt to use a closed file")
        }
        closed = true
    }

    public func read(_ state: Lua, _ count: Int?) async throws -> LuaValue {
        if closed {
            throw await state.error("attempt to use a closed file")
        }
        if pos >= data.count {
            return .nil
        }
        if var count = count {
            if pos + count > data.count {
                count = data.count - pos
            }
            let d = data[pos..<(pos + count)].map {$0}
            pos += count
            return .value(d)
        } else {
            let c = data[pos]
            pos += 1
            return .value(c)
        }
    }

    public func readAll(_ state: Lua) async throws -> [UInt8]? {
        if closed {
            throw await state.error("attempt to use a closed file")
        }
        if pos >= data.count {
            return nil
        }
        let d = data[pos...].map {$0}
        pos = data.count
        return d
    }

    public func readLine(_ state: Lua, _ withNewline: Bool?) async throws -> [UInt8]? {
        if closed {
            throw await state.error("attempt to use a closed file")
        }
        if pos >= data.count {
            return nil
        }
        var d = data[pos...].prefix {$0 != 0x0A}.map {$0}
        pos += d.count + 1
        if withNewline ?? false {
            d.append(0x0A)
        }
        return d
    }

    internal init(from data: Data) {
        self.data = data
    }
}
