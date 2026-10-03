import Foundation

enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    /// Runs an executable synchronously with stdin closed, so tools like `sudo -n` can never wait for input.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = []) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
