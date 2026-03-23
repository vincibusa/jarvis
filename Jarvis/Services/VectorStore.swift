import Foundation
import SQLite3
import Accelerate

// MARK: - Result type

struct ChunkResult: Sendable {
    let id: String
    let documentId: String
    let content: String
    let chunkIndex: Int
    let metadata: String
    let score: Float
}

struct MemoryResult: Sendable {
    let id: String
    let key: String
    let content: String
    let score: Float
}

// MARK: - SQLITE_TRANSIENT helper

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - VectorStore

final class VectorStore: @unchecked Sendable {

    private let dbPath: String
    private let lock = NSLock()

    // MARK: - Init

    init(path: URL) {
        self.dbPath = path.path
        createTableIfNeeded()
    }

    // MARK: - Private helpers

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            return nil
        }
        // Enable WAL mode for safe concurrent reads
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        return db
    }

    private func createTableIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE IF NOT EXISTS document_chunks (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            content TEXT NOT NULL,
            embedding BLOB NOT NULL,
            chunk_index INTEGER NOT NULL,
            metadata TEXT NOT NULL DEFAULT '{}'
        );
        CREATE INDEX IF NOT EXISTS idx_document_id ON document_chunks(document_id);
        CREATE TABLE IF NOT EXISTS memory_chunks (
            id TEXT PRIMARY KEY,
            key TEXT NOT NULL,
            content TEXT NOT NULL,
            embedding BLOB NOT NULL,
            created_at REAL NOT NULL DEFAULT (julianday('now'))
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Insert

    func insert(
        id: String,
        documentId: String,
        content: String,
        embedding: [Float],
        chunkIndex: Int,
        metadata: String = "{}"
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        let sql = """
        INSERT OR REPLACE INTO document_chunks
            (id, document_id, content, embedding, chunk_index, metadata)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        _ = id.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
        _ = documentId.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
        _ = content.withCString { sqlite3_bind_text(stmt, 3, $0, -1, SQLITE_TRANSIENT) }

        // Store embedding as raw bytes — SQLITE_TRANSIENT copies immediately
        _ = embedding.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(ptr.count), SQLITE_TRANSIENT)
        }

        sqlite3_bind_int(stmt, 5, Int32(chunkIndex))
        _ = metadata.withCString { sqlite3_bind_text(stmt, 6, $0, -1, SQLITE_TRANSIENT) }

        sqlite3_step(stmt)
    }

    // MARK: - Search

    func search(queryEmbedding: [Float], topK: Int) -> [ChunkResult] {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let sql = "SELECT id, document_id, content, embedding, chunk_index, metadata FROM document_chunks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        // Streaming top-K: keep only topK results in memory, never load all rows at once
        var topResults: [(ChunkResult, Float)] = []
        topResults.reserveCapacity(topK + 1)
        var minScore: Float = -.greatestFiniteMagnitude

        while sqlite3_step(stmt) == SQLITE_ROW {
            // Compute similarity directly on the blob pointer — no copy into [Float]
            let blobBytes = sqlite3_column_bytes(stmt, 3)
            guard let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }
            let floatCount = Int(blobBytes) / MemoryLayout<Float>.size
            let score = cosineSimilarityRaw(queryEmbedding, blobPtr, floatCount)

            // Early-exit: skip row if it can't displace any current top-K entry
            guard topResults.count < topK || score > minScore else { continue }

            let id = String(cString: sqlite3_column_text(stmt, 0))
            let documentId = String(cString: sqlite3_column_text(stmt, 1))
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let chunkIndex = Int(sqlite3_column_int(stmt, 4))
            let metadata = String(cString: sqlite3_column_text(stmt, 5))

            let result = ChunkResult(id: id, documentId: documentId, content: content,
                                     chunkIndex: chunkIndex, metadata: metadata, score: score)
            topResults.append((result, score))

            if topResults.count > topK {
                topResults.sort { $0.1 > $1.1 }
                topResults.removeLast()
                minScore = topResults.last?.1 ?? -.greatestFiniteMagnitude
            }
        }

        topResults.sort { $0.1 > $1.1 }
        return topResults.map { $0.0 }
    }

    // MARK: - Delete

    func deleteByDocument(id documentId: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        let sql = "DELETE FROM document_chunks WHERE document_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        _ = documentId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_step(stmt)
    }

    // MARK: - List

    func listDocumentIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let sql = "SELECT DISTINCT document_id FROM document_chunks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return ids
    }

    func chunkCount() -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return 0 }
        defer { sqlite3_close(db) }

        let sql = "SELECT COUNT(*) FROM document_chunks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    // MARK: - Memory insert/search/delete

    func insertMemory(id: String, key: String, content: String, embedding: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        let sql = "INSERT OR REPLACE INTO memory_chunks (id, key, content, embedding) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        _ = id.withCString      { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
        _ = key.withCString     { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
        _ = content.withCString { sqlite3_bind_text(stmt, 3, $0, -1, SQLITE_TRANSIENT) }
        _ = embedding.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(ptr.count), SQLITE_TRANSIENT)
        }
        sqlite3_step(stmt)
    }

    func searchMemory(queryEmbedding: [Float], topK: Int) -> [MemoryResult] {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        let sql = "SELECT id, key, content, embedding FROM memory_chunks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        // Streaming top-K: never load all rows into memory simultaneously
        var topResults: [(MemoryResult, Float)] = []
        topResults.reserveCapacity(topK + 1)
        var minScore: Float = -.greatestFiniteMagnitude

        while sqlite3_step(stmt) == SQLITE_ROW {
            let blobBytes = sqlite3_column_bytes(stmt, 3)
            guard let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }
            let floatCount = Int(blobBytes) / MemoryLayout<Float>.size
            let score = cosineSimilarityRaw(queryEmbedding, blobPtr, floatCount)

            guard topResults.count < topK || score > minScore else { continue }

            let id      = String(cString: sqlite3_column_text(stmt, 0))
            let key     = String(cString: sqlite3_column_text(stmt, 1))
            let content = String(cString: sqlite3_column_text(stmt, 2))

            topResults.append((MemoryResult(id: id, key: key, content: content, score: score), score))

            if topResults.count > topK {
                topResults.sort { $0.1 > $1.1 }
                topResults.removeLast()
                minScore = topResults.last?.1 ?? -.greatestFiniteMagnitude
            }
        }

        topResults.sort { $0.1 > $1.1 }
        return topResults.map { $0.0 }
    }

    func deleteMemory(id: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }

        let sql = "DELETE FROM memory_chunks WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        _ = id.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_step(stmt)
    }

    func deleteAllMemory() {
        lock.lock()
        defer { lock.unlock() }

        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "DELETE FROM memory_chunks;", nil, nil, nil)
    }

    // MARK: - Cosine similarity

    /// Compute cosine similarity directly against a raw blob pointer — avoids copying into [Float].
    private func cosineSimilarityRaw(_ a: [Float], _ blobPtr: UnsafeRawPointer, _ bCount: Int) -> Float {
        guard a.count == bCount, bCount > 0 else { return 0 }
        let b = blobPtr.assumingMemoryBound(to: Float.self)
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        let count = vDSP_Length(bCount)
        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)
        vDSP_svesq(a, 1, &normA, count)
        vDSP_svesq(b, 1, &normB, count)
        let denom = sqrtf(normA) * sqrtf(normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        let count = vDSP_Length(a.count)

        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)
        vDSP_svesq(a, 1, &normA, count)
        vDSP_svesq(b, 1, &normB, count)

        let denominator = sqrtf(normA) * sqrtf(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }
}
