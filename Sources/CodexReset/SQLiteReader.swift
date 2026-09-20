import Foundation
import SQLite3

/// SQLite 的 SQLITE_TRANSIENT 是 C 宏，Swift 里需手动定义
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 从本地 sqlite 定位「因用量用光而暂停」的对话
struct PausedThread {
    let threadId: String
    let title: String
    let cwd: String
    /// 错误消息里的恢复提示原文，如 "try again at 1:17 PM"
    let recoveryHint: String?
    /// 该失败轮次时间（Unix 秒）
    let failedAt: Int
    /// 该失败轮次是否仍是对话的最后一轮。
    /// false 表示失败之后对话已被继续过，不再处于暂停（旧版本会把这类对话误报为暂停）。
    var isStillPaused: Bool = false
    /// 该对话最后一条用户消息的开头，用作副标题（标题常被自动「继续」覆盖，看不出在做什么）
    var lastUserMessage: String? = nil
}

final class SQLiteReader {
    let codexHome: String

    init(codexHome: String) {
        self.codexHome = codexHome
    }

    private var threadHistoryPath: String { codexHome + "/thread_history_1.sqlite" }
    private var stateDbPath: String { codexHome + "/state_5.sqlite" }

    /// 找出所有因用量上限(usageLimitExceeded)失败暂停的线程（每线程取最新一次失败）。
    /// thread_turns 中 turn_id 为 ULID，按 turn_id 倒序即按时间倒序。
    func usageLimitedThreads(limit: Int = 20) -> [PausedThread] {
        guard let rows = queryRows(
            path: threadHistoryPath,
            sql: """
            SELECT t.thread_id, t.error_json, t.started_at,
                   CASE WHEN t.rollout_ordinal = a.last_ordinal THEN 1 ELSE 0 END AS is_still_paused
            FROM thread_turns t
            JOIN (
                SELECT thread_id, MAX(turn_id) AS max_turn
                FROM thread_turns
                WHERE status = 'failed' AND error_json LIKE '%usageLimitExceeded%'
                GROUP BY thread_id
            ) m ON t.thread_id = m.thread_id AND t.turn_id = m.max_turn
            JOIN (
                SELECT thread_id, MAX(rollout_ordinal) AS last_ordinal
                FROM thread_turns
                GROUP BY thread_id
            ) a ON a.thread_id = t.thread_id
            ORDER BY t.turn_id DESC
            LIMIT ?
            """,
            args: [limit]
        ) else { return [] }

        let bounds = userMessageBounds()
        var result: [PausedThread] = []
        for row in rows {
            let threadId = row[0] as? String ?? ""
            let errorJson = row[1] as? String ?? ""
            let failedAt = row[2] as? Int ?? 0
            let isStillPaused = (row[3] as? Int ?? 0) == 1
            guard !threadId.isEmpty else { continue }
            // 过滤子代理线程（主对话派生的 subagent，非用户独立对话，无需单独继续）
            if isSubagentThread(threadId: threadId) { continue }
            let entry = bounds[threadId]
            let title = displayTitle(stateTitle: threadTitle(threadId: threadId), messages: entry)
            let cwd = threadCwd(threadId: threadId) ?? ""
            let hint = Self.extractRecoveryHint(from: errorJson)
            result.append(PausedThread(threadId: threadId, title: title, cwd: cwd,
                                       recoveryHint: hint, failedAt: failedAt,
                                       isStillPaused: isStillPaused,
                                       lastUserMessage: entry?.last))
        }
        return result
    }

    /// 列出所有对话（含未暂停的），按项目分组用；过滤归档与子代理线程，最新在前
    func allThreads(limit: Int = 1000) -> [PausedThread] {
        guard let rows = queryRows(path: stateDbPath, sql: """
            SELECT id, title, cwd, updated_at
            FROM threads
            WHERE archived = 0 AND source NOT LIKE '{"subagent"%'
            ORDER BY updated_at_ms DESC
            LIMIT ?
        """, args: [limit]) else { return [] }

        let bounds = userMessageBounds()
        var result: [PausedThread] = []
        for row in rows {
            let threadId = row[0] as? String ?? ""
            let rawTitle = row[1] as? String
            let cwd = row[2] as? String ?? ""
            let updatedAt = row[3] as? Int ?? 0
            guard !threadId.isEmpty else { continue }
            let entry = bounds[threadId]
            let title = displayTitle(stateTitle: rawTitle, messages: entry)
            result.append(PausedThread(threadId: threadId, title: title, cwd: cwd,
                                       recoveryHint: nil, failedAt: updatedAt,
                                       isStillPaused: false,
                                       lastUserMessage: entry?.last))
        }
        return result
    }

