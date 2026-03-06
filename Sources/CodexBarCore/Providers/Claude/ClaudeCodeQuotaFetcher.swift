import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ClaudeCodeQuotaFetcher {
    fileprivate struct Policy {
        let minimumProbeInterval: TimeInterval
        let successTTL: TimeInterval
        let failureBaseBackoff: TimeInterval
        let failureMaxBackoff: TimeInterval
    }

    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let probeModel = "claude-haiku-4-5-20251001"
    private static let anthropicVersion = "2023-06-01"
    private static let anthropicBeta = "oauth-2025-04-20"
    private static let successTTL: TimeInterval = 10 * 60
    private static let backgroundMinimumProbeInterval: TimeInterval = 60
    private static let userInitiatedMinimumProbeInterval: TimeInterval = 30
    private static let failureBaseBackoff: TimeInterval = 10 * 60
    private static let failureMaxBackoff: TimeInterval = 60 * 60
    private static let cache = ClaudeCodeQuotaCache()

    #if DEBUG
    typealias PerformRequestOverride = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    @TaskLocal static var performRequestOverride: PerformRequestOverride?
    @TaskLocal static var nowOverride: Date?
    #endif

    static func fetchUsage(
        accessToken: String,
        clientVersion: String? = nil) async throws -> OAuthUsageResponse
    {
        let force = ProviderInteractionContext.current == .userInitiated
        let now = self.now()
        let policy = Policy(
            minimumProbeInterval: force ? self.userInitiatedMinimumProbeInterval : self.backgroundMinimumProbeInterval,
            successTTL: self.successTTL,
            failureBaseBackoff: self.failureBaseBackoff,
            failureMaxBackoff: self.failureMaxBackoff)

        return try await self.cache.response(
            accessToken: accessToken,
            now: now,
            force: force,
            policy: policy)
        {
            let request = Self.makeRequest(accessToken: accessToken, clientVersion: clientVersion)
            let (data, response) = try await Self.performRequest(request)
            switch response.statusCode {
            case 200:
                let usage = try Self.decodeUsageResponse(from: response)
                guard usage.fiveHour != nil || usage.sevenDay != nil || usage.sevenDayOpus != nil
                    || usage.sevenDaySonnet != nil
                else {
                    throw ClaudeOAuthFetchError.invalidResponse
                }
                return usage
            case 401, 403:
                throw ClaudeOAuthFetchError.unauthorized
            case 429:
                throw ClaudeOAuthFetchError.rateLimited(Self.retryAfterSeconds(from: response))
            default:
                let body = String(data: data, encoding: .utf8)
                throw ClaudeOAuthFetchError.serverError(response.statusCode, body)
            }
        }
    }

    private static func makeRequest(accessToken: String, clientVersion: String?) -> URLRequest {
        var request = URLRequest(url: self.messagesURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(self.anthropicBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code", forHTTPHeaderField: "x-app-name")
        if let clientVersion = self.normalizedClientVersion(clientVersion) {
            request.setValue(clientVersion, forHTTPHeaderField: "x-app-ver")
            request.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("claude-code", forHTTPHeaderField: "User-Agent")
        }

        let payload: [String: Any] = [
            "model": self.probeModel,
            "max_tokens": 1,
            "messages": [
                [
                    "role": "user",
                    "content": "quota",
                ],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private static func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #if DEBUG
        if let override = self.performRequestOverride {
            return try await override(request)
        }
        #endif

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeOAuthFetchError.invalidResponse
            }
            return (data, http)
        } catch let error as ClaudeOAuthFetchError {
            throw error
        } catch {
            throw ClaudeOAuthFetchError.networkError(error)
        }
    }

    private static func decodeUsageResponse(from response: HTTPURLResponse) throws -> OAuthUsageResponse {
        OAuthUsageResponse(
            fiveHour: self.window(from: response, claim: "5h"),
            sevenDay: self.window(from: response, claim: "7d"),
            sevenDayOAuthApps: nil,
            sevenDayOpus: self.window(from: response, claim: "7d_opus"),
            sevenDaySonnet: self.window(from: response, claim: "7d_sonnet"),
            iguanaNecktie: nil,
            extraUsage: nil)
    }

    private static func window(from response: HTTPURLResponse, claim: String) -> OAuthUsageWindow? {
        let prefix = "anthropic-ratelimit-unified-\(claim)"
        let utilization = response.value(forHTTPHeaderField: "\(prefix)-utilization")
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let resetSeconds = response.value(forHTTPHeaderField: "\(prefix)-reset")
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard utilization != nil || resetSeconds != nil else { return nil }
        let resetsAt = resetSeconds.map { seconds in
            self.iso8601String(fromUnixSeconds: seconds)
        }
        return OAuthUsageWindow(utilization: utilization, resetsAt: resetsAt)
    }

    private static func iso8601String(fromUnixSeconds seconds: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func normalizedClientVersion(_ rawVersion: String?) -> String? {
        guard let rawVersion else { return nil }
        let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let token = trimmed.split(whereSeparator: \.isWhitespace).first
        guard let token else { return nil }
        let normalized = String(token)
        return normalized.isEmpty ? nil : normalized
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        return Int(raw)
    }

    private static func now() -> Date {
        #if DEBUG
        if let override = self.nowOverride {
            return override
        }
        #endif
        return Date()
    }

    #if DEBUG
    static func _decodeUsageResponseForTesting(headers: [String: String]) throws -> OAuthUsageResponse {
        guard let response = HTTPURLResponse(
            url: self.messagesURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers)
        else {
            throw ClaudeOAuthFetchError.invalidResponse
        }
        return try self.decodeUsageResponse(from: response)
    }

    static func _resetCacheForTesting() async {
        await self.cache.reset()
    }
    #endif
}

private actor ClaudeCodeQuotaCache {
    private var cachedAccessToken: String?
    private var cachedResponse: OAuthUsageResponse?
    private var lastSuccessAt: Date?
    private var lastAttemptAt: Date?
    private var backoffUntil: Date?
    private var failureStreak: Int = 0
    private var inFlightTask: Task<OAuthUsageResponse, Error>?

    func response(
        accessToken: String,
        now: Date,
        force: Bool,
        policy: ClaudeCodeQuotaFetcher.Policy,
        producer: @escaping @Sendable () async throws -> OAuthUsageResponse) async throws -> OAuthUsageResponse
    {
        if self.cachedAccessToken != accessToken {
            self.cachedAccessToken = accessToken
            self.cachedResponse = nil
            self.lastSuccessAt = nil
            self.lastAttemptAt = nil
            self.backoffUntil = nil
            self.failureStreak = 0
            self.inFlightTask = nil
        }

        if let inFlightTask {
            return try await inFlightTask.value
        }

        if !force,
           let cachedResponse = self.cachedResponse,
           let lastSuccessAt = self.lastSuccessAt,
           now.timeIntervalSince(lastSuccessAt) < policy.successTTL
        {
            return cachedResponse
        }

        if let backoffUntil = self.backoffUntil, now < backoffUntil {
            if let cachedResponse = self.cachedResponse {
                return cachedResponse
            }
            throw ClaudeOAuthFetchError.rateLimited(Int(ceil(backoffUntil.timeIntervalSince(now))))
        }

        if let lastAttemptAt = self.lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < policy.minimumProbeInterval,
           let cachedResponse = self.cachedResponse
        {
            return cachedResponse
        }

        let task = Task {
            try await producer()
        }
        self.inFlightTask = task
        self.lastAttemptAt = now

        do {
            let response = try await task.value
            self.cachedResponse = response
            self.lastSuccessAt = now
            self.backoffUntil = nil
            self.failureStreak = 0
            self.inFlightTask = nil
            return response
        } catch let error as ClaudeOAuthFetchError {
            self.inFlightTask = nil
            switch error {
            case .unauthorized:
                throw error
            case let .rateLimited(retryAfterSeconds):
                let retryDelay = retryAfterSeconds.map(Double.init)
                    ?? min(
                        policy.failureMaxBackoff,
                        policy.failureBaseBackoff * pow(2, Double(self.failureStreak)))
                self.failureStreak += 1
                self.backoffUntil = now.addingTimeInterval(retryDelay)
            default:
                let retryDelay = min(
                    policy.failureMaxBackoff,
                    policy.failureBaseBackoff * pow(2, Double(self.failureStreak)))
                self.failureStreak += 1
                self.backoffUntil = now.addingTimeInterval(retryDelay)
            }
            if let cachedResponse = self.cachedResponse {
                return cachedResponse
            }
            throw error
        } catch {
            self.inFlightTask = nil
            let retryDelay = min(
                policy.failureMaxBackoff,
                policy.failureBaseBackoff * pow(2, Double(self.failureStreak)))
            self.failureStreak += 1
            self.backoffUntil = now.addingTimeInterval(retryDelay)
            if let cachedResponse = self.cachedResponse {
                return cachedResponse
            }
            throw ClaudeOAuthFetchError.networkError(error)
        }
    }

    #if DEBUG
    func reset() {
        self.cachedAccessToken = nil
        self.cachedResponse = nil
        self.lastSuccessAt = nil
        self.lastAttemptAt = nil
        self.backoffUntil = nil
        self.failureStreak = 0
        self.inFlightTask = nil
    }
    #endif
}
