// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// A chunked, parallel downloader -- the way Gopeed does it.
///
/// One HEAD to learn the size and whether the server answers ranges, then
/// sixteen connections each fetching its own byte range and writing straight
/// into its place in a pre-allocated file. Big files are the whole point: the
/// guest image and the snapshot are gigabytes, and one TCP stream through a
/// busy CDN stalls -- sixteen means one stalled stream costs a sixteenth of
/// the file, not all of it, and a home connection is filled rather than
/// dribbled through.
///
/// A server that does not answer ranges falls back to one streamed download,
/// which is what the old code always did. Each chunk retries itself -- three
/// goes, resuming from where it stopped -- before the download fails.
final class HuskDownloader: NSObject, URLSessionDataDelegate {
    /// Parallel connections per download. Sixteen fills a home connection
    /// without drowning a phone's radio in packets it cannot schedule.
    static let threadCount = 16
    /// How many times a chunk retries itself before the download fails.
    private static let maxRetries = 3

    private let url: URL
    private let destination: URL
    private let onProgress: (Int64, Int64) -> Void
    private let onComplete: (Result<URL, Error>) -> Void

    /// One byte range of the file. A class, so the delegate can hold it across
    /// callbacks and the launcher can mutate it in place.
    private final class Chunk {
        let start: Int64
        let end: Int64 // inclusive; Int64.max for the streamed fallback, whose end is whatever the server sends
        var received: Int64 = 0
        var retries = 0
        var task: URLSessionDataTask?

        init(start: Int64, end: Int64) {
            self.start = start
            self.end = end
        }

        var complete: Bool { start + received > end }
    }

    private var chunks: [Chunk] = []
    private var total: Int64 = 0
    /// Every chunk writes through this one handle. URLSession calls its
    /// delegate on a serial queue, so the seeks and writes never overlap.
    private var handle: FileHandle?
    private var session: URLSession!
    private var stopped = false
    private var lastReport = Date.distantPast

    init(url: URL, destination: URL,
         progress: @escaping (Int64, Int64) -> Void,
         completion: @escaping (Result<URL, Error>) -> Void) {
        self.url = url
        self.destination = destination
        self.onProgress = progress
        self.onComplete = completion
        super.init()
    }

    func start() {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)

        // The size decides the chunking, and Accept-Ranges decides whether
        // chunking is possible at all. HEAD answers both in one round trip.
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        session.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async { self?.sized(response: response, error: error) }
        }.resume()
    }

    /// Stop everything and delete what was written. A cancelled download
    /// should not leave half a file behind it.
    func cancel() {
        guard !stopped else { return }
        stopped = true
        session?.invalidateAndCancel()
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: destination)
    }

    private func fail(_ message: String) {
        guard !stopped else { return }
        stopped = true
        session?.invalidateAndCancel()
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: destination)
        onComplete(.failure(NSError(domain: "husk", code: 20,
                                    userInfo: [NSLocalizedDescriptionKey: message])))
    }

    private func finish() {
        guard !stopped else { return }
        stopped = true
        try? handle?.close()
        handle = nil
        session.finishTasksAndInvalidate()
        onComplete(.success(destination))
    }

    // MARK: sizing

    private func sized(response: URLResponse?, error: Error?) {
        guard !stopped else { return }
        if let error {
            fail("could not reach \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            fail("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) from \(url.lastPathComponent)")
            return
        }
        // GitHub's release CDN answers both; a server that does not gets the
        // one-stream download the old code did.
        if http.expectedContentLength > 0,
           http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes" {
            total = http.expectedContentLength
            layOutChunks()
        } else {
            streamSingle()
        }
    }

    private func layOutChunks() {
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        handle = try? FileHandle(forWritingTo: destination)
        guard let handle else {
            fail("could not write \(destination.lastPathComponent)")
            return
        }
        // Pre-allocated, so the sixteen pieces write into real space instead of
        // each extending the file under the others.
        try? handle.truncate(atOffset: UInt64(total))

        let per = total / Int64(Self.threadCount)
        for i in 0..<Self.threadCount {
            let start = Int64(i) * per
            let end = i == Self.threadCount - 1 ? total - 1 : start + per - 1
            // A file smaller than the thread count has nothing for the later
            // chunks to fetch.
            guard start <= end else { break }
            let chunk = Chunk(start: start, end: end)
            chunks.append(chunk)
            launch(chunk)
        }
        HuskLog.log("guest", "downloading \(url.lastPathComponent) in \(chunks.count) chunks "
                           + "(\(total / (1024 * 1024)) MiB)")
    }

    /// The streamed fallback: one connection, written as it arrives. Its end
    /// is whatever the server sends, so the chunk never reports itself done
    /// before didComplete says so.
    private func streamSingle() {
        chunks.removeAll()
        let chunk = Chunk(start: 0, end: Int64.max)
        chunks.append(chunk)
        let task = session.dataTask(with: url)
        chunk.task = task
        task.resume()
    }

    private func launch(_ chunk: Chunk) {
        var req = URLRequest(url: url)
        // A retry resumes from where it stopped: the range starts at what the
        // chunk already has on disk.
        req.setValue("bytes=\(chunk.start + chunk.received)-\(chunk.end)",
                     forHTTPHeaderField: "Range")
        let task = session.dataTask(with: req)
        chunk.task = task
        task.resume()
    }

    private func chunk(for task: URLSessionTask) -> Chunk? {
        chunks.first { $0.task === task }
    }

    private func reportProgress(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) > 0.25 else { return }
        lastReport = now
        let received = chunks.reduce(0) { $0 + $1.received }
        onProgress(received, total)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // The streamed fallback learns its total from the response itself; the
        // chunked download already knows, and its ranges are not the file's size.
        if total == 0 { total = response.expectedContentLength }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !stopped, let chunk = chunk(for: dataTask) else { return }
        do {
            try handle?.seek(toOffset: UInt64(chunk.start + chunk.received))
            try handle?.write(contentsOf: data)
        } catch {
            fail("could not write \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        chunk.received += Int64(data.count)
        reportProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !stopped, let chunk = chunk(for: task) else { return }
        if let error = error as NSError?, error.code == NSURLErrorCancelled { return }

        if chunk.complete {
            reportProgress(force: true)
            if chunks.allSatisfy(\.complete) { finish() }
            return
        }
        // Short (the stream closed without an error) or failed: retry from
        // where it stopped, before giving up on the whole download.
        if chunk.retries < Self.maxRetries {
            chunk.retries += 1
            HuskLog.log("guest", "chunk retry \(chunk.retries)/\(Self.maxRetries) at "
                               + "\(chunk.start + chunk.received) of \(url.lastPathComponent)")
            launch(chunk)
        } else {
            fail("\(url.lastPathComponent): a chunk failed \(Self.maxRetries) times "
               + "(\(error?.localizedDescription ?? "short read"))")
        }
    }
}
