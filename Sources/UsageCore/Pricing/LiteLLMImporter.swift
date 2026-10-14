import Foundation

/// Provider imports from LiteLLM's public price list (FR-006 to FR-013,
/// contracts/litellm-mapping.md). The list is fetched only when the user
/// picks a provider import, never in the background (FR-034).
public struct LiteLLMImporter: Sendable {
    public static let defaultURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!

    /// Ephemeral, no cache, 30 seconds per request and in total (FR-012).
    public static let priceListSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    public let session: URLSession
    public let url: URL
    public let maxBytes: Int

    public init(session: URLSession = LiteLLMImporter.priceListSession, url: URL = LiteLLMImporter.defaultURL,
                maxBytes: Int = 20 * 1024 * 1024) {
        self.session = session
        self.url = url
        self.maxBytes = maxBytes
    }

    /// Downloads the price list, streaming so that the size cap holds even
    /// without a `Content-Length` header (FR-012).
    public func fetch() async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PriceImportError.network("the response is not an HTTP response")
            }
            guard http.statusCode == 200 else { throw PriceImportError.httpStatus(http.statusCode) }
            if http.expectedContentLength > Int64(maxBytes) { throw PriceImportError.tooLarge }
            var data = Data()
            if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw PriceImportError.tooLarge }
            }
            return data
        } catch let error as PriceImportError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut { throw PriceImportError.timeout }
            throw PriceImportError.network(error.localizedDescription)
        } catch {
            throw PriceImportError.network(String(describing: error))
        }
    }

    // MARK: Mapping

    private struct Selection {
        let providers: Set<String>
        let modes: Set<String>
        let prefix: String?
    }

    private static func selection(for kind: ImportKind) -> Selection? {
        switch kind {
        case .anthropic: return Selection(providers: ["anthropic"], modes: ["chat"], prefix: nil)
        case .openai: return Selection(providers: ["openai", "vertex_ai-openai_models"], modes: ["chat", "responses"], prefix: "vertex_ai/")
        case .gemini: return Selection(providers: ["gemini"], modes: ["chat"], prefix: "gemini/")
        case .csv: return nil
        }
    }

    /// Selects and converts the entries of one provider (FR-007 to FR-011,
    /// FR-013). Throws `notJSON` when the body is not a JSON object and
    /// `noUsableEntries` when nothing usable is left.
    public static func batch(from data: Data, kind: ImportKind, origin: String, importedAt: Date) throws -> PriceBatch {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            throw PriceImportError.notJSON
        }
        guard let selection = selection(for: kind) else { throw PriceImportError.noUsableEntries(kind) }

        // Candidates per canonical id: key after prefix stripping, date suffix, entry.
        var candidates: [String: [(key: String, date: String?, entry: PriceEntry)]] = [:]
        for key in root.keys.sorted() {
            guard let value = root[key] as? [String: Any],
                  let provider = value["litellm_provider"] as? String, selection.providers.contains(provider),
                  let mode = value["mode"] as? String, selection.modes.contains(mode) else { continue }
            var id = key
            if let prefix = selection.prefix, id.hasPrefix(prefix) { id = String(id.dropFirst(prefix.count)) }
            guard PriceTable.isAcceptableImportedModelId(id) else { continue }
            guard let input = perMillion(value["input_cost_per_token"]),
                  let output = perMillion(value["output_cost_per_token"]) else { continue }
            let cacheWrite5m = perMillion(value["cache_creation_input_token_cost"]) ?? input
            let cacheWrite1h = perMillion(value["cache_creation_input_token_cost_above_1hr"]) ?? input
            let cacheRead = perMillion(value["cache_read_input_token_cost"]) ?? input
            let prices = [input, output, cacheWrite5m, cacheWrite1h, cacheRead]
            guard prices.allSatisfy({ $0 >= 0 }) else { continue }
            let canonical = PriceTable.canonicalModel(id)
            guard !canonical.isEmpty else { continue }
            // Only an 8-digit snapshot suffix is a date; other variants
            // (`name@latest`) rank after the exact and dated keys.
            let suffix = id.suffix(8)
            let date: String? = canonical != id && suffix.count == 8 && suffix.allSatisfy(\.isNumber) ? String(suffix) : nil
            let entry = PriceEntry(model: canonical, inputPerMTok: input, outputPerMTok: output, cacheWrite5mPerMTok: cacheWrite5m,
                                   cacheWrite1hPerMTok: cacheWrite1h, cacheReadPerMTok: cacheRead)
            candidates[canonical, default: []].append((id, date, entry))
        }

        var entries: [PriceEntry] = []
        for canonical in candidates.keys.sorted() {
            let list = candidates[canonical]!
            // FR-011: equal prices give one entry; otherwise the undated key
            // wins, without one the latest date.
            let chosen = list.first { $0.key == canonical }
                ?? list.filter { $0.date != nil }.max { $0.date! < $1.date! }
                ?? list.min { $0.key < $1.key }!
            entries.append(chosen.entry)
        }
        guard !entries.isEmpty else { throw PriceImportError.noUsableEntries(kind) }
        return PriceBatch(kind: kind, origin: origin, importedAt: importedAt, entries: entries)
    }

    /// Dollars per token to dollars per million tokens, rounded to 6 decimal
    /// places (FR-008). Anything that is not a number counts as missing.
    static func perMillion(_ value: Any?) -> Decimal? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite else { return nil }
        var scaled = Decimal(double) * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 6, .plain)
        return rounded
    }
}
