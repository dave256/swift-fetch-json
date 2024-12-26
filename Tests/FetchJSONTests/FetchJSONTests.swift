import Foundation
import Testing

@testable import FetchJSON

// use icanhazdadjoke.com for testing

struct Joke: Identifiable, Hashable, Codable {
    var id: String
    var joke: String
}

struct JokeConfig: URLQueryConfig {
    static var baseComponents: URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "icanhazdadjoke.com"
        return components
    }

    static var headers: [String: String] {
        [
            "Accept": "application/json",
        ]
    }

    enum RequestType {
        case random
        case byID(String)
    }
    var requestType: RequestType

    func path() -> String {
        switch requestType {
            case .random:
                return "/"
            case .byID(let id):
                return "/j/\(id)"
        }
    }

    var queryItems: [URLQueryItem] = []

    static func randomRequest() -> URLRequest? {
        let config: JokeConfig = .init(requestType: .random)
        return config
            .urlRequest(components: JokeConfig.baseComponents, headers: JokeConfig.headers)
    }

    static func byIDRequest(id: String) -> URLRequest? {
        let config: JokeConfig = .init(requestType: .byID(id))
        return config
            .urlRequest(components: JokeConfig.baseComponents, headers: JokeConfig.headers)
    }
}

public struct JokeSearch: Codable {
    let status: Int
    let limit: Int
    let results: [Joke]
    let nextPage: Int
    let previousPage: Int
    let totalPages: Int
    let totalJokes: Int
    let searchTerm: String
    let currentPage: Int

    enum CodingKeys: String, CodingKey {
        case nextPage = "next_page"
        case previousPage = "previous_page"
        case totalPages = "total_pages"
        case totalJokes = "total_jokes"
        case searchTerm = "search_term"
        case currentPage = "current_page"
        case status
        case limit
        case results
    }
}

struct JokeSearchConfig: URLQueryConfig {
    var searchTerm: String?
    var page: Int?
    var limit: Int?

    func path() -> String {
        "/search"
    }

    var queryItems: [URLQueryItem] {
        var items: [String: LosslessStringConvertible] = [:]
        if let searchTerm { items["term"] = searchTerm }
        if let page { items["page"] = page }
        if let limit { items["limit"] = limit }
        let queryItems: [URLQueryItem] = .init(items)
        return queryItems
    }

    static var headers: [String: String] {
        [
            "Accept": "application/json",
        ]
    }

    static func searchRequest(search: String? = nil, page: Int? = nil, limit: Int? = nil) -> URLRequest? {
        let config: JokeSearchConfig = .init(searchTerm: search, page: page, limit: limit)
        return config
            .urlRequest(components: JokeConfig.baseComponents, headers: JokeConfig.headers)
    }

}

extension JokeSearchConfig {
    init(searchTerm: String) {
        self.init(searchTerm: searchTerm, page: nil, limit: nil)
    }
}


// MARK: - test extensions

extension JokeConfig {
    static let sampleID = "EYoz51DtHtc"
    static let sampleURL = "https://icanhazdadjoke.com/j/\(sampleID)"
    static let sampleCorrectResponse = """
        {"id":"\(sampleID)","joke":"What do computers and air conditioners have in common? They both become useless when you open windows.","status":200}
        """
    static let sampleJokeRequest = JokeConfig.byIDRequest(id: sampleID)!

    static let sampleJoke = Joke(
        id: sampleID,
        joke:
            "What do computers and air conditioners have in common? They both become useless when you open windows."
    )
}

// MARK: -

struct JokeTests {
    struct BasicTest {
        @Test func searchByID() async throws {
            // make certain not nil
            let request = try #require(JokeConfig.byIDRequest(id: JokeConfig.sampleID))
            #expect(request.url!.absoluteString == JokeConfig.sampleURL)
            await #expect(throws: Never.self) {
                let joke = try await Joke.fetchAndDecode(urlRequest: request)
                #expect(joke == JokeConfig.sampleJoke)
            }
        }

