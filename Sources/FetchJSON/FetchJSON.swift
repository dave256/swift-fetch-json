import Foundation

// from: https://www.avanderlee.com/swift/url-components/
extension Collection where Element == URLQueryItem {
    public subscript(_ name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}

// based on: https://www.avanderlee.com/swift/url-components/
extension Array where Element == URLQueryItem {
    public init(_ dictionary: [String: LosslessStringConvertible]) {
        self = dictionary.map({ (key, value) -> Element in
            URLQueryItem(name: key, value: String(value))
        })
    }
}

/// values for a URLRequest
public protocol URLQueryConfig {

    ///  path/endpoint for the URLRequest
    /// - Returns: the path/endpoint for the URLRequest
    func path() -> String

    /// array of URLQueryItem for the URLRequest
    var queryItems: [URLQueryItem] { get }
}

extension URLQueryConfig {
    /// makes a URLRequest using the components along with the path and query items in the protocol
    /// - Parameters:
    ///   - components: URL components with the scheme and host set
    ///   - headers: if provided set the URLRequest's allHTTPHeaderFields to this
    ///   - method: URLRquest.http method
    ///   - timeoutInterval: if provided, set the URLRequest's timeoutInterval to this
    /// - Returns: URLRequest with the specified values or nil if unable to create the URL
    public func urlRequest(
        components: URLComponents, headers: [String: String],
        method: String? = nil, timeoutInterval: TimeInterval? = nil
    ) -> URLRequest? {
        var components = components
        components.path = path()
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !headers.isEmpty {
            request.allHTTPHeaderFields = headers
        }
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        return request
    }
}

/// errors that can be thrown using URLRequest.fetch and Decodable.fetchAndDecode or Decoable.decode
///
/// the non-Verbose ones are useful in testing to see if that error is thrown without worrying about the specific message
public enum FetchJSONError: Error, Equatable {
    /// the response if not an HTTPResponse returned
    case notHTTPResponse(URLResponse)

    // the code such as 404
    case invalidStatusCode(Int)

    /// if decode throws DecodingError.dataCorrupted
    case dataCorrupted
    case dataCorruptedVerbose(String)

    /// if decode throws DecodingError.keyNotFound
    case keyNotFound
    case keyNotFoundVerbose(String)

    /// if decode throws DecodingError.valueNotFound
    case valueNotFound
    case valueNotFoundVerbose(String)

    /// if decode throws DecodingError.typeMismatch
    case typeMismatch
    case typeMismatchVerbose(String)

    // if decode throws some other Error
    case other
    case otherVerbose(String)
}

extension URLRequest {

    /// fetch data from a URL request and return Data
    ///
    /// throws FetchJSONError.notHTTPResponse or FetchJSONError.invalidStatusCode (if response not 200)
    /// - Returns: Data that was fetched
    public func fetch() async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: self)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FetchJSONError.notHTTPResponse(response)
            }
            guard httpResponse.statusCode == 200 else {
                throw FetchJSONError.invalidStatusCode(httpResponse.statusCode)
            }
            //print(String(data: data, encoding: .utf8) ?? "could not convert data to string")
            return data
        }
    }
}

extension Decodable {

    /// for a Decodable type, fetch the data for the urlRequest and decode into Self
    /// - Parameters:
    ///   - urlRequest: URLRequest to use
    ///   - decoder: optional Decoder to use (uses JSONDecoder() if nil passed
    ///   - verboseErrors: true for more verbose errors if errors thrown
    /// - Returns: Self
    public static func fetchAndDecode(
        urlRequest: URLRequest,
        decoder: JSONDecoder? = nil,
        verboseErrors: Bool = true
    ) async throws -> Self {
        let data = try await urlRequest.fetch()
        return try decode(
            from: data,
            decoder: decoder,
            verboseErrors: verboseErrors
        )
    }

    /// for a Decodable type, try to create Self from the JSON data
    /// - Parameters:
    ///   - data: JSON data to init with
    ///   - decoder: optional Decoder to use (uses JSONDecoder() if nil passed
    ///   - verboseErrors: true for more verbose errors if errors thrown
    /// - Returns: Self
    public static func decode(
        from data: Data,
        decoder: JSONDecoder? = nil,
        verboseErrors: Bool = true
    ) throws -> Self {
        let decoder = decoder ?? JSONDecoder()

        do {
            return try decoder.decode(Self.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            if verboseErrors {
                throw FetchJSONError.dataCorruptedVerbose(
                    "Data corrupted: \(context.debugDescription)")
            } else {
                throw FetchJSONError.dataCorrupted
            }
        } catch DecodingError.keyNotFound(let key, let context) {
            if verboseErrors {
                throw
                    FetchJSONError
                    .keyNotFoundVerbose(
                        "Key '\(key)' not found: \(context.debugDescription), codingPath: \(context.codingPath)"
                    )
            } else {
                throw FetchJSONError.keyNotFound
            }
        } catch DecodingError.valueNotFound(let value, let context) {
            if verboseErrors {
                throw
                    FetchJSONError
                    .valueNotFoundVerbose(
                        "Value '\(value)' not found: \(context.debugDescription), codingPath: \(context.codingPath)"
                    )
            } else {
                throw FetchJSONError
                    .valueNotFound
            }
        } catch DecodingError.typeMismatch(let type, let context) {
            if verboseErrors {
                throw
                    FetchJSONError
                    .typeMismatchVerbose(
                        "Type '\(type)' mismatch: \(context.debugDescription), codingPath: \(context.codingPath)"
                    )
            } else {
                throw FetchJSONError.typeMismatch
            }
        } catch {
            if verboseErrors {
                throw FetchJSONError.otherVerbose(
                    "Other error: \(error.localizedDescription)")
            } else {
                throw FetchJSONError.other
            }
        }
    }
}
