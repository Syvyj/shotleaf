import Core

/// Holds several active providers at once and tracks the current one. Switching
/// providers (Embedded ⇄ LM Studio ⇄ OpenAI ⇄ OpenRouter…) is just `setCurrent`.
/// An actor because it is shared mutable state accessed from multiple tasks.
public actor InferenceProviderRegistry: InferenceProviderResolving {
    private var providers: [String: any InferenceProvider] = [:]
    private var order: [String] = []
    private var currentID: String?
    private let events: (any EventPublishing)?

    public init(events: (any EventPublishing)? = nil) {
        self.events = events
    }

    public func register(_ provider: any InferenceProvider, makeCurrent: Bool = false) {
        if providers[provider.id] == nil { order.append(provider.id) }
        providers[provider.id] = provider
        if makeCurrent || currentID == nil {
            currentID = provider.id
            events?.publish(.providerChanged(id: provider.id))
        }
    }

    @discardableResult
    public func unregister(id: String) -> Bool {
        guard providers.removeValue(forKey: id) != nil else { return false }
        order.removeAll { $0 == id }
        if currentID == id {
            currentID = order.first
            if let current = currentID { events?.publish(.providerChanged(id: current)) }
        }
        return true
    }

    public func setCurrent(id: String) {
        guard providers[id] != nil, currentID != id else { return }
        currentID = id
        events?.publish(.providerChanged(id: id))
    }

    // MARK: InferenceProviderResolving

    public func currentProvider() async -> (any InferenceProvider)? {
        guard let currentID else { return nil }
        return providers[currentID]
    }

    public func provider(id: String) async -> (any InferenceProvider)? {
        providers[id]
    }

    // MARK: Introspection

    public func current() -> String? { currentID }
    public func registeredIDs() -> [String] { order }
    public func allProviders() -> [any InferenceProvider] { order.compactMap { providers[$0] } }
}