        @Test func randomJoke() async throws {
            let request = try #require(JokeConfig.randomRequest())
            print(request.url!.absoluteString)
            await #expect(throws: Never.self) {
                let joke = try await Joke.fetchAndDecode(urlRequest: request)
                #expect(!joke.id.isEmpty)
                #expect(!joke.joke.isEmpty)
            }
        }
    }

    struct ErrorHandlingTests {
        static let badResponseCode = JokeConfig.sampleCorrectResponse
            .replacingOccurrences(of: "200", with: "404")

        @Test func badResponse() async throws {
            var request = try #require(JokeConfig.randomRequest())
            request.url = URL(string: "https://icanhazdadjoke.com/abc")!
            await #expect(throws: FetchJSONError.invalidStatusCode(404)) {
                _ = try await Joke.fetchAndDecode(urlRequest: request)
            }
        }

        @Test func badJokeID() async throws {
            let request = try #require(JokeConfig.byIDRequest(id: "123"))
            await #expect(throws: FetchJSONError.keyNotFound) {
                _ = try await Joke.fetchAndDecode(
                    urlRequest: request, verboseErrors: false)
            }
        }

        @Test func badJokeIDVerboseErrors() async throws {
            let request = try #require(JokeConfig.byIDRequest(id: "123"))
            do {
                _ = try await Joke.fetchAndDecode(
                    urlRequest: request, verboseErrors: true)
            } catch let FetchJSONError.keyNotFoundVerbose(message) {
                #expect(message.contains("id"))
                return
            }
            // some other error was thrown
            #expect(Bool(false))
        }

        @Test func badJokeKey() async throws {
            struct JokeBadKey: Identifiable, Hashable, Codable {
                var id: String
                var jokeBadKey: String
            }
            let request = try #require(JokeConfig.sampleJokeRequest)
            await #expect(throws: FetchJSONError.keyNotFound) {
                _ =
                    try await JokeBadKey
                    .fetchAndDecode(urlRequest: request, verboseErrors: false)
            }
        }

        @Test func badJokeKeyVerboseErrors() async throws {
            struct JokeBadKey: Identifiable, Hashable, Codable {
                var id: String
                var jokeBadKey: String
            }
            let request = try #require(JokeConfig.sampleJokeRequest)
            do {
                _ =
                    try await JokeBadKey.fetchAndDecode(urlRequest: request)
            } catch let FetchJSONError.keyNotFoundVerbose(message) {
                #expect(message.contains("jokeBadKey"))
                return
            }
            // some other error was thrown
            #expect(Bool(false))
        }

        @Test func extraJokeKey() async throws {
            struct JokeExtraKey: Identifiable, Hashable, Codable {
                var id: String
                var joke: String
                var extraKey: String
            }
            let request = try #require(JokeConfig.sampleJokeRequest)
            await #expect(throws: FetchJSONError.keyNotFound) {
                _ = try await JokeExtraKey.fetchAndDecode(
                    urlRequest: request, verboseErrors: false)
            }
        }

        @Test func extraJokeKeyVerboseErrors() async throws {
            struct JokeExtraKey: Identifiable, Hashable, Codable {
                var id: String
                var joke: String
                var extraKey: String
            }
            let request = try #require(JokeConfig.sampleJokeRequest)
            do {
                _ =
                    try await JokeExtraKey
                    .fetchAndDecode(urlRequest: request, verboseErrors: true)
            } catch let FetchJSONError.keyNotFoundVerbose(message) {
                #expect(message.contains("extraKey"))
                return
            }
            // some other error was thrown
            #expect(Bool(false))
        }
    }
}

struct JokeSearchTests {
    @Test func searchWindows() async throws {
        let request = try #require(JokeSearchConfig.searchRequest(search: "windows"))
//        let url = request.url!
//        print(url)
        await #expect(throws: Never.self) {
            let jokes = try await JokeSearch.fetchAndDecode(urlRequest: request)
            #expect(!jokes.results.isEmpty)
            #expect(jokes.currentPage == 1)
            #expect(jokes.nextPage == 1)
            for joke in jokes.results {
                #expect(joke.joke.contains("windows"))
//                print(joke.joke)
            }
        }
    }

    @Test func searchComputerOrWindows() async throws {
        let request = try #require(JokeSearchConfig.searchRequest(search: "computer windows", page: 1, limit: 5))
//        let url = request.url!
//        print(url)
        await #expect(throws: Never.self) {
            let jokes = try await JokeSearch.fetchAndDecode(urlRequest: request)
            #expect(!jokes.results.isEmpty)
            #expect(jokes.currentPage == 1)
            #expect(jokes.nextPage == 1)
            #expect(jokes.results.count <= 5)
            for joke in jokes.results {
                #expect(joke.joke.contains("windows") || joke.joke.contains("computer"))
//                print(joke.joke)
            }
        }
    }

    @Test func searchPage2() async throws {
        let request = try #require(JokeSearchConfig.searchRequest(
            page: 2,
            limit: 10
        ))
//        let url = request.url!
//        print(url)
        await #expect(throws: Never.self) {
            let jokes = try await JokeSearch.fetchAndDecode(urlRequest: request)
            #expect(!jokes.results.isEmpty)
            #expect(jokes.currentPage == 2)
            #expect(jokes.nextPage == 3)
            #expect(jokes.results.count == 10)
        }
    }
}
