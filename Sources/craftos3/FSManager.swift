import Foundation
import Lua

public actor FSManager {
    public struct FilesystemError: Error {
        public let message: String
        public var localizedDescription: String {
            return message // TODO: translate?
        }
    }

    public struct Attributes: Sendable {
        public let size: Int
        public let isDir: Bool
        public let isReadOnly: Bool
        public let created: Int
        public let modified: Int
    }

    public struct OpenFlags: OptionSet, Sendable {
        public static let read: OpenFlags = []
        public static let write = OpenFlags(rawValue: 0x01)
        public static let append = OpenFlags(rawValue: 0x03)
        public static let readWrite = OpenFlags(rawValue: 0x04)
        public static let readPlus = OpenFlags(rawValue: 0x04)
        public static let writePlus = OpenFlags(rawValue: 0x05)
        public static let appendPlus = OpenFlags(rawValue: 0x07)
        public static let binary = OpenFlags(rawValue: 0x08)
        public let rawValue: UInt8
        public init(rawValue: UInt8) {self.rawValue = rawValue}
        public init?(from mode: String) {
            var value: UInt8 = 0
            if mode.contains("w") {
                value |= 1
            } else if mode.contains("a") {
                value |= 3
            } else if !mode.contains("r") {
                return nil
            }
            if mode.contains("+") {
                value |= 4
            }
            if mode.contains("b") {
                value |= 8
            }
            rawValue = value
        }
        public var isRead: Bool {return (rawValue & 3) == 0}
        public var isWrite: Bool {return (rawValue & 3) == 1}
        public var isAppend: Bool {return (rawValue & 3) == 3}
        public var isReadWrite: Bool {return (rawValue & 4) != 0}
        public var isBinary: Bool {return (rawValue & 8) != 0}
        public var isReadable: Bool {return (rawValue & 4) != 0 || (rawValue & 1) == 0}
        public var isWritable: Bool {return (rawValue & 4) != 0 || (rawValue & 1) != 0}
    }

    public protocol Mount: Sendable, Equatable {
        var mountLocation: [String] {get}

        func list(at: String) async throws -> [String]
        func stat(at: String) async throws -> Attributes?
        func makeDir(at: String) async throws
        func move(from: String, to: String) async throws
        func copy(from: String, to: String) async throws
        func delete(_: String) async throws
        func open(_: String, mode: OpenFlags) async throws -> LuaTable
        func read(from: String) async throws -> Data
        func write(to: String, with: Data) async throws
        var freeSpace: Int {get async throws}
        var capacity: Int {get async throws}
    }

    public final class FileMount: Mount {
        public let mountLocation: [String]
        public let filesystemPath: URL
        public let readOnly: Bool
        public let emulatedCapacity: Int?

        private func fixpath(_ path: String) throws -> URL {
            let url = URL(fileURLWithPath: path, relativeTo: filesystemPath).standardizedFileURL
            if url.pathComponents.count < filesystemPath.pathComponents.count || !url.pathComponents[0..<filesystemPath.pathComponents.count].elementsEqual(filesystemPath.pathComponents) {
                throw FilesystemError(message: "No such file or directory")
            }
            return url
        }

        public static func == (lhs: FileMount, rhs: FileMount) -> Bool {
            return lhs.filesystemPath == rhs.filesystemPath && lhs.readOnly == rhs.readOnly
        }

        public func list(at path: String) async throws -> [String] {
            let contents = try FileManager.default.contentsOfDirectory(at: try fixpath(path), includingPropertiesForKeys: nil)
            return contents.map {$0.lastPathComponent}.sorted()
        }

        public func stat(at path: String) async throws -> Attributes? {
            let url = try fixpath(path)
            if !FileManager.default.fileExists(atPath: url.path) {
                return nil
            }
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            let isReadOnly: Bool
            if readOnly {
                isReadOnly = true
            } else if let appendOnly = attr[.appendOnly] as? NSNumber {
                isReadOnly = appendOnly.intValue != 0
            } else if let perms = attr[.posixPermissions] as? NSNumber {
                if let owner = attr[.ownerAccountName] as? NSString as? String, ProcessInfo.processInfo.userName == owner {
                    isReadOnly = (perms.intValue & 0o200) == 0
                } else {
                    isReadOnly = (perms.intValue & 0o002) == 0
                }
            } else {
                // TODO
                isReadOnly = false
            }

            return Attributes(
                size: (attr[.size]! as! NSNumber).intValue,
                isDir: (attr[.type]! as! FileAttributeType) == FileAttributeType.typeDirectory,
                isReadOnly: isReadOnly,
                created: Int((attr[.creationDate]! as! NSDate).timeIntervalSince1970 * 1000),
                modified: Int((attr[.modificationDate]! as! NSDate).timeIntervalSince1970 * 1000)
            )
        }

        public func makeDir(at path: String) async throws {
            if readOnly {
                throw FilesystemError(message: "Permission denied")
            }
            try FileManager.default.createDirectory(at: try fixpath(path), withIntermediateDirectories: true)
        }

        public func move(from: String, to: String) async throws {
            if readOnly {
                throw FilesystemError(message: "Permission denied")
            }
            try FileManager.default.moveItem(at: try fixpath(from), to: try fixpath(to))
        }

        public func copy(from: String, to: String) async throws {
            if readOnly {
                throw FilesystemError(message: "Permission denied")
            }
            try FileManager.default.copyItem(at: try  fixpath(from), to: try  fixpath(to))
        }

        public func delete(_ path: String) async throws {
            if readOnly {
                throw FilesystemError(message: "Permission denied")
            }
            try FileManager.default.removeItem(at: try fixpath(path))
        }

        public func open(_ path: String, mode: OpenFlags) async throws -> LuaTable {
            if readOnly && mode.isWritable {
                throw FilesystemError(message: "Permission denied")
            }
            let url = try fixpath(path)
            if mode.isReadWrite {
                return try ReadWriteHandle(with: url, atEnd: mode.isAppend, truncate: mode.isWrite).table()
            } else if mode.isRead {
                return try ReadHandle(with: url).table()
            } else {
                return try WriteHandle(with: url, atEnd: mode.isAppend).table()
            }
        }

        public func read(from path: String) async throws -> Data {
            return try Data(contentsOf: try fixpath(path))
        }

        public func write(to path: String, with data: Data) async throws {
            if readOnly {
                throw FilesystemError(message: "Permission denied")
            }
            try data.write(to: try fixpath(path))
        }

        public var capacity: Int {
            get async throws {
                if let capacity = emulatedCapacity {
                    return capacity
                } else {
                    return (try FileManager.default.attributesOfFileSystem(forPath: filesystemPath.path)[.systemSize]! as! NSNumber).intValue
                }
            }
        }

        public var freeSpace: Int {
            get async throws {
                if let capacity = emulatedCapacity {
                    // TODO: calculate free space
                    return capacity
                } else {
                    return (try FileManager.default.attributesOfFileSystem(forPath: filesystemPath.path)[.systemFreeSize]! as! NSNumber).intValue
                }
            }
        }

        public init(for location: [String], at path: URL, readOnly: Bool, capacity: Int? = nil) throws {
            mountLocation = location
            filesystemPath = path
            self.readOnly = readOnly
            emulatedCapacity = capacity
            var isDir = false
            if !FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) || !isDir {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
        }
    }

    public final class MemoryMount: Mount {
        public enum FileInfo: Sendable {
            case file(data: Data)
            case directory(contents: [String: FileInfo])
        }

        public let mountLocation: [String]
        public let filesystem: FileInfo

        public static func == (lhs: MemoryMount, rhs: MemoryMount) -> Bool {
            return lhs === rhs
        }

        private func getFile(at path: String) throws -> FileInfo? {
            var node: FileInfo? = filesystem
            for component in FSManager.split(path: path) {
                if case let .directory(contents) = node {
                    if let file = contents[component] {
                        node = file
                    } else {
                        node = nil
                    }
                } else {
                    throw FilesystemError(message: "Not a directory")
                }
            }
            return node
        }

        public func list(at path: String) async throws -> [String] {
            if let dir = try getFile(at: path), case let .directory(contents) = dir {
                return contents.keys.sorted()
            } else {
                throw FilesystemError(message: "Not a directory")
            }
        }

        public func stat(at path: String) async throws -> Attributes? {
            if let dir = try getFile(at: path) {
                switch dir {
                    case .file(let data): return Attributes(size: data.count, isDir: false, isReadOnly: true, created: 0, modified: 0)
                    case .directory: return Attributes(size: 0, isDir: true, isReadOnly: true, created: 0, modified: 0)
                }
            } else {
                return nil
            }
        }

        public func makeDir(at path: String) async throws {
            throw FilesystemError(message: "Permission denied")
        }

        public func move(from: String, to: String) async throws {
            throw FilesystemError(message: "Permission denied")
        }

        public func copy(from: String, to: String) async throws {
            throw FilesystemError(message: "Permission denied")
        }

        public func delete(_ path: String) async throws {
            throw FilesystemError(message: "Permission denied")
        }

        public func open(_ path: String, mode: OpenFlags) async throws -> LuaTable {
            if mode.isWritable {
                throw FilesystemError(message: "Permission denied")
            }
            guard let file = try getFile(at: path) else {
                throw FilesystemError(message: "No such file")
            }
            guard case let .file(data) = file else {
                throw FilesystemError(message: "Not a file")
            }
            return await ReadableDataHandle(from: data).table()
        }

        public func read(from path: String) async throws -> Data {
            if let file = try getFile(at: path), case let .file(data) = file {
                return data
            } else {
                throw FilesystemError(message: "No such file")
            }
        }

        public func write(to path: String, with data: Data) async throws {
            throw FilesystemError(message: "Permission denied")
        }

        public var capacity: Int {
            get async throws {
                return 0
            }
        }

        public var freeSpace: Int {
            get async throws {
                return 0
            }
        }

        public init(for location: [String], with contents: [String: FileInfo]) {
            mountLocation = location
            filesystem = .directory(contents: contents)
        }
    }

    public static var basePath: URL {
        // TODO: config
        if true {
            return URL.currentDirectory()
        }
        #if os(Windows)
        if let dataDir = ProcessInfo.processInfo.environment["APPDATA"] {
            return URL(fileURLWithPath: dataDir, isDirectory: true).appending(component: "CraftOS-PC", directoryHint: .isDirectory)
        } else {
            return URL.homeDirectory.appending(path: "AppData\\Roaming\\CraftOS-PC", directoryHint: .isDirectory)
        }
        #elseif os(macOS)
        return URL.applicationSupportDirectory.appending(component: "CraftOS-PC", directoryHint: .isDirectory)
        #elseif os(iOS)
        return URL.documentsDirectory
        #elseif os(Linux)
        if let dataDir = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: dataDir, isDirectory: true).appending(component: "craftos-pc", directoryHint: .isDirectory)
        } else {
            return URL.homeDirectory.appending(path: ".local/share/craftos-pc", directoryHint: .isDirectory)
        }
        #else
        return URL.homeDirectory.appending(component: ".craftos", directoryHint: .isDirectory)
        #endif
    }

    public static var romPath: URL {
        // TODO: config
        #if os(Windows)
        return URL.currentDirectory()
        #elseif os(macOS)
        // ?
        if let url = Bundle.main.resourceURL {
            return url
        } else {
            return URL(fileURLWithPath: "/usr/local/share/craftos", isDirectory: true)
        }
        #elseif os(iOS)
        return Bundle.main.resourceURL!
        #elseif os(Linux)
        return URL(fileURLWithPath: "/usr/share/craftos", isDirectory: true)
        #else
        return URL.currentDirectory() // ?
        #endif
    }

    public static func split(path: String) -> [String] {
        return [String](URL(string: "virtual:///" + path)!.standardized.pathComponents.drop {$0 == "/"})
    }

    private var mounts: [any Mount]

    internal init(withRoot root: URL) throws {
        mounts = [try FileMount(for: [], at: root, readOnly: false)]
    }

    public func findMounts(for components: [String]) -> ([any Mount], String) {
        var maxMatchDepth = 0
        var matches = [any Mount]()
        for mount in mounts {
            let loc = mount.mountLocation
            if loc.count < maxMatchDepth {
                continue
            }
            if components.count >= loc.count && components[0..<loc.count].elementsEqual(loc) {
                if loc.count > maxMatchDepth {
                    maxMatchDepth = loc.count
                    matches = [mount]
                } else {
                    matches.append(mount)
                }
            }
        }
        return (matches, components[maxMatchDepth...].joined(separator: "/"))
    }

    public func findMounts(for path: String) -> ([any Mount], String) {
        return findMounts(for: FSManager.split(path: path))
    }

    public func findMount(for components: [String]) async throws -> (any Mount, String) {
        let (mounts, outPath) = findMounts(for: components)
        guard var match = mounts.first else {
            fatalError("Root mount not found!")
        }
        var minMissing = components.count
        let depth = match.mountLocation.count
        let innerPath = components[depth...]
        for mount in mounts {
            var removed = 0
            while removed < innerPath.count, try await mount.stat(at: innerPath[..<innerPath.startIndex.advanced(by: innerPath.count - removed)].joined(separator: "/")) == nil {
                removed += 1
            }
            if removed < minMissing {
                match = mount
                minMissing = removed
            }
        }
        return (match, outPath)
    }

    public func findMount(for path: String) async throws -> (any Mount, String) {
        return try await findMount(for: FSManager.split(path: path))
    }

    public func add(mount: any Mount) {
        mounts.append(mount)
    }

    public func add(fileMountAtPath path: String, for url: URL, readOnly: Bool, capacity: Int? = nil) throws {
        mounts.append(try FileMount(for: FSManager.split(path: path), at: url, readOnly: readOnly, capacity: capacity))
    }

    public func remove(mount: any Mount) throws {
        if mount.equals(mounts.first!) {
            throw FilesystemError(message: "Cannot unmount root mount")
        }
    }

    public func remove(mountsAt path: String) throws {
        let components = FSManager.split(path: path)
        if components.count == 0 {
            throw FilesystemError(message: "Cannot unmount root mount")
        }
        mounts.removeAll {$0.mountLocation.elementsEqual(components)}
    }

    public func list(at path: String) async throws -> [String] {
        var results = Set<String>()
        let (mounts, innerPath) = findMounts(for: path)
        for mount in mounts {
            if let attr = try await mount.stat(at: innerPath), attr.isDir {
                results.formUnion(try await mount.list(at: innerPath))
            }
        }
        for mount in self.mounts {
            if mount.mountLocation.count > 0 && mount.mountLocation[0..<(mount.mountLocation.count-1)].joined(separator: "/") == path {
                results.insert(mount.mountLocation.last!)
            }
        }
        return results.sorted()
    }

    public func stat(at path: String) async throws -> Attributes? {
        let (mount, innerPath) = try await findMount(for: path)
        return try await mount.stat(at: innerPath)
    }

    public func makeDir(at path: String) async throws {
        let (mount, innerPath) = try await findMount(for: path)
        try await mount.makeDir(at: innerPath)
    }

    public func move(from: String, to: String) async throws {
        let (fromMount, fromPath) = try await findMount(for: from)
        let (toMount, toPath) = try await findMount(for: to)
        if fromMount.equals(toMount) {
            try await fromMount.move(from: fromPath, to: toPath)
        } else {
            try await toMount.write(to: toPath, with: fromMount.read(from: fromPath))
            try await fromMount.delete(fromPath)
        }
    }

    public func copy(from: String, to: String) async throws {
        let (fromMount, fromPath) = try await findMount(for: from)
        let (toMount, toPath) = try await findMount(for: to)
        if fromMount.equals(toMount) {
            try await fromMount.copy(from: fromPath, to: toPath)
        } else {
            try await toMount.write(to: toPath, with: fromMount.read(from: fromPath))
        }
    }

    public func delete(_ path: String) async throws {
        let (mount, innerPath) = try await findMount(for: path)
        try await mount.delete(innerPath)
    }

    public func open(_ path: String, mode: OpenFlags) async throws -> LuaTable {
        let (mount, innerPath) = try await findMount(for: path)
        return try await mount.open(innerPath, mode: mode)
    }

    public func read(from path: String) async throws -> Data {
        let (mount, innerPath) = try await findMount(for: path)
        return try await mount.read(from: innerPath)
    }

    public func write(to path: String, with data: Data) async throws {
        let (mount, innerPath) = try await findMount(for: path)
        try await mount.write(to: innerPath, with: data)
    }
}

public extension FSManager.Mount {
    func equals(_ rhs: any FSManager.Mount) -> Bool {
        if let r = rhs as? Self {
            return self == r
        } else {
            return false
        }
    }
}
