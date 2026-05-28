# Streaming Architecture and Fixes

The core `opencode` streaming loop has undergone a series of deep fixes to correctly handle SSE connections and SwiftUI updates. This document captures the edge cases fixed in `#30b1558` to prevent regression.

## 1. OpenAPI parts vs. scalar strings
The `opencode` server responds with multi-part streams (e.g. `reasoning` and then `text`). The client initially mapped this to a flat string dictionary, which caused parts to silently overwrite each other on reconnects and made reasoning blocks bleed into the primary output.
*Fix*: `TranscriptMessage` was heavily refactored to wrap a `[TranscriptMessagePart]` array. Both partial updates (`message.part.delta`) and full snap updates (`message.part.updated`) use `partID` locally to explicitly append to their own streams.

## 2. HTTP Chunk Buffering in URLSession
Swift's native `URLSession.shared.bytes.lines` sequence has a notorious failure mode on HTTP chunked responses where the chunks are not delimited strictly by the payload length, waiting up to 8KB before flushing parsed strings.
*Fix*: The stream iterator was converted to a manual `for try await byte in bytes` loop that parses `\n` delineated events specifically, completely bypassing Swift's async text sequence buffering logic.

## 3. Required Headers for SSE
`URLSession` may default to treating a `GET` without a specific media type as a standard JSON bulk download, leading upstream CDNs and the Foundation layer itself to sit and wait for the HTTP connection to close.
*Fix*: Forced the `Accept: text/event-stream` and `Cache-Control: no-cache` headers on the event request generator.

## 4. Reconnection and Backoff
The OpenCode `opencode serve` SSE endpoint terminates the stream intentionally when the server sits completely idle, to clean up inactive streams.
*Fix*: Wrapped the byte loop in a persistent `while !Task.isCancelled` block. When the `opencode` server drops the connection on idle, the app gracefully reconnects with a 1-second backoff.

## 5. SwiftUI @Published Deep Mutation
Updating the deep parts array `sessions[i].messages[j].parts[k].text += delta` triggered an `objectWillChange` on `sessions`, but views reading the data via the computed variable `appState.selectedSession` failed to redraw.
*Fix*: Removed the use of the detached `selectedSession` getter inside `TranscriptView`'s iterators in favor of an inline `.first(where: { $0.id == appState.selectedSessionID })` block, establishing a strict binding between the `sessions` state array and the view body.
