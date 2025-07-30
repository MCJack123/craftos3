import SDL3
import Lua
import Foundation

@main
class CraftOS3 {
    public static let VERSION = "v3.0"
    public static let COMPUTERCRAFT_VERSION = "1.116.1"
    @MainActor public static var mainTask: Task<Void, Never>!

    static func main() async {
        do {
            try await SDLTerminal.initialize()
            defer {SDLTerminal.quit()}
            let computer = try await Computer(with: 0)
            mainTask = Task {
                await withTaskGroup { group in
                    group.addTask(priority: .high) {
                        await computer.run()
                        await mainTask.cancel()
                    }
                    group.addTask {
                        do {
                            while try await !SDLTerminal.pollEvents() {}
                        } catch {
                            print(error)
                        }
                        await mainTask.cancel()
                    }
                }
            }
            _ = await mainTask.result
        } catch {
            print(error)
        }
    }
}
