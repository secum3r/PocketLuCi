import Foundation

enum NetworkError: LocalizedError {
    case notConfigured
    case authFailed(String)
    case rpcNotFound(String)
    case requestFailed(String)
    case decodingFailed
    case sessionExpired
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Router not configured. Go to Settings and enter the router IP."
        case .authFailed(let detail):
            return "Authentication failed.\n\nRouter replied:\n\(detail)"
        case .rpcNotFound(let url):
            return "LuCI RPC not found (404) at \(url)\n\nOn the router run:\nopkg update && opkg install luci-mod-rpc\nthen restart LuCI."
        case .requestFailed(let msg):
            return "Request failed: \(msg)"
        case .decodingFailed:
            return "Could not parse the router's response."
        case .sessionExpired:
            return "Session expired. Reconnect in Settings."
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        }
    }
}
