import Foundation

/// Sets up the Python environment with uv and runs the engine server as a child process.
final class EngineProcess {
    enum Failure: LocalizedError {
        case missing(String)
        case setupFailed(Int32)
        case exited(Int32)
        case timeout

        var errorDescription: String? {
            switch self {
            case .missing(let what): return "Could not find \(what)."
            case .setupFailed(let code): return "Setting up the Python environment failed (exit code \(code)). Check the engine log."
            case .exited(let code): return "The engine stopped unexpectedly (exit code \(code)). Check the engine log."
            case .timeout: return "The engine did not start in time. Check the engine log."
            }
        }
    }

    static let supportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ImageGen", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var logURL: URL { supportDir.appending(path: "engine.log") }
    static var venvURL: URL { supportDir.appending(path: "venv", directoryHint: .isDirectory) }

    var onLog: ((String) -> Void)?
    private var process: Process?
    private var logHandle: FileHandle?

    // MARK: Locating resources

    /// The backend sources: bundled in the .app, or the repo checkout during development.
    static func backendDir() -> URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["IMAGEGEN_BACKEND_DIR"] {
            return URL(fileURLWithPath: env)
        }
        if let bundled = Bundle.main.resourceURL?.appending(path: "backend"),
           fm.fileExists(atPath: bundled.appending(path: "pyproject.toml").path) {
            return bundled
        }
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        while let current = dir, current.path != "/" {
            let candidate = current.appending(path: "backend")
            if fm.fileExists(atPath: candidate.appending(path: "pyproject.toml").path) { return candidate }
            dir = current.deletingLastPathComponent()
        }
        return nil
    }

    static func uvBinary() -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let bundled = Bundle.main.resourceURL?.appending(path: "bin/uv").path { candidates.append(bundled) }
        let home = fm.homeDirectoryForCurrentUser.path
        candidates += ["\(home)/.local/bin/uv", "\(home)/.cargo/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    // MARK: Lifecycle

    func start(port: Int, hfToken: String?, status: @escaping (String) -> Void) async throws {
        guard let backend = Self.backendDir() else { throw Failure.missing("the engine sources") }
        guard let uv = Self.uvBinary() else { throw Failure.missing("uv (the Python package manager)") }

        openLog()
        var env = ProcessInfo.processInfo.environment
        env["UV_PROJECT_ENVIRONMENT"] = Self.venvURL.path
        env["PYTHONUNBUFFERED"] = "1"
        env["IMAGEGEN_HOME"] = Self.supportDir.path
        env["IMAGEGEN_PORT"] = String(port)
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        if let hfToken, !hfToken.isEmpty { env["HF_TOKEN"] = hfToken }

        status("Preparing the Python environment. The first start downloads about 1 GB and takes a few minutes.")
        let sync = makeProcess(uv, ["sync", "--frozen", "--no-dev", "--project", backend.path], env: env, cwd: backend)
        try sync.run()
        await Task.detached { sync.waitUntilExit() }.value
        guard sync.terminationStatus == 0 else { throw Failure.setupFailed(sync.terminationStatus) }

        status("Starting the engine…")
        let python = Self.venvURL.appending(path: "bin/python")
        env["PYTHONPATH"] = backend.path
        let server = makeProcess(python, ["-m", "imagegen", "--port", String(port)], env: env, cwd: backend)
        try server.run()
        process = server

        let client = APIClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        for _ in 0..<240 {
            if await client.health() { return }
            if !server.isRunning { throw Failure.exited(server.terminationStatus) }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw Failure.timeout
    }

    var isRunning: Bool { process?.isRunning ?? false }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        self.process = nil
    }

    // MARK: Helpers

    private func openLog() {
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: Self.logURL)
    }

    private func makeProcess(_ exe: URL, _ args: [String], env: [String: String], cwd: URL) -> Process {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = env
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.logHandle?.write(data)
            if let text = String(data: data, encoding: .utf8) {
                self?.onLog?(text)
            }
        }
        return p
    }
}
