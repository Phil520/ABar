import Foundation

/// 行情抓取。腾讯为主、新浪为备；两条都不通才报错。
final class QuoteService {

    enum FetchError: LocalizedError {
        case noData
        case http(Int)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .noData: return "接口返回空数据"
            case .http(let code): return "HTTP \(code)"
            case .network(let msg): return msg
            }
        }
    }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: cfg)
    }()

    /// GBK 解码：腾讯返回的是 GB18030，用 UTF-8 硬解会把中文变成替换符。
    /// 数值字段是 ASCII 本来不受影响，但留着干净的名字字段有利于以后扩展。
    private static let gbk: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }()

    func fetch(completion: @escaping (Result<Quote, Error>) -> Void) {
        fetchTencent { [weak self] result in
            switch result {
            case .success(let q):
                completion(.success(q))
            case .failure(let firstError):
                guard let self = self else { return }
                self.fetchSina { sinaResult in
                    switch sinaResult {
                    case .success(let q): completion(.success(q))
                    case .failure: completion(.failure(firstError))
                    }
                }
            }
        }
    }

    // MARK: - 腾讯

    private func fetchTencent(completion: @escaping (Result<Quote, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://qt.gtimg.cn/q=sh000001")!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        perform(req) { data in
            let text = String(data: data, encoding: QuoteService.gbk)
                ?? String(decoding: data, as: UTF8.self)
            if let q = QuoteParser.parseTencent(text) { return q }
            return nil
        } completion: { completion($0) }
    }

    // MARK: - 新浪

    private func fetchSina(completion: @escaping (Result<Quote, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://hq.sinajs.cn/list=s_sh000001")!)
        // 新浪对 Referer 有硬要求，缺了直接 403
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        perform(req) { data in
            let text = String(data: data, encoding: QuoteService.gbk)
                ?? String(decoding: data, as: UTF8.self)
            return QuoteParser.parseSina(text)
        } completion: { completion($0) }
    }

    // MARK: - 公共

    private func perform(_ request: URLRequest,
                         parse: @escaping (Data) -> Quote?,
                         completion: @escaping (Result<Quote, Error>) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(FetchError.network(error.localizedDescription)))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(FetchError.http(http.statusCode)))
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(FetchError.noData))
                return
            }
            if let quote = parse(data) {
                completion(.success(quote))
            } else {
                completion(.failure(FetchError.noData))
            }
        }
        task.resume()
    }
}
