import Foundation
import Testing
@testable import Products

struct LocalDevOriginTests {
    // MARK: - parseOrigin(_:)

    @Test func readsBareHostAndPortAsHttp() {
        #expect(LocalDevOrigin.parseOrigin("localhost:3000") == "http://localhost:3000")
    }

    @Test func keepsAnExplicitHttpScheme() {
        #expect(LocalDevOrigin.parseOrigin("http://localhost:3000") == "http://localhost:3000")
    }

    @Test func reducesAFullUrlToItsOrigin() {
        #expect(LocalDevOrigin.parseOrigin("http://localhost:3000/apps?id=1#k=2") == "http://localhost:3000")
    }

    @Test func acceptsAHostWithoutAPort() {
        #expect(LocalDevOrigin.parseOrigin("localhost") == "http://localhost")
    }

    @Test func acceptsAPrivateLanAddressSoDevicesReachTheDevServer() {
        #expect(LocalDevOrigin.parseOrigin("http://192.168.1.59:3000") == "http://192.168.1.59:3000")
        #expect(LocalDevOrigin.parseOrigin("10.1.2.3:3000") == "http://10.1.2.3:3000")
        #expect(LocalDevOrigin.parseOrigin("172.16.0.1:3000") == "http://172.16.0.1:3000")
        #expect(LocalDevOrigin.parseOrigin("172.31.255.254:8080") == "http://172.31.255.254:8080")
    }

    @Test func rejectsHttpsSinceADevServerIsServedInTheClear() {
        #expect(LocalDevOrigin.parseOrigin("https://localhost:3000") == nil)
    }

    @Test func rejectsAHostThatIsNotLocal() {
        #expect(LocalDevOrigin.parseOrigin("coinflip.dot") == nil)
        #expect(LocalDevOrigin.parseOrigin("http://example.com:3000") == nil)
    }

    @Test func rejectsAPublicAddressWhichIsNeverADevServer() {
        for raw in ["8.8.8.8:3000", "172.15.0.1:3000", "172.32.0.1:3000", "192.169.1.1:3000", "1.2.3.4"] {
            #expect(LocalDevOrigin.parseOrigin(raw) == nil, "expected '\(raw)' to be rejected")
        }
    }

    @Test func doesNotTreatAHostMerelyContainingALocalNameAsLocal() {
        #expect(LocalDevOrigin.parseOrigin("localhost.example.com:3000") == nil)
        #expect(LocalDevOrigin.parseOrigin("notlocalhost:3000") == nil)
    }

    @Test func rejectsSomethingMerelyShapedLikeAnAddress() {
        #expect(LocalDevOrigin.parseOrigin("192.168.1") == nil)
        #expect(LocalDevOrigin.parseOrigin("192.168.1.300:3000") == nil)
    }

    @Test func rejectsBlankInput() {
        #expect(LocalDevOrigin.parseOrigin("") == nil)
        #expect(LocalDevOrigin.parseOrigin("   ") == nil)
    }

    @Test func isCaseInsensitiveAboutSchemeAndHost() {
        #expect(LocalDevOrigin.parseOrigin("HTTP://LocalHost:3000") == "http://localhost:3000")
    }

    // MARK: - productLabel(forOrigin:)

    @Test func buildsALabelProductHostAccepts() {
        let label = LocalDevOrigin.productLabel(forOrigin: "http://192.168.1.59:3000")

        #expect(label == "dev-192.168.1.59-3000")
        #expect(ProductHost(name: label, root: "paseo") != nil)
    }

    @Test func derivesADistinctLabelPerOriginSoTwoPortsAreTwoProducts() {
        let first = LocalDevOrigin.productLabel(forOrigin: "http://localhost:3000")
        let second = LocalDevOrigin.productLabel(forOrigin: "http://localhost:5173")

        #expect(first == "dev-localhost-3000")
        #expect(first != second)
    }

    // MARK: - origin(forProductId:)

    // MARK: - origin(forProductId:)

    @Test func readsTheOriginFromTheIdADevProductTransactsUnder() {
        // A dev product is identified by its origin's authority — the same string the page reads from
        // `window.location.host` and sends back as its own identifier.
        #expect(LocalDevOrigin.origin(forProductId: "localhost:3000") == "http://localhost:3000")
        #expect(LocalDevOrigin.origin(forProductId: "192.168.1.59:3000") == "http://192.168.1.59:3000")
        #expect(LocalDevOrigin.origin(forProductId: "localhost") == "http://localhost")
    }

    @Test func returnsNoOriginForAnOrdinaryDotNsProduct() {
        #expect(LocalDevOrigin.origin(forProductId: "coinflip.paseo") == nil)
        #expect(LocalDevOrigin.origin(forProductId: "browse.dot") == nil)
    }

    @Test func returnsNoOriginForAPublicAuthority() {
        #expect(LocalDevOrigin.origin(forProductId: "example.com:3000") == nil)
    }
}
