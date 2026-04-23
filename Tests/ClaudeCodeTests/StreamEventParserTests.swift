import Foundation
import Testing
@testable import ClaudeCode

@Suite("StreamEventParser")
struct StreamEventParserTests {

    @Test("system event")
    func system() throws {
        let json = """
        {"type":"system","session_id":"s1","cwd":"/tmp","model":"claude-opus-4-6","tools":["Read"],"mcp_servers":[{"name":"memory","status":"connected"}],"permissionMode":"default"}
        """
        let event = try StreamEventParser().parse(json)
        guard case .system(let sys) = event else { Issue.record("expected .system"); return }
        #expect(sys.sessionID == "s1")
        #expect(sys.cwd == "/tmp")
        #expect(sys.model == "claude-opus-4-6")
        #expect(sys.tools == ["Read"])
        #expect(sys.mcpServers.count == 1)
        #expect(sys.mcpServers.first?.name == "memory")
    }

    @Test("assistant text content")
    func assistantText() throws {
        let json = """
        {"type":"assistant","session_id":"s1","message":{"id":"m1","model":"claude-opus-4-6","content":[{"type":"text","text":"hello"}]}}
        """
        let event = try StreamEventParser().parse(json)
        guard case .assistant(let msg) = event else { Issue.record("expected .assistant"); return }
        #expect(msg.messageID == "m1")
        guard case .text(let t) = msg.content.first else { Issue.record("expected text block"); return }
        #expect(t == "hello")
    }

    @Test("user tool_result")
    func userToolResult() throws {
        let json = """
        {"type":"user","session_id":"s1","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"ok"}]}}
        """
        let event = try StreamEventParser().parse(json)
        guard case .user(let u) = event else { Issue.record("expected .user"); return }
        #expect(u.toolResults.first?.toolUseID == "tu1")
        #expect(u.toolResults.first?.content == "ok")
    }

    @Test("user tool_result with array content")
    func userToolResultArrayContent() throws {
        let json = """
        {"type":"user","session_id":"s1","message":{"content":[{"type":"tool_result","tool_use_id":"tu2","content":[{"type":"text","text":"part1"},{"type":"text","text":"part2"}]}]}}
        """
        let event = try StreamEventParser().parse(json)
        guard case .user(let u) = event else { Issue.record("expected .user"); return }
        #expect(u.toolResults.first?.content == "part1part2")
    }

    @Test("stream_event text delta")
    func streamEventTextDelta() throws {
        let json = """
        {"type":"stream_event","session_id":"s1","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"tok"}}}
        """
        let event = try StreamEventParser().parse(json)
        guard case .streamEvent(let d) = event else { Issue.record("expected .streamEvent"); return }
        guard case .textDelta(_, let text) = d.event else { Issue.record("expected .textDelta"); return }
        #expect(text == "tok")
    }

    @Test("result event")
    func result() throws {
        let json = """
        {"type":"result","session_id":"s1","result":"done","is_error":false,"stop_reason":"end_turn","total_cost_usd":0.01,"duration_ms":123,"num_turns":2}
        """
        let event = try StreamEventParser().parse(json)
        guard case .result(let r) = event else { Issue.record("expected .result"); return }
        #expect(r.numTurns == 2)
        #expect(r.totalCostUSD == 0.01)
        #expect(r.durationMS == 123)
    }

    @Test("rate_limit_event is ignored")
    func rateLimitIgnored() {
        let json = """
        {"type":"rate_limit_event"}
        """
        #expect(throws: StreamEventParser.ParserError.self) {
            try StreamEventParser().parse(json)
        }
    }

    @Test("unknown type throws")
    func unknownType() {
        let json = """
        {"type":"definitely_not_a_type"}
        """
        #expect(throws: StreamEventParser.ParserError.self) {
            try StreamEventParser().parse(json)
        }
    }

    @Test("system init (explicit subtype) parses as .system")
    func systemInitExplicit() throws {
        let json = """
        {"type":"system","subtype":"init","session_id":"s1","cwd":"/tmp","model":"claude-opus-4-6","tools":[],"mcp_servers":[],"permissionMode":"default"}
        """
        let event = try StreamEventParser().parse(json)
        guard case .system(let sys) = event else { Issue.record("expected .system"); return }
        #expect(sys.sessionID == "s1")
    }

    @Test("system status heartbeat parses as .systemStatus (not .system)")
    func systemStatusHeartbeat() throws {
        let json = """
        {"type":"system","subtype":"status","session_id":"s1","status":"requesting"}
        """
        let event = try StreamEventParser().parse(json)
        guard case .systemStatus(let s) = event else {
            Issue.record("expected .systemStatus — status heartbeat must not be treated as init")
            return
        }
        #expect(s.sessionID == "s1")
        #expect(s.status == "requesting")
    }

    @Test("system unknown subtype is ignored")
    func systemUnknownSubtype() {
        let json = """
        {"type":"system","subtype":"something_new","session_id":"s1"}
        """
        #expect(throws: StreamEventParser.ParserError.self) {
            try StreamEventParser().parse(json)
        }
    }

    @Test("result event with subtype, terminal_reason, and usage")
    func resultExtendedFields() throws {
        let json = """
        {"type":"result","subtype":"success","session_id":"s1","result":"done","is_error":false,"stop_reason":"end_turn","terminal_reason":"completed","total_cost_usd":0.05,"duration_ms":900,"num_turns":3,"usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":7}}
        """
        let event = try StreamEventParser().parse(json)
        guard case .result(let r) = event else { Issue.record("expected .result"); return }
        #expect(r.subtype == "success")
        #expect(r.terminalReason == "completed")
        let usage = try #require(r.usage)
        #expect(usage.inputTokens == 10)
        #expect(usage.outputTokens == 20)
        #expect(usage.cacheCreationInputTokens == 5)
        #expect(usage.cacheReadInputTokens == 7)
    }

    @Test("tool_use delta start parses tool id and name")
    func toolUseStartDelta() throws {
        let json = """
        {"type":"stream_event","session_id":"s1","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu9","name":"Read"}}}
        """
        let event = try StreamEventParser().parse(json)
        guard case .streamEvent(let d) = event else { Issue.record("expected .streamEvent"); return }
        guard case .toolUseStart(_, let id, let name) = d.event else {
            Issue.record("expected .toolUseStart"); return
        }
        #expect(id == "tu9")
        #expect(name == "Read")
    }
}
