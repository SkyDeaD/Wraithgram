import CryptoKit
import Foundation
import SwiftSignalKit
import XCTest

final class WGNetworkTests: XCTestCase {
    private let body = Data("{\"masks\":[1,2,3]}".utf8)

    private func request(keys: [Data] = [], maxBytes: Int = 1024, etag: String? = nil) -> WGNetworkRequest {
        return WGNetworkRequest(url: URL(string: "https://example.org/catalog.json")!, etag: etag, signingKeys: keys, maxBytes: maxBytes)
    }

    func testSignatureCheckAcceptsEveryKeyEncoding() throws {
        let privateKey = P256.Signing.PrivateKey()
        let signature = try privateKey.signature(for: self.body).derRepresentation.base64EncodedString()
        let publicKey = privateKey.publicKey
        for keyData in [publicKey.rawRepresentation, publicKey.x963Representation, publicKey.derRepresentation] {
            XCTAssertTrue(WGNetwork.isValidSignature(body: self.body, signatureBase64: signature, keys: [keyData]))
        }
        let otherKey = P256.Signing.PrivateKey().publicKey.rawRepresentation
        XCTAssertTrue(WGNetwork.isValidSignature(body: self.body, signatureBase64: signature, keys: [otherKey, publicKey.rawRepresentation]), "key rotation: any key may match")
        XCTAssertFalse(WGNetwork.isValidSignature(body: self.body, signatureBase64: signature, keys: [otherKey]))
        XCTAssertFalse(WGNetwork.isValidSignature(body: Data("tampered".utf8), signatureBase64: signature, keys: [publicKey.rawRepresentation]))
        XCTAssertFalse(WGNetwork.isValidSignature(body: self.body, signatureBase64: nil, keys: [publicKey.rawRepresentation]))
        XCTAssertFalse(WGNetwork.isValidSignature(body: self.body, signatureBase64: "not base64!", keys: [publicKey.rawRepresentation]))
    }

    func testValidation() throws {
        let privateKey = P256.Signing.PrivateKey()
        let signature = try privateKey.signature(for: self.body).derRepresentation.base64EncodedString()
        let key = privateKey.publicKey.rawRepresentation

        let signed = WGNetwork.validate(status: 200, body: self.body, headers: ["x-wg-signature": signature, "Etag": "\"v2\""], request: self.request(keys: [key]))
        XCTAssertEqual(try? signed.get().data, self.body)
        XCTAssertEqual(try? signed.get().etag, "\"v2\"")

        let unsigned = WGNetwork.validate(status: 200, body: self.body, headers: [:], request: self.request(keys: [key]))
        XCTAssertEqual(WGNetworkTests.error(unsigned), .badSignature)

        let notModified = WGNetwork.validate(status: 304, body: Data(), headers: [:], request: self.request(etag: "\"v1\""))
        XCTAssertEqual(try? notModified.get().notModified, true)
        XCTAssertEqual(try? notModified.get().etag, "\"v1\"")

        XCTAssertEqual(WGNetworkTests.error(WGNetwork.validate(status: 404, body: Data(), headers: [:], request: self.request())), .http(404))
        XCTAssertEqual(WGNetworkTests.error(WGNetwork.validate(status: 200, body: self.body, headers: [:], request: self.request(maxBytes: 4))), .tooLarge)
    }

    func testSignatureContextAndHeader() throws {
        let privateKey = P256.Signing.PrivateKey()
        let key = privateKey.publicKey.rawRepresentation
        let context = Data("WG-CATALOG/1\n".utf8)
        var signedMessage = context
        signedMessage.append(self.body)
        let signature = try privateKey.signature(for: signedMessage).derRepresentation.base64EncodedString()
        let bodyOnlySignature = try privateKey.signature(for: self.body).derRepresentation.base64EncodedString()

        // Defaults keep the old contract: `X-WG-Signature` over the body alone.
        let defaults = self.request(keys: [key])
        XCTAssertEqual(defaults.signatureHeader, "X-WG-Signature")
        XCTAssertTrue(defaults.signatureContext.isEmpty)

        var request = self.request(keys: [key])
        request.signatureHeader = "X-GTok-Sig"
        request.signatureContext = context

        let accepted = WGNetwork.validate(status: 200, body: self.body, headers: ["x-gtok-sig": signature], request: request)
        XCTAssertEqual(try? accepted.get().data, self.body, "the response carries the body, not the signed context")

        let sameKeyOtherDomain = WGNetwork.validate(status: 200, body: self.body, headers: ["X-GTok-Sig": bodyOnlySignature], request: request)
        XCTAssertEqual(WGNetworkTests.error(sameKeyOtherDomain), .badSignature, "a body signed without the context is not accepted")

        let defaultHeader = WGNetwork.validate(status: 200, body: self.body, headers: ["X-WG-Signature": signature], request: request)
        XCTAssertEqual(WGNetworkTests.error(defaultHeader), .badSignature, "only the request's own header is read")

        let initialized = WGNetworkRequest(url: URL(string: "https://example.org/badges")!, signingKeys: [key], signatureHeader: "X-GTok-Sig", signatureContext: context)
        let viaInit = WGNetwork.validate(status: 200, body: self.body, headers: ["X-GTok-Sig": signature], request: initialized)
        XCTAssertEqual(try? viaInit.get().data, self.body)
    }

    func testRequestCarriesNothingAboutTheUser() {
        let urlRequest = WGNetwork.makeURLRequest(self.request(etag: "\"v1\""))
        XCTAssertFalse(urlRequest.httpShouldHandleCookies)
        XCTAssertEqual(urlRequest.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "User-Agent"), "Wraithgram")
        XCTAssertEqual(urlRequest.allHTTPHeaderFields?.count, 3)

        let configuration = WGNetwork.makeConfiguration(proxy: nil)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.connectionProxyDictionary)
    }

    func testSocksProxyDictionary() {
        let configuration = WGNetwork.makeConfiguration(proxy: .socks5(host: "127.0.0.1", port: 1080, username: "u", password: "p"))
        let dictionary = configuration.connectionProxyDictionary ?? [:]
        XCTAssertEqual(dictionary["SOCKSEnable"] as? Int, 1)
        XCTAssertEqual(dictionary["SOCKSProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(dictionary["SOCKSPort"] as? Int, 1080)
        XCTAssertEqual(dictionary[kCFStreamPropertySOCKSUser as String] as? String, "u")
        XCTAssertEqual(dictionary[kCFStreamPropertySOCKSPassword as String] as? String, "p")
    }

    func testOnlyHttpsIsFetched() {
        let network = WGNetwork()
        var received: WGNetworkError?
        let request = WGNetworkRequest(url: URL(string: "http://example.org/a.json")!)
        let disposable = network.fetch(request).start(error: { error in
            received = error
        })
        XCTAssertEqual(received, .network)
        disposable.dispose()
    }

    func testDirectRequestsAreRefusedBehindAnotherProxy() {
        let network = WGNetwork()
        network.proxyProvider = {
            return nil
        }
        network.isDirectConnectionAllowedProvider = {
            return false
        }
        var received: WGNetworkError?
        let disposable = network.fetch(self.request()).start(error: { error in
            received = error
        })
        XCTAssertEqual(received, .network)
        disposable.dispose()
    }

    private static func error(_ result: Result<WGNetworkResponse, WGNetworkError>) -> WGNetworkError? {
        switch result {
        case .success:
            return nil
        case let .failure(error):
            return error
        }
    }
}
