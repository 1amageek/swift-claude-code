import Foundation

// MARK: - Top-Level Envelope

/// A single line from Claude Code's `--output-format stream-json` stdout.
public enum StreamEvent: Sendable {
    case system(SystemEvent)
    case systemStatus(SystemStatusEvent)
    case streamEvent(StreamDelta)
    case assistant(AssistantMessage)
    case user(UserMessage)
    case result(ResultEvent)
}

// MARK: - System Init

public struct SystemEvent: Sendable {
    public var sessionID: String
    public var cwd: String
    public var model: String
    public var tools: [String]
    public var mcpServers: [MCPServerStatus]
    public var permissionMode: String

    public init(
        sessionID: String,
        cwd: String,
        model: String,
        tools: [String],
        mcpServers: [MCPServerStatus],
        permissionMode: String
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.model = model
        self.tools = tools
        self.mcpServers = mcpServers
        self.permissionMode = permissionMode
    }
}

public struct MCPServerStatus: Sendable {
    public var name: String
    public var status: String

    public init(name: String, status: String) {
        self.name = name
        self.status = status
    }
}

// MARK: - System Status (heartbeat)

/// Emitted by the CLI between init and result, e.g. `{"subtype":"status","status":"requesting"}`.
/// Callers can use this to surface intermediate activity without overwriting session metadata.
public struct SystemStatusEvent: Sendable {
    public var sessionID: String
    public var status: String

    public init(sessionID: String, status: String) {
        self.sessionID = sessionID
        self.status = status
    }
}

// MARK: - Stream Delta

public struct StreamDelta: Sendable {
    public var sessionID: String
    public var parentToolUseID: String?
    public var event: DeltaEvent

    public init(sessionID: String, parentToolUseID: String?, event: DeltaEvent) {
        self.sessionID = sessionID
        self.parentToolUseID = parentToolUseID
        self.event = event
    }
}

public enum DeltaEvent: Sendable {
    case messageStart
    case contentBlockStart(index: Int)
    case toolUseStart(index: Int, toolID: String, toolName: String)
    case textDelta(index: Int, text: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?)
    case messageStop
}

// MARK: - Assistant Message

public struct AssistantMessage: Sendable {
    public var sessionID: String
    public var messageID: String
    public var model: String
    public var content: [ContentBlock]
    public var parentToolUseID: String?

    public init(
        sessionID: String,
        messageID: String,
        model: String,
        content: [ContentBlock],
        parentToolUseID: String?
    ) {
        self.sessionID = sessionID
        self.messageID = messageID
        self.model = model
        self.content = content
        self.parentToolUseID = parentToolUseID
    }
}

public enum ContentBlock: Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: String)
}

// MARK: - User Message (Tool Results)

public struct UserMessage: Sendable {
    public var sessionID: String
    public var toolResults: [ToolResult]

    public init(sessionID: String, toolResults: [ToolResult]) {
        self.sessionID = sessionID
        self.toolResults = toolResults
    }
}

public struct ToolResult: Sendable {
    public var toolUseID: String
    public var content: String

    public init(toolUseID: String, content: String) {
        self.toolUseID = toolUseID
        self.content = content
    }
}

// MARK: - Result

public struct ResultEvent: Sendable {
    public var sessionID: String
    /// `"success"`, `"error_during_execution"`, etc.
    public var subtype: String
    public var result: String
    public var isError: Bool
    public var stopReason: String
    /// CLI-level termination reason (e.g. `"completed"`, `"cancelled"`).
    public var terminalReason: String
    public var totalCostUSD: Double
    public var durationMS: Int
    public var numTurns: Int
    public var usage: Usage?

    public init(
        sessionID: String,
        subtype: String = "",
        result: String,
        isError: Bool,
        stopReason: String,
        terminalReason: String = "",
        totalCostUSD: Double,
        durationMS: Int,
        numTurns: Int,
        usage: Usage? = nil
    ) {
        self.sessionID = sessionID
        self.subtype = subtype
        self.result = result
        self.isError = isError
        self.stopReason = stopReason
        self.terminalReason = terminalReason
        self.totalCostUSD = totalCostUSD
        self.durationMS = durationMS
        self.numTurns = numTurns
        self.usage = usage
    }
}

public struct Usage: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}
