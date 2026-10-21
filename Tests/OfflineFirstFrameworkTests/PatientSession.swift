import Foundation

extension URLSession {
    /// A session whose requests wait five minutes: the tests share a CI simulator with heavy
    /// suites, which answers late, not never, and the default 60 seconds failed them there.
    static func patient() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        return URLSession(configuration: configuration)
    }
}
