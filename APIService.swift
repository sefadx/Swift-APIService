import Foundation
import os

/// Genel API hata tipleri
public enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(statusCode: Int, data: Data?)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case noInternetConnection
    case requestTimedOut
    case serverUnavailable
    case unexpected(Error)

    public var errorDescription: String {
        switch self {
        case .invalidURL:
            return "The URL is invalid. Please contact support."
        case .requestFailed(_, let data):
            let message = extractMessage(from: data)
            return "\(message.isEmpty ? "The request failed. Please try again." : message)"
        case .decodingFailed:
            return "Failed to process the response. Please try again later."
        case .encodingFailed:
            return "Failed to send your data. Please try again."
        case .noInternetConnection:
            return "No internet connection. Please check your network settings."
        case .requestTimedOut:
            return "The request timed out. Please try again later."
        case .serverUnavailable:
            return "The server is currently unavailable. Please try again in a few moments."
        case .unexpected(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    private func extractMessage(from data: Data?) -> String {
            guard let data = data else { return "" }
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let message = json["message"] as? String {
                return message
            }
            return ""
        }
}

protocol APIServiceProtocol {
    var baseURL: URL { get }
    func get<T: Decodable>(_ endpoint: APIS, responseType: T.Type) async throws -> T
    func post<T: Decodable, U: Encodable>(_ endpoint: APIS, body: U, responseType: T.Type) async throws -> T
    func put<T: Decodable, U: Encodable>(_ endpoint: APIS, body: U, responseType: T.Type) async throws -> T
    func delete<T: Decodable>(_ endpoint: APIS, responseType: T.Type) async throws -> T

    func getJSON(_ endpoint: APIS) async throws -> Any
    func postJSON<U: Encodable>(_ endpoint: APIS, body: U) async throws -> Any
    func putJSON<U: Encodable>(_ endpoint: APIS, body: U) async throws -> Any
    func deleteJSON(_ endpoint: APIS) async throws -> Any
}

///let base = URL(string: "https://api.example.com")!
///let service: APIServiceProtocol = APIService(baseURL: base)

/// Genel amaçlı HTTP servisi
class APIService: APIServiceProtocol {
    internal let baseURL: URL
    private let session: URLSession
    private let token: String?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "APIService", category: "network")
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(baseURL: URL = AppState.domain,
         token: String? = nil,
         session: URLSession? = nil,
         requestTimeout: TimeInterval = 5,
         jsonEncoder: JSONEncoder = JSONEncoder(),
         jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.baseURL = baseURL
        self.token = token
        // Eğer dışarıdan session verilmemişse, timeout'lı config ile kendimiz oluştururuz
            if let providedSession = session {
                self.session = providedSession
            } else {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = requestTimeout
                config.timeoutIntervalForResource = requestTimeout
                self.session = URLSession(configuration: config)
            }
        
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
        
        // Öneri: date decoding strategy gibi özelleştirmeler
        self.jsonDecoder.keyDecodingStrategy = .useDefaultKeys
        self.jsonDecoder.dateDecodingStrategy = .iso8601withFractionalSeconds
    }

    private func buildURL(_ endpoint: APIS) throws -> URL {
        guard let url = URL(string: endpoint.path(), relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func makeRequest(url: URL, method: String, body: Data? = nil) throws -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = body
            return request
        }

    func get<T: Decodable>(_ endpoint: APIS, responseType: T.Type) async throws -> T {
        let url = try buildURL(endpoint)
        logger.debug("GET \(url.absoluteString)")
        let request = try makeRequest(url: url, method: "GET")
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try decodeData(data, as: responseType)
        } catch let error as APIError {
            logger.error("GET error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("Unexpected GET error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func post<T: Decodable, U: Encodable>(_ endpoint: APIS, body: U, responseType: T.Type) async throws -> T {
        let url = try buildURL(endpoint)
        logger.debug("POST \(url.absoluteString) body: \(String(describing: body))")

        let bodyData: Data
        do{
            bodyData = try jsonEncoder.encode(body)
        } catch {
            logger.error("Encoding error: \(error)")
            throw APIError.encodingFailed(error)
        }
        let request = try makeRequest(url: url, method: "POST", body: bodyData)
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try decodeData(data, as: responseType)
        } catch let error as APIError {
            logger.error("POST error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("Unexpected POST error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func put<T: Decodable, U: Encodable>(_ endpoint: APIS, body: U, responseType: T.Type) async throws -> T {
        let url = try buildURL(endpoint)
        logger.debug("PUT \(url.absoluteString) body: \(String(describing: body))")

        let bodyData: Data
        do{
            bodyData = try jsonEncoder.encode(body)
        } catch {
            logger.error("Encoding error: \(error)")
            throw APIError.encodingFailed(error)
        }
        let request = try makeRequest(url: url, method: "PUT", body: bodyData)
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try decodeData(data, as: responseType)
        } catch let error as APIError {
            logger.error("PUT error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("Unexpected PUT error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func delete<T: Decodable>(_ endpoint: APIS, responseType: T.Type) async throws -> T {
        let url = try buildURL(endpoint)
        logger.debug("DELETE \(url.absoluteString)")
        let request = try makeRequest(url: url, method: "DELETE")
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try decodeData(data, as: responseType)
        } catch let error as APIError {
            logger.error("DELETE error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("Unexpected DELETE error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func getJSON(_ endpoint: APIS) async throws -> Any {
        let url = try buildURL(endpoint)
        logger.debug("GET JSON \(url.absoluteString)")
        let request = try makeRequest(url: url, method: "GET")
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try JSONSerialization.jsonObject(with: data, options: [])
        }  catch let error as APIError {
            logger.error("GET JSON error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("GET JSON error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func postJSON<U: Encodable>(_ endpoint: APIS, body: U) async throws -> Any {
        let url = try buildURL(endpoint)
        logger.debug("POST JSON \(url.absoluteString) body: \(String(describing: body))")

        let bodyData: Data
        do{
            bodyData = try jsonEncoder.encode(body)
        } catch {
            logger.error("Encoding error: \(error)")
            throw APIError.encodingFailed(error)
        }
        let request = try makeRequest(url: url, method: "POST", body: bodyData)
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try JSONSerialization.jsonObject(with: data, options: [])
        }  catch let error as APIError {
            logger.error("POST JSON error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("POST JSON error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func putJSON<U: Encodable>(_ endpoint: APIS, body: U) async throws -> Any {
        let url = try buildURL(endpoint)
        logger.debug("PUT JSON \(url.absoluteString) body: \(String(describing: body))")
        let bodyData: Data
        do{
            bodyData = try jsonEncoder.encode(body)
        } catch {
            logger.error("Encoding error: \(error)")
            throw APIError.encodingFailed(error)
        }
        let request = try makeRequest(url: url, method: "PUT", body: bodyData)
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try JSONSerialization.jsonObject(with: data, options: [])
        }  catch let error as APIError {
            logger.error("PUT JSON error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("PUT JSON error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    func deleteJSON(_ endpoint: APIS) async throws -> Any {
        let url = try buildURL(endpoint)
        logger.debug("DELETE JSON \(url.absoluteString)")
        let request = try makeRequest(url: url, method: "DELETE")
        do {
            let (data, response) = try await session.data(for: request)
            logger.debug("RESPONSE data: \(String(decoding: data, as: UTF8.self))\n response: \(response)")
            try validateResponse(response, data: data)
            return try JSONSerialization.jsonObject(with: data, options: [])
        }  catch let error as APIError {
            logger.error("DELETE JSON error: \(error) | URL: \(url.absoluteString)")
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw APIError.noInternetConnection
            case .timedOut:
                throw APIError.requestTimedOut
            case .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                throw APIError.serverUnavailable
            default:
                throw APIError.unexpected(urlError)
            }
        } catch {
            logger.error("DELETE JSON error: \(error) | URL: \(url.absoluteString)")
            throw APIError.unexpected(error)
        }
    }

    // MARK: - Yardımcı metodlar
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unexpected(URLError(.badServerResponse))
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            logger.warning("HTTP status code: \(httpResponse.statusCode)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func decodeData<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding error: \(error) | Data: \(String(decoding: data, as: UTF8.self))")
            throw APIError.decodingFailed(error)
        }
    }
}
