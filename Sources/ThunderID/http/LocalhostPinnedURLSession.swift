/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import Foundation
import Security

final class LocalhostPinnedURLSession: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let host: String
    private let pinnedCertificateData: Data?

    private init(host: String, pinnedCertificateData: Data?) {
        self.host = host
        self.pinnedCertificateData = pinnedCertificateData
    }

    static func make(for baseUrl: String) -> URLSession {
        guard let url = URL(string: baseUrl), let host = url.host else {
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

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
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
