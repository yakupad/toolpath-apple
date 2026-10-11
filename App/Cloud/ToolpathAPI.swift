import Foundation

/// Client for the Toolpath API (Cloudflare Worker): the cloud assistant used
/// when on-device Apple Intelligence isn't available, and purchase
/// verification. The base URL is public; nothing secret ships in the app.
enum ToolpathAPI {
    static let baseURL = URL(string: "https://toolpath-api.yakupad.workers.dev")!

    struct Quota: Decodable, Equatable {
        let plan: String
        let monthlyLimit: Int
        let used: Int
        let credits: Int
        let remaining: Int
        var isPro: Bool { plan == "pro" }
    }

    struct Answer: Decodable {
        let answer: String
        let remaining: Int
        let plan: String
        let monthlyLimit: Int
        let used: Int
        let credits: Int
        var quota: Quota { Quota(plan: plan, monthlyLimit: monthlyLimit, used: used, credits: credits, remaining: remaining) }
    }

    enum APIError: Error, Equatable {
        case quotaExhausted(Quota?)
        case unavailable
        case rateLimited
        case server
    }

    struct Turn: Encodable {
        let role: String
        let text: String
    }

    static func quota() async throws -> Quota {
        try await send(request(path: "v1/assistant/quota", method: "GET", body: Optional<String>.none))
    }

    static func ask(question: String, history: [Turn], context: [String], locale: String) async throws -> Answer {
        struct Body: Encodable { let question: String; let history: [Turn]; let context: [String]; let locale: String }
        return try await send(request(path: "v1/assistant/ask", method: "POST",
                                      body: Body(question: question, history: history, context: context, locale: locale)))
    }

    /// Hands a StoreKit-signed transaction to the API, which verifies Apple's
    /// signature before granting Pro or credits.
    @discardableResult
    static func verify(signedTransaction: String) async throws -> Quota {
        struct Body: Encodable { let signedTransaction: String }
        return try await send(request(path: "v1/iap/verify", method: "POST", body: Body(signedTransaction: signedTransaction)))
    }

    private static func request<B: Encodable>(path: String, method: String, body: B?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue(ToolpathAccount.id.uuidString.lowercased(), forHTTPHeaderField: "x-account-id")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try JSONDecoder().decode(T.self, from: data)
        case 402: throw APIError.quotaExhausted(try? JSONDecoder().decode(Quota.self, from: data))
        case 429: throw APIError.rateLimited
        case 503: throw APIError.unavailable
        default: throw APIError.server
        }
    }
}
