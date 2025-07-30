import Lua
import LuaLib
import Foundation

@LuaLibrary(named: "os")
internal final class OSAPI {
    private let computer: Computer

    public func queueEvent(_ state: Lua, _ args: LuaArgs) async throws {
        _ = try await args.checkString(at: 1)
        await computer.push(event: args.args)
    }

    public func startTimer(_ time: Double) async -> Int {
        return await computer.start(timer: time)
    }

    public func cancelTimer(_ id: Int) async {
        await computer.cancel(timer: id)
    }

    public func setAlarm(_ state: Lua, _ time: Double) async throws -> Int {
        if time < 0.0 || time >= 24.0 {
            throw await state.error("Number out of range")
        }
        return await computer.set(alarm: time)
    }

    public func cancelAlarm(_ id: Int) async {
        await computer.cancel(timer: id)
    }

    public func shutdown() async {
        await computer.shutdown()
    }

    public func reboot() async {
        await computer.reboot()
    }

    public func getComputerID() -> Int {
        return computer.id
    }

    public func computerID() -> Int {
        return computer.id
    }

    public func getComputerLabel() async -> String? {
        return await computer.label
    }

    public func computerLabel() async -> String? {
        return await computer.label
    }

    public func setComputerLabel(_ label: String?) async {
        await computer.set(label: label)
    }

    public func clock() async -> Double {
        return await Date.now.distance(to: computer.systemStart)
    }

    public func time(_ state: Lua, _ locale: LuaValue) async throws -> Double {
        switch locale {
            case .nil:
                let passedTime: Int = await Int((Date.now.distance(to: computer.systemStart)) * 1000)
                return Double(((passedTime + 300000) % 1200000) / 50) / 1000.0
            case .string(let str):
                switch str.string {
                    case "ingame":
                        let passedTime: Int = await Int((Date.now.distance(to: computer.systemStart)) * 1000)
                        return Double(((passedTime + 300000) % 1200000) / 50) / 1000.0
                    case "local":
                        let now = Date.now
                        return Double(Calendar.current.component(.hour, from: now)) + Double(Calendar.current.component(.minute, from: now)) / 60.0 + Double(Calendar.current.component(.minute, from: now)) / 3600.0
                    case "utc":
                        let now = Date.now
                        var calendar = Calendar(identifier: .iso8601)
                        calendar.timeZone = TimeZone.gmt
                        return Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60.0 + Double(calendar.component(.minute, from: now)) / 3600.0
                    default:
                        throw await state.error("Unsupported operation")
                }
            case .table(let tab):
                guard case let .number(sec) = await tab["sec"] else {
                    throw await state.error("field sec missing in date table")
                }
                guard case let .number(min) = await tab["min"] else {
                    throw await state.error("field min missing in date table")
                }
                guard case let .number(hour) = await tab["hour"] else {
                    throw await state.error("field hour missing in date table")
                }
                guard case let .number(day) = await tab["day"] else {
                    throw await state.error("field day missing in date table")
                }
                guard case let .number(month) = await tab["month"] else {
                    throw await state.error("field month missing in date table")
                }
                guard case let .number(year) = await tab["year"] else {
                    throw await state.error("field year missing in date table")
                }
                guard let date = Calendar.current.date(from: DateComponents(calendar: Calendar.current, timeZone: Calendar.current.timeZone, era: nil, year: Int(year), month: Int(month), day: Int(day), hour: Int(hour), minute: Int(min), second: Int(sec))) else {
                    throw await state.error("Could not construct date")
                }
                return date.timeIntervalSince1970
            default:
                throw await state.error("bad argument #1 (expected string or table, got \(locale.type))")
        }
    }

    public func day(_ state: Lua, _ locale: String?) async throws -> Int {
        // TODO: this is supposed to be days since epoch, not day of year
        switch locale ?? "ingame" {
            case "ingame":
                return await Int(Date.now.distance(to: computer.systemStart) / 1200) + 1
            case "local":
                return Calendar.current.component(.dayOfYear, from: Date.now)
            case "utc":
                var calendar = Calendar(identifier: .iso8601)
                calendar.timeZone = TimeZone.gmt
                return calendar.component(.dayOfYear, from: Date.now)
            default:
                throw await state.error("Unsupported operation")
        }
    }

    public func epoch(_ state: Lua, _ locale: String?) async throws -> Int {
        switch locale ?? "ingame" {
            case "ingame":
                let passedTime: Int = await Int((Date.now.distance(to: computer.systemStart)) * 1000)
                let m_time = Double(((passedTime + 300000) % 1200000) / 50) / 1000.0
                let m_day = passedTime / 1200000 + 1
                let epoch = m_day * 86400000 + Int(m_time * 3600000.0)
                return epoch
            case "local":
                return Int(Date.now.addingTimeInterval(TimeInterval(Calendar.current.timeZone.secondsFromGMT())).timeIntervalSince1970 * 1000)
            case "utc":
                return Int(Date.now.timeIntervalSince1970 * 1000)
            default:
                throw await state.error("Unsupported operation")
        }
    }

    public func date(_ state: Lua, _ format: String?, _ time: Int?) async throws -> LuaValue {
        var format = format ?? "%c"
        let time = time ?? Int(Date.now.timeIntervalSince1970)
        let date = Date(timeIntervalSince1970: TimeInterval(time))

        var calendar = Calendar.current
        if format.first == "!" {
            format = String(format[format.index(after: format.startIndex)...])
            calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone.gmt
        }

        if format == "*t" {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone, .weekday, .dayOfYear], from: date)
            return .table(LuaTable(from: [
                .value("year"): .value(components.year!),
                .value("month"): .value(components.month!),
                .value("day"): .value(components.day!),
                .value("hour"): .value(components.hour!),
                .value("min"): .value(components.minute!),
                .value("sec"): .value(components.second!),
                .value("wday"): .value(components.weekday!),
                .value("yday"): .value(components.dayOfYear!),
                .value("isdst"): .value(calendar.timeZone.isDaylightSavingTime(for: date))
            ]))
        }

        var tm = tm()
        var timet = time_t(time)
        if calendar.timeZone.secondsFromGMT() == 0 {
            gmtime_r(&timet, &tm)
        } else {
            localtime_r(&timet, &tm)
        }
        return .value(format.replacing(/%\w/, with: {(match: Regex<Substring>.Match) in
            String(utf8String: [CChar](unsafeUninitializedCapacity: 200, initializingWith: {_buf, _count in
                _count = strftime(_buf.baseAddress!, _count, String(match.output), &tm)
            })) ?? ""
        }))
    }

    public func about() -> String {
        return """
CraftOS-PC \(CraftOS3.VERSION)

CraftOS-PC 3 is licensed under the MIT License.
MIT License

Copyright (c) 2019-2025 JackMacWindows

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Special thanks:
* dan200 for creating the ComputerCraft mod and making it open source
* SquidDev for picking up ComputerCraft after Dan left and creating CC: Tweaked
* Everyone on the Minecraft Computer Mods Discord server for the support while developing CraftOS-PC
"""
    }

    internal init(for computer: Computer) {
        self.computer = computer
    }
}