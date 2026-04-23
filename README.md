# swift-claude-code

A small Swift actor that spawns the `claude` CLI (Claude Code) as a subprocess,
streams its `--output-format stream-json` events, and maintains multi-turn
conversations via `--resume`.

Used by Bob and agents-in-black.

## Requirements

- macOS 15+
- Swift 6.2+
- The `claude` CLI installed (`~/.local/bin/claude`, `/usr/local/bin/claude`,
  or `/opt/homebrew/bin/claude`) and authenticated via `claude auth login --claudeai`

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

## Configuration

Key fields on `ClaudeCodeConfiguration`:

| Field | Default | Purpose |
|---|---|---|
| `model` | `nil` (subscription default) | `.opus / .sonnet / .haiku / .custom(String)` |
| `dangerouslySkipPermissions` | `true` | Skip all tool approvals |
| `additionalDirectories` | `[]` | `--add-dir` |
| `mcpConfigs` | `[]` | Inline MCP JSON (`--mcp-config`) |
| `mcpConfigPath` | `nil` | Path to isolated MCP config file (`--mcp-config`) |
| `pluginDirectories` | `[]` | `--plugin-dir` |
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

## Event stream

`StreamEvent` cases:

- `.system(SystemEvent)` — session init, delivers sessionID / cwd / tools / MCP status
- `.streamEvent(StreamDelta)` — token-level deltas (tool use, text, message boundaries)
- `.assistant(AssistantMessage)` — completed assistant blocks
- `.user(UserMessage)` — tool-result blocks fed back to the assistant
- `.result(ResultEvent)` — turn completion with cost / duration / turn count

`rate_limit_event` and other unknown types are skipped without interrupting the stream.
