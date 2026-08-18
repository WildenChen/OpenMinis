import XCTest
@testable import Minis

/// Config/credential coverage for the External Agent Backend settings surface
/// (issue #4): URL + agent ID save/reload, Keychain-backed credential semantics
/// (including that the secret never lands in UserDefaults), explicit
/// activate/deactivate resolution, and the registry reading only adapter-owned
/// transport config. No network, no real Keychain.
final class OpenClawBackendConfigTests: XCTestCase {

    /// Deterministic in-memory stand-in for the Keychain-backed credential store.
    private final class InMemoryCredentialStorage: OpenClawCredentialStorage, @unchecked Sendable {
        var value: String?
        func save(_ token: String) -> Bool { value = token; return true }
        func load() -> String? { value }
        func delete() { value = nil }
    }

    override func setUp() {
        super.setUp()
        // Reset shared state so tests never depend on order or on a real Keychain.
        OpenClawBackendCredentialStore.storage = InMemoryCredentialStorage()
        OpenClawBackendConfigStore.setBaseURL(nil)
        OpenClawBackendConfigStore.setAgentID(nil)
        AgentBackendConfigStore.setActive(nil)
    }

    override func tearDown() {
        OpenClawBackendCredentialStore.storage = OpenClawKeychainCredentialStorage()
        OpenClawBackendConfigStore.setBaseURL(nil)
        OpenClawBackendConfigStore.setAgentID(nil)
        AgentBackendConfigStore.setActive(nil)
        super.tearDown()
    }

    // MARK: - URL + agent ID persistence

    func testConfigStoreSaveReloadBaseURLAndAgentID() {
        let url = URL(string: "http://192.168.1.50:18789")!
        OpenClawBackendConfigStore.setBaseURL(url)
        OpenClawBackendConfigStore.setAgentID("yujie")

        let loaded = OpenClawBackendConfigStore.load()
        XCTAssertEqual(loaded.baseURL, url)
        XCTAssertEqual(loaded.agentID, "yujie")
    }

    func testConfigStoreDefaultsWhenNothingSet() {
        let loaded = OpenClawBackendConfigStore.load()
        XCTAssertEqual(loaded.baseURL, OpenClawBackendConfig.defaultBaseURL)
        XCTAssertNil(loaded.agentID)
    }

    func testConfigStoreClearingValuesRestoresDefaults() {
        OpenClawBackendConfigStore.setBaseURL(URL(string: "http://example.com")!)
        OpenClawBackendConfigStore.setAgentID("yujie")
        OpenClawBackendConfigStore.setBaseURL(nil)
        OpenClawBackendConfigStore.setAgentID(nil)

        let loaded = OpenClawBackendConfigStore.load()
        XCTAssertEqual(loaded.baseURL, OpenClawBackendConfig.defaultBaseURL)
        XCTAssertNil(loaded.agentID)
    }

    // MARK: - Credential store semantics

    func testCredentialStoreSaveLoadDelete() {
        XCTAssertFalse(OpenClawBackendCredentialStore.isConfigured)
        XCTAssertNil(OpenClawBackendCredentialStore.load())

        XCTAssertTrue(OpenClawBackendCredentialStore.save("tok-123"))
        XCTAssertTrue(OpenClawBackendCredentialStore.isConfigured)
        XCTAssertEqual(OpenClawBackendCredentialStore.load(), "tok-123")

        OpenClawBackendCredentialStore.delete()
        XCTAssertFalse(OpenClawBackendCredentialStore.isConfigured)
        XCTAssertNil(OpenClawBackendCredentialStore.load())
    }

    func testCredentialStoreReplaceUpdatesValue() {
        XCTAssertTrue(OpenClawBackendCredentialStore.save("tok-old"))
        XCTAssertTrue(OpenClawBackendCredentialStore.save("tok-new"))
        XCTAssertEqual(OpenClawBackendCredentialStore.load(), "tok-new")
    }

    func testCredentialStoreNeverWritesUserDefaults() {
        let before = UserDefaults.standard.dictionaryRepresentation()
        let secret = "ultra-secret-gateway-token"
        XCTAssertTrue(OpenClawBackendCredentialStore.save(secret))
        XCTAssertEqual(OpenClawBackendCredentialStore.load(), secret)

        let after = UserDefaults.standard.dictionaryRepresentation()
        XCTAssertEqual(after.count, before.count, "saving a credential must not add UserDefaults keys")
        for (key, value) in after {
            let matchesKey = key.contains("soulnest") || key.contains("openclaw")
            let matchesValue = "\(value)".contains(secret)
            XCTAssertFalse(matchesKey && matchesValue, "credential leaked into UserDefaults key \(key)")
            XCTAssertFalse(matchesValue, "credential value leaked into UserDefaults key \(key)")
        }
    }

    func testConfigStoreLoadInjectsKeychainCredential() {
        XCTAssertTrue(OpenClawBackendCredentialStore.save("tok-keychain"))
        XCTAssertEqual(OpenClawBackendConfigStore.load().gatewayToken, "tok-keychain")
    }

    // MARK: - Explicit activate / deactivate

    @MainActor
    func testActivateThenDeactivateResolvesSyntheticBackendEntry() {
        AgentBackendRegistry.registerOpenClaw()

        AgentBackendConfigStore.setActive(AgentBackendConfig(backendID: "openclaw", agentID: "yujie"))
        XCTAssertTrue(AgentBackendConfigStore.isActive)
        XCTAssertEqual(AgentBackendConfigStore.loadActive()?.backendID, "openclaw")
        XCTAssertEqual(AgentBackendConfigStore.loadActive()?.agentID, "yujie")

        guard let resolved = AgentBackendActiveState.resolved() else {
            return XCTFail("expected resolved backend while active")
        }
        XCTAssertEqual(resolved.provider.name, "OpenClaw")
        XCTAssertTrue(AgentBackendActiveState.isBackendEntry(resolved.entry))

        AgentBackendConfigStore.setActive(nil)
        XCTAssertFalse(AgentBackendConfigStore.isActive)
        XCTAssertNil(AgentBackendConfigStore.loadActive())
        XCTAssertNil(AgentBackendActiveState.resolved())
    }

    @MainActor
    func testUnregisteredHermesNeverResolvesAsActive() {
        AgentBackendRegistry.registerOpenClaw()
        // A Hermes config could never be instantiated today; it must not resolve.
        AgentBackendConfigStore.setActive(AgentBackendConfig(backendID: "hermes", agentID: "pilot"))
        XCTAssertNil(AgentBackendActiveState.resolved())
    }

    // MARK: - Registry reads only adapter-owned transport config

    @MainActor
    func testRegistryFactoryReadsAdapterOwnedTransport() {
        let url = URL(string: "http://192.168.1.50:18789")!
        OpenClawBackendConfigStore.setBaseURL(url)
        OpenClawBackendConfigStore.setAgentID("default-agent")
        XCTAssertTrue(OpenClawBackendCredentialStore.save("tok-adapter"))

        AgentBackendRegistry.registerOpenClaw()
        AgentBackendConfigStore.setActive(AgentBackendConfig(backendID: "openclaw", agentID: "yujie"))
        defer { AgentBackendConfigStore.setActive(nil) }

        guard let resolved = AgentBackendActiveState.resolved(),
              let backend = resolved.provider.backend as? OpenClawBackend else {
            return XCTFail("expected an OpenClawBackend provider")
        }
        XCTAssertEqual(backend.config.baseURL, url)
        XCTAssertEqual(backend.config.agentID, "yujie")
        XCTAssertEqual(backend.config.gatewayToken, "tok-adapter")
    }
}
