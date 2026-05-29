import Foundation

class MockBytesAsyncSequence: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = UInt8

    let dataChunks: [[UInt8]]
    var currentChunkIndex = 0
    var currentByteIndex = 0

    init(chunks: [String]) {
        self.dataChunks = chunks.map { Array($0.utf8) }
    }

    func next() async throws -> UInt8? {
        // simulate streaming delay
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        if currentChunkIndex >= dataChunks.count {
            return nil
        }

        let chunk = dataChunks[currentChunkIndex]
        if currentByteIndex >= chunk.count {
            currentChunkIndex += 1
            currentByteIndex = 0
            return try await next()
        }

        let byte = chunk[currentByteIndex]
        currentByteIndex += 1
        return byte
    }

    func makeAsyncIterator() -> MockBytesAsyncSequence {
        return self
    }
}