    /// 每个线程的首条 / 末条 userMessage，一次查询取全部（逐条查会打开上百次库）。
    func userMessageBounds() -> [String: (first: String?, last: String?)] {
        guard let rows = queryRows(path: threadHistoryPath, sql: """
            SELECT i.thread_id, i.item_json,
                   CASE WHEN i.rollout_ordinal = m.first_ord THEN 1 ELSE 0 END AS is_first
            FROM thread_items i
            JOIN (
                SELECT thread_id,
                       MIN(rollout_ordinal) AS first_ord,
                       MAX(rollout_ordinal) AS last_ord
                FROM thread_items
                WHERE item_type = 'userMessage'
                GROUP BY thread_id
            ) m ON m.thread_id = i.thread_id
             AND i.rollout_ordinal IN (m.first_ord, m.last_ord)
            WHERE i.item_type = 'userMessage'
        """) else { return [:] }

        var result: [String: (first: String?, last: String?)] = [:]
        for row in rows {
            guard let threadId = row[0] as? String, !threadId.isEmpty,
                  let json = row[1] as? String else { continue }
            let text = Self.extractText(fromItemJSON: json)
            var entry = result[threadId] ?? (first: nil, last: nil)
            if (row[2] as? Int ?? 0) == 1 {
                entry.first = text
            } else {
                entry.last = text
            }
            result[threadId] = entry
        }
        return result
    }

    /// 从 thread_items.item_json 里取出用户消息正文，只保留前 500 字
    static func extractText(fromItemJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { return nil }
        let raw = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return meaningfulText(raw)
    }

    /// Codex 会在用户消息前拼接上下文块（`# Files mentioned by the user:` + `## 文件: 路径`）。
    /// 直接展示这段的话每条都长得一样，所以跳到真正的正文。
    static func meaningfulText(_ raw: String) -> String? {
        let lines = raw.components(separatedBy: "\n")
        var index = 0
        var attachments = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }
            guard line.hasPrefix("#") else { break }
            if line.hasPrefix("##") { attachments += 1 }
            index += 1
        }
        let body = lines[index...]
            .joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { return String(body.prefix(500)) }
        if attachments > 0 {
            return L("附带 \(attachments) 个文件", "\(attachments) file(s) attached")
        }
        let fallback = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : String(fallback.prefix(500))
    }

    /// 判断是否为子代理线程    /// 判断是否为子代理线程（state 库 source 以 {"subagent" 开头）
    private func isSubagentThread(threadId: String) -> Bool {
        guard let source = threadSource(threadId: threadId) else { return false }
        return source.trimmingCharacters(in: .whitespaces).hasPrefix(#"{"subagent""#)
    }

    private func threadSource(threadId: String) -> String? {
        queryRow(path: stateDbPath,
                 sql: "SELECT source FROM threads WHERE id = ?",
                 args: [threadId])?[0] as? String
    }

    /// 显示用标题。
    /// Codex 会把对话标题同步成最新一条用户消息，所以 state 里的标题常常就是副标题那句话。
    /// 遇到这种情况回退到首条消息（最初的任务），标题和副标题才各说各的。
    private func displayTitle(stateTitle: String?,
                              messages: (first: String?, last: String?)?) -> String {
        let fallback = messages?.first ?? messages?.last
        guard let stateTitle, stateTitle.count >= 3 else {
            return trimTitle(fallback) ?? L("未命名对话", "Untitled chat")
        }
        // 标题只是末条消息的开头 → 换成首条消息
        if let last = messages?.last, last.hasPrefix(String(stateTitle.prefix(24))) {
            if let first = messages?.first, !first.hasPrefix(String(stateTitle.prefix(24))) {
                return trimTitle(first) ?? stateTitle
            }
        }
        return stateTitle
    }

    /// 消息正文当标题时截断到一行长度
    private func trimTitle(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(60))
    }

    private func threadTitle(threadId: String) -> String? {
        queryRow(path: stateDbPath,
                 sql: "SELECT title FROM threads WHERE id = ?",
                 args: [threadId])?[0] as? String
    }

    private func threadCwd(threadId: String) -> String? {
        queryRow(path: stateDbPath,
                 sql: "SELECT cwd FROM threads WHERE id = ?",
                 args: [threadId])?[0] as? String
    }

    /// 从错误 JSON 中提取 "try again at ..." 恢复提示
    static func extractRecoveryHint(from errorJson: String) -> String? {
        guard let data = errorJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? String else {
            return nil
        }
        if let range = message.range(of: "try again at ") {
            return String(message[range.upperBound...])
        }
        return nil
    }

    // MARK: - 通用查询

    private func queryRow(path: String, sql: String, args: [Any] = []) -> [Any?]? {
        queryRows(path: path, sql: sql, args: args)?.first
    }

    /// 多行查询
    private func queryRows(path: String, sql: String, args: [Any] = []) -> [[Any?]]? {
        guard let db = open(path) else {
            #if DEBUG
            FileHandle.standardError.write("[SQLITE-OPEN-FAIL] \(path)\n".data(using: .utf8)!)
            #endif
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            #if DEBUG
            let err = sqlite3_errmsg(db).flatMap { String(cString: $0) } ?? "?"
            FileHandle.standardError.write("[SQLITE-PREPARE-FAIL] \(err)\n".data(using: .utf8)!)
            #endif
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            if let s = arg as? String {
                sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            } else if let n = arg as? Int {
                sqlite3_bind_int64(stmt, idx, Int64(n))
            }
        }

        let count = sqlite3_column_count(stmt)
        var rows: [[Any?]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var row: [Any?] = []
                for i in 0..<count {
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER:
                        row.append(Int(sqlite3_column_int64(stmt, i)))
                    case SQLITE_TEXT:
                        if let c = sqlite3_column_text(stmt, i) {
                            row.append(String(cString: c))
                        } else {
                            row.append(nil)
                        }
                    case SQLITE_NULL:
                        row.append(nil)
                    case SQLITE_FLOAT:
                        row.append(sqlite3_column_double(stmt, i))
                    default:
                        if let c = sqlite3_column_text(stmt, i) {
                            row.append(String(cString: c))
                        } else {
                            row.append(nil)
                        }
                    }
                }
                rows.append(row)
            } else if rc == SQLITE_DONE {
                break
            } else {
                #if DEBUG
                let err = sqlite3_errmsg(db).flatMap { String(cString: $0) } ?? "rc=\(rc)"
                FileHandle.standardError.write("[SQLITE-STEP-FAIL] \(err)\n".data(using: .utf8)!)
                #endif
                return nil
            }
        }
        return rows
    }

    private func open(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        // 用 READWRITE 而非 READONLY：WAL 模式数据库在并发写时 readonly 打开可能失败
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
        guard rc == SQLITE_OK else {
            let msg = (db.flatMap { sqlite3_errmsg($0) }).flatMap { String(cString: $0) } ?? "rc=\(rc)"
            #if DEBUG
            FileHandle.standardError.write("[SQLITE-OPEN-ERR] \(path): \(msg)\n".data(using: .utf8)!)
            #endif
            if let db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 5000)
        return db
    }
}

