import Foundation
import Testing

@testable import StructuredConcurrency

@Suite("withMinDuration Tests")
struct MinDurationTests {
    @Test("success path respects floor")
    func successPathRespectsFloor() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        let value = try await withMinDuration(.milliseconds(200)) {
            42
        }

        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(200))
        #expect(value == 42)
    }

    @Test("throwing path respects floor")
    func throwingPathRespectsFloor() async throws {
        struct TestError: Error {}

        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: TestError.self) {
            try await withMinDuration(.milliseconds(200)) {
                throw TestError()
            }
        }

        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(200))
    }

    @Test("slow operation not delayed further")
    func slowOperationNotDelayedFurther() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        let value = try await withMinDuration(.milliseconds(100)) {
            try await Task.sleep(for: .milliseconds(300))
            return 7
        }

        let elapsed = clock.now - start
        #expect(elapsed < .milliseconds(500))
        #expect(value == 7)
    }
}
