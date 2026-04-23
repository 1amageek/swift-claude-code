import Foundation
import Testing
@testable import ClaudeCode

@Suite("ClaudeCodeConfiguration")
struct ConfigurationTests {

    @Test("defaults include prompt, output format, and dangerous-skip-permissions")
    func defaultArguments() {
        let config = ClaudeCodeConfiguration()
        let args = config.arguments(prompt: "hello")
        #expect(args.contains("-p"))
        #expect(args.contains("hello"))
        #expect(args.contains("--output-format"))
        #expect(args.contains("stream-json"))
        #expect(args.contains("--verbose"))
        #expect(args.contains("--include-partial-messages"))
        #expect(args.contains("--dangerously-skip-permissions"))
    }

    @Test("resumeSessionID adds --resume flag")
    func resumeFlag() {
        let config = ClaudeCodeConfiguration()
        let args = config.arguments(prompt: "x", resumeSessionID: "abc")
        let idx = args.firstIndex(of: "--resume")
        #expect(idx != nil)
        if let idx { #expect(args[args.index(after: idx)] == "abc") }
    }

    @Test("model rawValue is forwarded")
    func modelRawValue() {
        var config = ClaudeCodeConfiguration(model: .sonnet)
        var args = config.arguments(prompt: "x")
        #expect(args.contains("--model"))
        #expect(args.contains("claude-sonnet-4-6"))

        config.model = .custom("claude-opus-4-7")
        args = config.arguments(prompt: "x")
        #expect(args.contains("claude-opus-4-7"))
    }

    @Test("mcpConfigs and mcpConfigPath can coexist")
    func mcpDualMode() {
        let path = URL(fileURLWithPath: "/tmp/mcp.json")
        let config = ClaudeCodeConfiguration(
            mcpConfigs: ["{\"a\":1}", "{\"b\":2}"],
            mcpConfigPath: path
        )
        let args = config.arguments(prompt: "x")
        let mcpIndices = args.enumerated().compactMap { $0.element == "--mcp-config" ? $0.offset : nil }
        #expect(mcpIndices.count == 2)
        #expect(args.contains("{\"a\":1}"))
        #expect(args.contains("{\"b\":2}"))
        #expect(args.contains(path.path))
    }

    @Test("plugin directories pass as repeated --plugin-dir")
    func pluginDirectories() {
        let a = URL(fileURLWithPath: "/tmp/plugin-a")
        let b = URL(fileURLWithPath: "/tmp/plugin-b")
        let config = ClaudeCodeConfiguration(pluginDirectories: [a, b])
        let args = config.arguments(prompt: "x")
        let pluginDirCount = args.filter { $0 == "--plugin-dir" }.count
        #expect(pluginDirCount == 2)
        #expect(args.contains(a.path))
        #expect(args.contains(b.path))
    }

    @Test("shellCommand with OAuth enforcement unsets API key vars")
    func shellCommandOAuthOnly() {
        let config = ClaudeCodeConfiguration(enforceOAuthOnly: true)
        let cmd = config.shellCommand(prompt: "hello")
        #expect(cmd.contains("unset"))
        #expect(cmd.contains("ANTHROPIC_API_KEY"))
        #expect(cmd.contains("ANTHROPIC_AUTH_TOKEN"))
        #expect(cmd.contains("ANTHROPIC_BASE_URL"))
    }

    @Test("shellCommand without OAuth enforcement keeps API key vars")
    func shellCommandAllowAPIKey() {
        let config = ClaudeCodeConfiguration(enforceOAuthOnly: false)
        let cmd = config.shellCommand(prompt: "hello")
        #expect(!cmd.contains("ANTHROPIC_API_KEY"))
        #expect(!cmd.contains("ANTHROPIC_AUTH_TOKEN"))
    }

    @Test("shellCommand applies ulimit when raiseFileDescriptorLimit is true")
    func shellCommandFDLimit() {
        let withLimit = ClaudeCodeConfiguration(raiseFileDescriptorLimit: true)
        let without = ClaudeCodeConfiguration(raiseFileDescriptorLimit: false)
        #expect(withLimit.shellCommand(prompt: "x").contains("ulimit -n"))
        #expect(!without.shellCommand(prompt: "x").contains("ulimit"))
    }

    @Test("additionalDirectories pass as --add-dir followed by paths")
    func additionalDirectories() {
        let dirs = [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]
        let config = ClaudeCodeConfiguration(additionalDirectories: dirs)
        let args = config.arguments(prompt: "x")
        #expect(args.contains("--add-dir"))
        #expect(args.contains("/a"))
        #expect(args.contains("/b"))
    }

    @Test("auth allowed methods accept claude.ai only")
    func authAllowedMethods() {
        let oauth = ClaudeCodeConfiguration.AuthStatus(loggedIn: true, authMethod: "claude.ai")
        let apiKey = ClaudeCodeConfiguration.AuthStatus(loggedIn: true, authMethod: "apiKey")
        let loggedOut = ClaudeCodeConfiguration.AuthStatus(loggedIn: false, authMethod: nil)
        #expect(oauth.isOAuthAuthenticated)
        #expect(!apiKey.isOAuthAuthenticated)
        #expect(!loggedOut.isOAuthAuthenticated)
    }
}