// MARK: - config.toml 读取

/// 读取 ~/.codex/config.toml 中的相关配置
struct CodexConfig {
    let remoteControlEnabled: Bool

    static func load(codexHome: String) -> CodexConfig {
        let path = codexHome + "/config.toml"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return CodexConfig(remoteControlEnabled: false)
        }
        var remoteControl = false
        var inFeatures = false
        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inFeatures = (line == "[features]")
                continue
            }
            if inFeatures && line.hasPrefix("remote_control") {
                remoteControl = line.lowercased().contains("true")
            }
        }
        return CodexConfig(remoteControlEnabled: remoteControl)
    }

    /// 写入 [features] remote_control = true/false（保留原有内容；需重启 Codex 桌面 app 生效）
    /// 注意：必须复用已有的 [features] 段，不能重复定义，否则 TOML 报 duplicate key
    @discardableResult
    static func setRemoteControl(codexHome: String, enabled: Bool) -> Bool {
        let path = codexHome + "/config.toml"
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        var lines = content.components(separatedBy: "\n")
        let value = enabled ? "true" : "false"

        // 找到所有段标题行（以 [ 开头 ] 结尾）
        let sectionIndices = lines.indices.filter {
            let t = lines[$0].trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[") && t.hasSuffix("]")
        }
        // 定位 [features] 段
        var featuresStart: Int?
        for idx in sectionIndices where lines[idx].trimmingCharacters(in: .whitespaces) == "[features]" {
            featuresStart = idx
            break
        }

        var modified = false
        if let start = featuresStart {
            // 段范围：start ..< 下一个段标题（或文件末尾）
            let end = sectionIndices.first(where: { $0 > start }) ?? lines.count
            var inserted = false
            for i in start..<end {
                if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("remote_control") {
                    lines[i] = "remote_control = \(value)"
                    inserted = true
                    modified = true
                    break
                }
            }
            if !inserted {
                // 在段内末尾插入
                lines.insert("remote_control = \(value)", at: end)
                modified = true
            }
        } else {
            // 完全没有 [features] 段才追加新段
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            lines.append("")
            lines.append("[features]")
            lines.append("remote_control = \(value)")
            modified = true
        }

        guard modified else { return true }
        do {
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
