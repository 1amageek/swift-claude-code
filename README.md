# swift-claude-code

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015%2B-blue.svg)](https://developer.apple.com/macos/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

A small Swift actor that spawns the `claude` CLI (Claude Code) as a subprocess,
streams its `--output-format stream-json` events, and maintains multi-turn
conversations via `--resume`.

Used by Bob and agents-in-black.

## Requirements

- macOS 15+
- Swift 6.2+
- The `claude` CLI installed (`~/.local/bin/claude`, `/usr/local/bin/claude`,
  or `/opt/homebrew/bin/claude`) and authenticated via `claude auth login --claudeai`

## Installation

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-claude-code.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "ClaudeCode", package: "swift-claude-code"),
        ]
    ),
]
```

## Usage

```swift
import ClaudeCode

let config = ClaudeCodeConfiguration(
    workingDirectory: URL(fileURLWithPath: "/path/to/project"),
    model: .sonnet,
    pluginDirectories: [pluginDir]
)

let session = ClaudeCodeSession(configuration: config)

for try await event in session.send("Summarize this repo.") {
    switch event {
    case .system(let sys):    print("session:", sys.sessionID)
    case .streamEvent:        break
    case .assistant(let msg): print("assistant:", msg.content)
    case .user(let u):        print("tool results:", u.toolResults)
    case .result(let r):      print("done:", r.numTurns, "turns")
    }
}

// Subsequent calls auto-resume the same session.
for try await _ in session.send("And list the top-level folders.") { }
```

## Models

`ClaudeModel` selects the `--model` flag value:

| Case | Maps to |
|---|---|
| `.opus` | `claude-opus-4-6` |
| `.sonnet` | `claude-sonnet-4-6` |
| `.haiku` | `claude-haiku-4-5` |
| `.custom("...")` | arbitrary model identifier |

Leave `model` as `nil` to use the subscription default.

## Configuration

Key fields on `ClaudeCodeConfiguration`:

| Field | Default | Purpose |
|---|---|---|
| `model` | `nil` (subscription default) | `.opus / .sonnet / .haiku / .custom(String)` |
| `fallbackModel` | `nil` | `--fallback-model` for overload retries |
| `dangerouslySkipPermissions` | `true` | Skip all tool approvals |
| `allowedTools` / `disallowedTools` | `[]` | `--allowedTools` / `--disallowedTools` |
| `permissionMode` | `nil` | `default`, `acceptEdits`, `plan`, etc. |
| `maxTurns` | `nil` | Cap agentic turns per invocation |
| `systemPrompt` / `appendSystemPrompt` | `nil` | Override or extend the system prompt |
| `additionalDirectories` | `[]` | `--add-dir` |
| `mcpConfigs` | `[]` | Inline MCP JSON (`--mcp-config`) |
| `mcpConfigPath` | `nil` | Path to isolated MCP config file (`--mcp-config`) |
| `strictMCPConfig` | `false` | `--strict-mcp-config` (only `--mcp-config` sources) |
| `pluginDirectories` | `[]` | `--plugin-dir` |
| `sessionID` | `nil` | Assign a specific UUID to a new session (`--session-id`) |
| `forkSession` | `false` | `--fork-session` on resume |
| `disableSessionPersistence` | `false` | `--no-session-persistence` |
| `environment` | `[:]` | Extra env vars merged into the subprocess |
| `enforceOAuthOnly` | `true` | Strip `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` |
| `raiseFileDescriptorLimit` | `true` | Apply `ulimit -n 2147483646` before exec |
| `additionalFlags` | `[]` | Extra verbatim CLI flags |

## Auth

The library speaks only to the CLI; authentication is handled by `claude auth login`.

`configuration.checkAuthStatus()` invokes `claude auth status --json` and returns
`AuthStatus` with a convenience `isOAuthAuthenticated` flag. When
`enforceOAuthOnly` is true, API-key env vars are scrubbed so the check reflects
subscription auth only.

```swift
let status = await config.checkAuthStatus()
guard status.isOAuthAuthenticated else {
    // Prompt the user to run `claude auth login --claudeai`
    return
}
```

## Event stream

`StreamEvent` cases:

- `.system(SystemEvent)` — session init, delivers sessionID / cwd / tools / MCP status
- `.streamEvent(StreamDelta)` — token-level deltas (tool use, text, message boundaries)
- `.assistant(AssistantMessage)` — completed assistant blocks
- `.user(UserMessage)` — tool-result blocks fed back to the assistant
- `.result(ResultEvent)` — turn completion with cost / duration / turn count

`rate_limit_event` and other unknown types are skipped without interrupting the stream.

## Building

```bash
swift build
swift test
```
