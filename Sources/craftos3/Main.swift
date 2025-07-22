import SDL3
import Lua
import Foundation

@main
class Main {
    static func main() async {
        do {
            try await SDLTerminal.initialize()
            defer {SDLTerminal.quit()}
            let computer = try await Computer(with: 0)
            Task.detached(priority: .high) {
                await computer.run()
            }
            while try await !SDLTerminal.pollEvents() {}
        } catch {
            print(error)
        }
    }
}
