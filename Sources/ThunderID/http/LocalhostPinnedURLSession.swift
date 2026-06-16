import Foundation
import Security

final class LocalhostPinnedURLSession: NSObject, URLSessionDelegate {
    private let host: String
    private let pinnedCertificateData: Data?

    private init(host: String, pinnedCertificateData: Data?) {
        self.host = host
        self.pinnedCertificateData = pinnedCertificateData
    }

    static func make(for baseUrl: String) -> URLSession {
        guard let url = URL(string: baseUrl),
              let host = url.host,
              host == "localhost" else {
            return .shared
        }

        let certData = Bundle.main.url(forResource: "server", withExtension: "cert")
            .flatMap { loadCertificateData(from: $0) }
        let delegate = LocalhostPinnedURLSession(host: host, pinnedCertificateData: certData)
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            challenge.protectionSpace.host == host,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let pinned = pinnedCertificateData {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
                  (SecCertificateCopyData(certificate) as Data) == pinned else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private static func loadCertificateData(from url: URL) -> Data? {
        guard let fileData = try? Data(contentsOf: url) else {
            return nil
        }

        if let certificate = SecCertificateCreateWithData(nil, fileData as CFData) {
            return SecCertificateCopyData(certificate) as Data
        }

        guard let pemString = String(data: fileData, encoding: .utf8) else {
            return nil
        }

        let base64Lines = pemString
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") && !$0.isEmpty }
            .joined()

        guard
            let derData = Data(base64Encoded: base64Lines),
            let certificate = SecCertificateCreateWithData(nil, derData as CFData)
        else {
            return nil
        }

        return SecCertificateCopyData(certificate) as Data
    }
}
