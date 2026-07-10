import Foundation

enum ApiError: LocalizedError {
    case invalidURL
    case network(Error)
    case http(Int, String)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL"
        case .network(let e): "Network error: \(e.localizedDescription)"
        case .http(let code, let body): "HTTP \(code): \(body)"
        case .decode(let e): "Decode error: \(e.localizedDescription)"
        }
    }
}

actor ApiClient {
    private let session: URLSession
    private var baseURL: URL
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    func fetchNotifications(cursor: String?, count: Int = 80) async throws -> NotificationsPage {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/sources/notifications"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "count", value: String(count))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw ApiError.invalidURL
        }

        let data = try await fetchData(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        do {
            return try decoder.decode(NotificationsPage.self, from: data)
        } catch {
            throw ApiError.decode(error)
        }
    }

    func fetchImageData(from url: URL) async throws -> Data {
        try await fetchData(url: url, cachePolicy: .returnCacheDataElseLoad)
    }

    private func fetchData(url: URL, cachePolicy: NSURLRequest.CachePolicy) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = cachePolicy

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ApiError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.http(0, "Not an HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ApiError.http(http.statusCode, body)
        }

        return data
    }
}
