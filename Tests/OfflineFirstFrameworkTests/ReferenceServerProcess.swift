#if os(macOS)
import Foundation

/// The path of a Node 24 binary for the suites that run the reference server, as the "Examples"
/// workflow sets it: `OFFLINE_FIRST_NODE=$(command -v node) swift test`.
let referenceServerNode = ProcessInfo.processInfo.environment["OFFLINE_FIRST_NODE"]

/// `Examples/SyncServer/server.mjs` in a process of its own on a free port, optionally with
/// `--data`; ended with SIGKILL as a crash would end it.
final class ReferenceServerProcess {
    let url: URL
    private let process = Process()

    init(node: String, data: URL? = nil) throws {
        let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Examples/SyncServer/server.mjs")
        process.executableURL = URL(filePath: node)
        process.arguments = [script.path(percentEncoded: false), "--port", "0"]
            + (data.map { ["--data", $0.path(percentEncoded: false)] } ?? [])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        var text = ""
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw URLError(.cannotConnectToHost) }
            text += String(decoding: chunk, as: UTF8.self)
            if let port = text.firstMatch(of: /localhost:(\d+)/)?.1, let url = URL(string: "http://localhost:\(port)") {
                self.url = url
                return
            }
        }
    }

    func kill() {
        Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }

    deinit {
        if process.isRunning { kill() }
    }
}
#endif
