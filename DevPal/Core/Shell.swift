import Foundation

/// Generic shell command executor for running external commands (ssh-keygen, ssh, git, etc.)
actor Shell {
    enum ShellError: LocalizedError {
        case executionFailed(exitCode: Int32, stderr: String)
        case timeout
        case processError(String)

        var errorDescription: String? {
            switch self {
            case .executionFailed(let code, let stderr):
                return "命令执行失败 (exit \(code)): \(stderr)"
            case .timeout:
                return "命令执行超时"
            case .processError(let msg):
                return "进程错误: \(msg)"
            }
        }
    }

    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { exitCode == 0 }
    }

    /// Execute a shell command asynchronously with timeout
    static func execute(
        _ command: String,
        arguments: [String] = [],
        timeout: TimeInterval = 30
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            func safeResume(_ result: Swift.Result<Result, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            // Timeout
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                process.terminate()
                safeResume(.failure(ShellError.timeout))
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                safeResume(.success(Result(
                    exitCode: proc.terminationStatus,
                    stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                )))
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                safeResume(.failure(ShellError.processError(error.localizedDescription)))
            }
        }
    }

    /// Convenience: run /bin/zsh -c "command string"
    static func run(_ commandString: String, timeout: TimeInterval = 30) async throws -> Result {
        try await execute("/bin/zsh", arguments: ["-c", commandString], timeout: timeout)
    }
}
