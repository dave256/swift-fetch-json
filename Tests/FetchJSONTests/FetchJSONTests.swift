import Foundation
import Testing

@testable import FetchJSON

// use icanhazdadjoke.com for testing

struct Joke: Identifiable, Hashable, Codable {
    var id: String
    var joke: String

    enum RequestType {
        case random
        case byID(String)
    }

    static var baseComponents: URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "icanhazdadjoke.com"
        return components
    }

    static func urlComponents(for type: RequestType) -> URLComponents {
        var components = Joke.baseComponents
        switch type {
        case .random:
            components.path = "/"
        case .byID(let id):
            components.path = "/j/\(id)"
        }
        return components
    }

    static func urlRequest(for type: RequestType) -> URLRequest? {
        let components = Self.urlComponents(for: type)
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // specify the header for JSON format of the joke
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

struct JokeSearchConfig {
    var searchTerm: String?
    var page: Int?
    var limit: Int?

    func queryItems() -> [URLQueryItem] {
        var items: [String: LosslessStringConvertible] = [:]
        if let searchTerm { items["term"] = searchTerm }
        if let page { items["page"] = page }
        if let limit { items["limit"] = limit }
        let queryItems: [URLQueryItem] = .init(items)
        return queryItems
    }
}

extension JokeSearchConfig {
    init(searchTerm: String) {
        self.init(searchTerm: searchTerm, page: nil, limit: nil)
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

    static func urlRequest(for search: JokeSearchConfig) -> URLRequest? {
        var components = Joke.baseComponents
        components.path = "/search"
        components.queryItems = search.queryItems()
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // specify the header for JSON format of the joke
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

extension Joke {
    static let sampleURL = "https://icanhazdadjoke.com/j/EYoz51DtHtc"
    static let sampleCorrectResponse = """
        {"id":"EYoz51DtHtc","joke":"What do computers and air conditioners have in common? They both become useless when you open windows.","status":200}
        """
    static let sampleJoke = Joke(
        id: "EYoz51DtHtc",
        joke:
            "What do computers and air conditioners have in common? They both become useless when you open windows."
    )
    static let sampleJokeRequest = Joke.urlRequest(for: .byID("EYoz51DtHtc"))
}

struct JokeTests {
    struct BasicTest {
        @Test func searchByID() async throws {
            // make certain not nil
            let request = try #require(Joke.sampleJokeRequest)
            #expect(request.url?.absoluteString == Joke.sampleURL)
            await #expect(throws: Never.self) {
                let joke = try await Joke.fetchAndDecode(urlRequest: request)
                #expect(joke == Joke.sampleJoke)
            }
        }

        @Test func randomJoke() async throws {
            let request = try #require(Joke.urlRequest(for: .random))
            await #expect(throws: Never.self) {
                let joke = try await Joke.fetchAndDecode(urlRequest: request)
                #expect(!joke.id.isEmpty)
                #expect(!joke.joke.isEmpty)
            }
        }
    }

    struct ErrorHandlingTests {
        static let badResponseCode = Joke.sampleCorrectResponse
            .replacingOccurrences(of: "200", with: "404")

        @Test func badResponse() async throws {
            var request = try #require(Joke.urlRequest(for: .random))
            request.url = URL(string: "https://icanhazdadjoke.com/abc")!
            await #expect(throws: FetchJSONError.invalidStatusCode(404)) {
                _ = try await Joke.fetchAndDecode(urlRequest: request)
            }
        }

        @Test func badJokeID() async throws {
            let request = try #require(Joke.urlRequest(for: .byID("123")))
            await #expect(throws: FetchJSONError.keyNotFound) {
                _ = try await Joke.fetchAndDecode(
                    urlRequest: request, verboseErrors: false)
            }
        }

        @Test func badJokeIDVerboseErrors() async throws {
            let request = try #require(Joke.urlRequest(for: .byID("123")))
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
            let request = try #require(Joke.sampleJokeRequest)
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
            let request = try #require(Joke.sampleJokeRequest)
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
            let request = try #require(Joke.sampleJokeRequest)
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
            let request = try #require(Joke.sampleJokeRequest)
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
        let config = JokeSearchConfig(searchTerm: "windows")
        let request = try #require(JokeSearch.urlRequest(for: config))
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
        let config = JokeSearchConfig(searchTerm: "computer windows", page: 1, limit: 5)
        let request = try #require(JokeSearch.urlRequest(for: config))
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
        let config = JokeSearchConfig(page: 2, limit: 10)
        let request = try #require(JokeSearch.urlRequest(for: config))
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
