#if os(macOS)
import Foundation

@MainActor
@Observable
final class AudioPluginInstaller {
    private(set) var status = "HushPort Audio is not installed"
    private(set) var isInstalling = false

    private let destination = URL(
        fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/HushPortAudio.driver",
        isDirectory: true
    )

    init() {
        if FileManager.default.fileExists(atPath: destination.path) {
            status = "HushPort Audio is installed"
        }
    }

    func install() {
        guard !isInstalling else { return }
        guard let source = Bundle.main.url(forResource: "HushPortAudio", withExtension: "driver") else {
            status = "Bundled HushPort Audio driver was not found"
            return
        }

        isInstalling = true
        status = "Waiting for administrator approval…"
        Task.detached { [destination] in
            let command = "/usr/bin/ditto \(Self.shellQuote(source.path)) \(Self.shellQuote(destination.path))"
            let script = "do shell script \"\(Self.appleScriptEscape(command))\" with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self.isInstalling = false
                    self.status = process.terminationStatus == 0
                        ? "Installed. Restart your Mac, then select HushPort in Sound settings."
                        : (errorText.isEmpty ? "Installation was cancelled" : errorText)
                }
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.status = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func appleScriptEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
#endif
