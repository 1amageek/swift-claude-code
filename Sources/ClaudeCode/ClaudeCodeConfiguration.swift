import Foundation
import os.log

private let logger = Logger(subsystem: "com.1amageek.ClaudeCode", category: "Configuration")

/// Built-in Claude models for the `--model` flag.
public enum ClaudeModel: Sendable, Equatable {
    /// Most intelligent model — agents, complex reasoning, coding.
    case opus
    /// Best balance of speed and intelligence.
    case sonnet
    /// Fastest model with near-frontier intelligence.
    case haiku
    /// Arbitrary model identifier (e.g. "claude-opus-4-6").
    case custom(String)

    public var rawValue: String {
        switch self {
        case .opus: "claude-opus-4-6"
        case .sonnet: "claude-sonnet-4-6"
        case .haiku: "claude-haiku-4-5"
        case .custom(let s): s
        }
    }
}

/// Configuration for spawning a Claude Code CLI process.
public struct ClaudeCodeConfiguration: Sendable {

    /// Path to the `claude` executable. Defaults to the standard install location.
    public var executablePath: String

    /// Working directory for the Claude session.
    public var workingDirectory: URL?

    /// Model override. When nil, uses the subscription default.
    public var model: ClaudeModel?

    /// Tools to auto-approve without prompting.
    public var allowedTools: [String]

    /// Maximum agentic turns per invocation.
    public var maxTurns: Int?

    /// System prompt override.
    public var systemPrompt: String?

    /// Additional system prompt appended to the default.
    public var appendSystemPrompt: String?

    /// Permission mode (e.g. "default", "acceptEdits", "plan").
    public var permissionMode: String?

    /// Skip all permission checks (tools run without approval).
    public var dangerouslySkipPermissions: Bool

    /// Additional directories to allow tool access to (passed as `--add-dir`).
    public var additionalDirectories: [URL]

    /// Inline MCP server configurations. Each entry is a JSON string passed as `--mcp-config`.
    public var mcpConfigs: [String]

    /// Path to an isolated MCP config file (passed as `--mcp-config`).
    /// When set alongside `mcpConfigs`, both are forwarded to the CLI.
    public var mcpConfigPath: URL?

    /// Plugin roots to load (passed as `--plugin-dir`).
    /// Each URL must point to a directory containing `.claude-plugin/plugin.json`.
    public var pluginDirectories: [URL]

    /// Additional environment variables set on the Claude CLI process.
    public var environment: [String: String]

    /// Additional CLI flags passed verbatim.
    public var additionalFlags: [String]

    /// When true (the default), `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL`
    /// are stripped from the subprocess environment so the CLI authenticates via OAuth only.
    /// Set to false if you need API-key billing.
    public var enforceOAuthOnly: Bool

    /// When true (the default), `ulimit -n 2147483646` is applied to the subprocess
    /// to avoid FD exhaustion on large workloads.
    public var raiseFileDescriptorLimit: Bool

    public init(
        executablePath: String? = nil,
        workingDirectory: URL? = nil,
        model: ClaudeModel? = nil,
        allowedTools: [String] = [],
        maxTurns: Int? = nil,
        systemPrompt: String? = nil,
        appendSystemPrompt: String? = nil,
        permissionMode: String? = nil,
        dangerouslySkipPermissions: Bool = true,
        additionalDirectories: [URL] = [],
        mcpConfigs: [String] = [],
        mcpConfigPath: URL? = nil,
        pluginDirectories: [URL] = [],
        environment: [String: String] = [:],
        additionalFlags: [String] = [],
        enforceOAuthOnly: Bool = true,
        raiseFileDescriptorLimit: Bool = true
    ) {
        self.executablePath = executablePath ?? Self.defaultExecutablePath
        self.workingDirectory = workingDirectory
        self.model = model
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
        self.systemPrompt = systemPrompt
        self.appendSystemPrompt = appendSystemPrompt
        self.permissionMode = permissionMode
        self.dangerouslySkipPermissions = dangerouslySkipPermissions
        self.additionalDirectories = additionalDirectories
        self.mcpConfigs = mcpConfigs
        self.mcpConfigPath = mcpConfigPath
        self.pluginDirectories = pluginDirectories
        self.environment = environment
        self.additionalFlags = additionalFlags
        self.enforceOAuthOnly = enforceOAuthOnly
        self.raiseFileDescriptorLimit = raiseFileDescriptorLimit
    }

    /// The user's login shell.
    static let loginShell: String = {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }()

    /// Env vars stripped when `enforceOAuthOnly` is true.
    static let apiKeyEnvVars: [String] = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
    ]

    /// Builds the CLI arguments for a single prompt invocation.
    func arguments(prompt: String, resumeSessionID: String? = nil) -> [String] {
        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]

        if dangerouslySkipPermissions {
            args += ["--dangerously-skip-permissions"]
        }

        if let sessionID = resumeSessionID {
            args += ["--resume", sessionID]
        }

        if let model {
            args += ["--model", model.rawValue]
        }

        if !allowedTools.isEmpty {
            args += ["--allowedTools"] + allowedTools
        }

        if let maxTurns {
            args += ["--max-turns", String(maxTurns)]
        }

        if let systemPrompt {
            args += ["--system-prompt", systemPrompt]
        }

        if let appendSystemPrompt {
            args += ["--append-system-prompt", appendSystemPrompt]
        }

        if let permissionMode {
            args += ["--permission-mode", permissionMode]
        }

        if !additionalDirectories.isEmpty {
            args += ["--add-dir"] + additionalDirectories.map(\.path)
        }

        for config in mcpConfigs {
            args += ["--mcp-config", config]
        }

        if let mcpConfigPath {
            args += ["--mcp-config", mcpConfigPath.path]
        }

        for dir in pluginDirectories {
            args += ["--plugin-dir", dir.path]
        }

        args += additionalFlags

        return args
    }

    /// Build a shell command string that launches `claude` via the user's login shell.
    /// This reproduces the same environment as Terminal.app, with optional FD-limit raise
    /// and OAuth-only enforcement via env-var scrubbing.
    func shellCommand(prompt: String, resumeSessionID: String? = nil) -> String {
        let args = arguments(prompt: prompt, resumeSessionID: resumeSessionID)
        let escaped = args.map { shellEscape($0) }.joined(separator: " ")

        var prefix: [String] = []
        if raiseFileDescriptorLimit {
            prefix.append("ulimit -n 2147483646 2>/dev/null")
        }

        var unsets = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"]
        if enforceOAuthOnly {
            unsets += Self.apiKeyEnvVars
        }
        prefix.append("unset \(unsets.joined(separator: " "))")

        return "\(prefix.joined(separator: "; ")); exec \(shellEscape(executablePath)) \(escaped)"
    }

    /// Shell-escape a string using single quotes.
    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    // MARK: - Default Path

    private static var defaultExecutablePath: String {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "claude"
    }

    // MARK: - Status

    /// Whether the claude executable exists at the configured path.
    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    /// Allowed OAuth-based auth methods. API key auth is rejected.
    private static let allowedAuthMethods: Set<String> = ["claude.ai"]

    /// Auth status returned by `claude auth status`.
    public struct AuthStatus: Sendable {
        public let loggedIn: Bool
        public let authMethod: String?

        public init(loggedIn: Bool, authMethod: String?) {
            self.loggedIn = loggedIn
            self.authMethod = authMethod
        }

        /// Whether the auth method is OAuth-based (not API key).
        public var isOAuthAuthenticated: Bool {
            loggedIn && authMethod.map { ClaudeCodeConfiguration.allowedAuthMethods.contains($0) } ?? false
        }
    }

    /// Check login status by running `claude auth status --json`.
    ///
    /// - CWD is set to `NSTemporaryDirectory()` so the subprocess never inherits
    ///   a TCC-restricted working directory from the parent (which would trigger
    ///   macOS folder-access prompts). Callers that need a specific CWD should
    ///   run `auth status` themselves.
    /// - When `enforceOAuthOnly` is true (the default), API-key env vars are
    ///   stripped from the subprocess environment so the result reflects
    ///   OAuth status only.
    public func checkAuthStatus() async -> AuthStatus {
        logger.info("[auth] checkAuthStatus: executable=\(executablePath, privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["auth", "status", "--json"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        var env = ProcessInfo.processInfo.environment
        if enforceOAuthOnly {
            for key in Self.apiKeyEnvVars {
                env.removeValue(forKey: key)
            }
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            let rawError = String(data: errData, encoding: .utf8) ?? ""

            logger.info("[auth] exit=\(status) stdout=\(rawOutput, privacy: .public)")
            if !rawError.isEmpty {
                logger.warning("[auth] stderr=\(rawError, privacy: .public)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("[auth] Failed to parse JSON from stdout")
                return AuthStatus(loggedIn: false, authMethod: nil)
            }

            let loggedIn = json["loggedIn"] as? Bool ?? false
            let authMethod = json["authMethod"] as? String
            logger.info("[auth] loggedIn=\(loggedIn) authMethod=\(authMethod ?? "nil", privacy: .public)")

            return AuthStatus(loggedIn: loggedIn, authMethod: authMethod)
        } catch {
            logger.error("[auth] Process launch failed: \(error.localizedDescription, privacy: .public)")
            return AuthStatus(loggedIn: false, authMethod: nil)
        }
    }
}
