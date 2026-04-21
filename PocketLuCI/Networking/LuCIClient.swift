import Foundation

// MARK: - Ubus request format

private struct UbusBody: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method = "call"
    let params: UbusParams
}

private struct UbusParams: Encodable {
    let session: String
    let object: String
    let callMethod: String
    let args: [String: String]

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(session)
        try c.encode(object)
        try c.encode(callMethod)
        try c.encode(args)
    }
}

// MARK: - Ubus response format

private struct UbusResponse<T: Decodable>: Decodable {
    let id: Int?
    let result: UbusTuple<T>?
    let error: UbusRPCError?
}

private struct UbusTuple<T: Decodable>: Decodable {
    let code: Int
    let data: T?

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        code = try c.decode(Int.self)
        data = try? c.decode(T.self)
    }
}

private struct UbusRPCError: Decodable {
    let code: Int?
    let message: String?
}

// MARK: - Specific result payloads

private struct SessionData: Decodable { let ubus_rpc_session: String? }
private struct ExecData: Decodable { let stdout: String? }
private struct UCIAddData: Decodable { let section: String? }
private struct UCIGetData: Decodable { let values: [String: UCISection]? }
private struct EmptyData: Decodable {}

// MARK: - LuCI classic RPC (fallback for rpc-sys ACL issues)

private struct LuCIAuthBody: Encodable {
    let id = 1
    let method = "getToken"
    let params: Params
    struct Params: Encodable { let username, password: String }
}
private struct LuCIAuthResponse: Decodable { let result: String? }
private struct LuCIRPCRequest: Encodable {
    let id = 1
    let method: String
    let params: [String]
}
private struct LuCIRPCResponse<T: Decodable>: Decodable { let result: T? }
private struct LuCIARPEntry: Decodable { let ip: String?; let mac: String? }

// network.get_host_hints response (netifd — always present)
private struct HostHint: Decodable {
    let macaddr: String?
    let mac: String?
    let name: String?
    let hostname: String?
    let ipaddr: String?
    let ip: String?
    var resolvedMAC: String? { macaddr ?? mac }
    var resolvedName: String? {
        let n = name ?? hostname
        return (n?.isEmpty == false && n != "*") ? n : nil
    }
    var resolvedIP: String? { ipaddr ?? ip }
}

// dhcp.ipv4leases response (odhcpd)
private struct IPv4LeaseEntry: Decodable { let mac: String?; let ip: String?; let hostname: String? }
private struct IPv4Bridge: Decodable { let leases: [IPv4LeaseEntry]? }
private struct IPv4LeasesData: Decodable { let device: [String: IPv4Bridge]? }

// MARK: - Public domain types

struct ARPEntry {
    let ip: String
    let mac: String
}

struct DHCPLease {
    let mac: String
    let ip: String
    let hostname: String?
}

struct UCISection: Decodable {
    let type: String?
    let options: [String: String]

    private struct DynKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynKey.self)
        type = try container.decodeIfPresent(String.self, forKey: DynKey(stringValue: ".type")!)
        var opts = [String: String]()
        for key in container.allKeys where !key.stringValue.hasPrefix(".") {
            if let val = try? container.decode(String.self, forKey: key) {
                opts[key.stringValue] = val
            }
        }
        options = opts
    }
}

// MARK: - LuCI Client (ubus rpcd API)

@MainActor
final class LuCIClient {
    static let shared = LuCIClient()

    private var host: String = ""
    private var useHTTPS: Bool = false
    private var authToken: String?
    private var luciToken: String?
    private var storedUsername: String?
    private var storedPassword: String?
    private var sysauthCookie: String?
    private var sysauthStok: String?
    private var aclSetupAttempted = false
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config, delegate: TrustAllDelegate(), delegateQueue: nil)
    }

    func configure(host: String, useHTTPS: Bool = false) {
        self.host = host
        self.useHTTPS = useHTTPS
        self.authToken = nil
        self.luciToken = nil
        self.sysauthCookie = nil
        self.sysauthStok = nil
        self.aclSetupAttempted = false
    }

    var isAuthenticated: Bool { authToken != nil }

    // MARK: Auth

    func authenticate(username: String, password: String) async throws {
        guard !host.isEmpty else { throw NetworkError.notConfigured }
        let scheme = useHTTPS ? "https" : "http"
        let urlStr = "\(scheme)://\(host)/ubus"
        guard let url = URL(string: urlStr) else {
            throw NetworkError.requestFailed("Invalid URL: \(urlStr)")
        }

        let body = UbusBody(params: UbusParams(
            session: "00000000000000000000000000000000",
            object: "session",
            callMethod: "login",
            args: ["username": username, "password": password]
        ))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: req)
        let rawReply = String(data: data, encoding: .utf8) ?? "(binary \(data.count) bytes)"

        if let http = response as? HTTPURLResponse {
            if (http.statusCode == 307 || http.statusCode == 308) && !useHTTPS,
               let location = http.value(forHTTPHeaderField: "Location"),
               location.hasPrefix("https://") {
                useHTTPS = true
                return try await authenticate(username: username, password: password)
            }
            if http.statusCode == 404 { throw NetworkError.rpcNotFound(urlStr) }
            if http.statusCode != 200 { throw NetworkError.requestFailed("HTTP \(http.statusCode)") }
        }

        guard let resp = try? JSONDecoder().decode(UbusResponse<SessionData>.self, from: data),
              resp.result?.code == 0,
              let token = resp.result?.data?.ubus_rpc_session,
              !token.isEmpty,
              token != "00000000000000000000000000000000" else {
            throw NetworkError.authFailed(String(rawReply.prefix(300)))
        }
        authToken = token
        storedUsername = username
        storedPassword = password
        await tryLuCIRPCAuth(username: username, password: password)
        await luciWebLogin(username: username, password: password)
        if !aclSetupAttempted {
            aclSetupAttempted = true
            await ensureACLIfNeeded()
        }
    }

    func invalidateSession() {
        authToken = nil
        luciToken = nil
        sysauthCookie = nil
        sysauthStok = nil
    }

    // MARK: Devices

    func getDevices() async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        var attempts: [String] = []

        // 1. luci-rpc.getHostHints — indexed by MAC, includes hostname (OpenWrt 25+)
        do {
            let r = try await getDevicesViaLuCIRpcHostHints()
            if !r.arp.isEmpty { return r }
            attempts.append("luci-rpc.getHostHints: empty")
        } catch { attempts.append("luci-rpc.getHostHints: \(error.localizedDescription)") }

        // 2. file.read /proc/net/arp + /tmp/dhcp.leases
        do {
            let r = try await getDevicesViaFileRead()
            if !r.arp.isEmpty { return r }
            attempts.append("file.read: empty")
        } catch { attempts.append("file.read: \(error.localizedDescription)") }

        // 3. network.get_host_hints (older OpenWrt)
        do {
            let r = try await getDevicesViaHostHints()
            if !r.arp.isEmpty { return r }
            attempts.append("host_hints: empty")
        } catch { attempts.append("host_hints: \(error.localizedDescription)") }

        // 4. dhcp.ipv4leases (odhcpd)
        do {
            let r = try await getDevicesViaIPv4Leases()
            if !r.arp.isEmpty { return r }
            attempts.append("ipv4leases: empty")
        } catch { attempts.append("ipv4leases: \(error.localizedDescription)") }

        // 5. LuCI proxy fallback
        let webLoginAvail = sysauthCookie != nil && sysauthStok != nil ? "yes" : "no"
        do {
            let r = try await getDevicesViaLuCIProxy()
            if !r.arp.isEmpty { return r }
            attempts.append("luci-proxy(weblogin=\(webLoginAvail)): empty")
        } catch { attempts.append("luci-proxy(weblogin=\(webLoginAvail)): \(error.localizedDescription)") }

        throw NetworkError.operationFailed("No device data. Tried: \(attempts.joined(separator: " | "))")
    }

    private func getDevicesViaLuCIRpcHostHints() async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        let raw = try await ubusCallRaw(object: "luci-rpc", method: "getHostHints", params: [:] as [String: String])
        guard let hints = raw as? [String: Any] else {
            throw NetworkError.operationFailed("luci-rpc.getHostHints: unexpected type")
        }
        var arp: [ARPEntry] = []; var dhcp: [DHCPLease] = []
        for (macKey, hintVal) in hints {
            guard let hint = hintVal as? [String: Any] else { continue }
            let mac = macKey.lowercased()
            guard mac.contains(":"), mac != "00:00:00:00:00:00", mac != "ff:ff:ff:ff:ff:ff" else { continue }
            let ipaddrs = hint["ipaddrs"] as? [String] ?? []
            guard let ip = ipaddrs.first(where: { $0.contains(".") }) else { continue }
            let name = hint["name"] as? String
            arp.append(ARPEntry(ip: ip, mac: mac))
            dhcp.append(DHCPLease(mac: mac, ip: ip, hostname: (name?.isEmpty == false && name != "*") ? name : nil))
        }
        if arp.isEmpty { throw NetworkError.operationFailed("luci-rpc.getHostHints: 0 entries from \(hints.count)") }
        return (arp, dhcp)
    }

    private func getDevicesViaHostHints() async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        let raw = try await ubusCallRaw(object: "network", method: "get_host_hints", params: [:] as [String: String])
        guard let hints = raw as? [String: Any] else {
            throw NetworkError.operationFailed("host_hints: unexpected type \(type(of: raw))")
        }
        var arp: [ARPEntry] = []; var dhcp: [DHCPLease] = []
        for (ipKey, hintVal) in hints {
            guard let hint = hintVal as? [String: Any] else { continue }
            let mac = hint["macaddr"] as? String ?? hint["mac"] as? String ?? hint["mac_addr"] as? String
            guard let m = mac, m.contains(":"), m.lowercased() != "00:00:00:00:00:00" else { continue }
            let ip = ipKey.contains(".") ? ipKey : (hint["ipaddr"] as? String ?? hint["ip"] as? String ?? ipKey)
            guard ip.contains(".") else { continue }
            let name = hint["name"] as? String ?? hint["hostname"] as? String
            let low = m.lowercased()
            arp.append(ARPEntry(ip: ip, mac: low))
            dhcp.append(DHCPLease(mac: low, ip: ip, hostname: (name?.isEmpty == false && name != "*") ? name : nil))
        }
        if arp.isEmpty { throw NetworkError.operationFailed("host_hints: 0 valid entries from \(hints.count)") }
        return (arp, dhcp)
    }

    private func getDevicesViaIPv4Leases() async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        let raw = try await ubusCallRaw(object: "dhcp", method: "ipv4leases", params: [:] as [String: String])
        guard let result = raw as? [String: Any],
              let deviceMap = result["device"] as? [String: Any] else {
            throw NetworkError.operationFailed("ipv4leases: unexpected response")
        }
        var arp: [ARPEntry] = []; var dhcp: [DHCPLease] = []
        for (_, val) in deviceMap {
            guard let bridge = val as? [String: Any],
                  let leases = bridge["leases"] as? [[String: Any]] else { continue }
            for lease in leases {
                guard let mac = lease["mac"] as? String, let ip = lease["ip"] as? String,
                      mac.contains(":"), ip.contains(".") else { continue }
                let low = mac.lowercased(); let h = lease["hostname"] as? String
                arp.append(ARPEntry(ip: ip, mac: low))
                dhcp.append(DHCPLease(mac: low, ip: ip, hostname: (h?.isEmpty == false && h != "*") ? h : nil))
            }
        }
        if arp.isEmpty { throw NetworkError.operationFailed("ipv4leases: 0 entries") }
        return (arp, dhcp)
    }

    private func getDevicesViaExec(service: String) async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        let arpRaw = try await ubusExecString(service: service, command: "cat /proc/net/arp")
        guard !arpRaw.isEmpty else { throw NetworkError.operationFailed("\(service).exec: empty") }
        let dhcpRaw = (try? await ubusExecString(service: service, command: "cat /tmp/dhcp.leases")) ?? ""
        return (parseARPTable(arpRaw), parseDHCPLeases(dhcpRaw))
    }

    private func getDevicesViaFileRead() async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        async let arpTask = ubusFileRead(path: "/proc/net/arp")
        async let dhcpTask = ubusFileRead(path: "/tmp/dhcp.leases")
        let arpRaw = (try? await arpTask) ?? ""
        let dhcpRaw = (try? await dhcpTask) ?? ""
        let arp = parseARPTable(arpRaw)
        if arp.isEmpty { throw NetworkError.operationFailed("file.read: empty") }
        return (arp, parseDHCPLeases(dhcpRaw))
    }

    private func getDevicesViaLuCIProxy() async throws -> (arp: [ARPEntry], dhcp: [DHCPLease]) {
        // Prefer the web-login sysauth session; fall back to ubus token as last resort
        let cookie: String
        let stok: String
        if let c = sysauthCookie, let s = sysauthStok, !c.isEmpty, !s.isEmpty {
            cookie = c
            stok = s
        } else if let token = authToken {
            cookie = token
            stok = ""
        } else {
            throw NetworkError.sessionExpired
        }

        let scheme = useHTTPS ? "https" : "http"
        let stokSegment = stok.isEmpty ? "" : ";stok=\(stok)"
        guard let proxyURL = URL(string: "\(scheme)://\(host)/cgi-bin/luci/\(stokSegment)/admin/ubus") else {
            throw NetworkError.requestFailed("Invalid proxy URL")
        }

        func proxyCall(service: String, method: String) async throws -> [String: Any] {
            var req = URLRequest(url: proxyURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("sysauth_http=\(cookie); sysauth_https=\(cookie); sysauth=\(cookie)",
                         forHTTPHeaderField: "Cookie")
            // The sysauth cookie value IS the LuCI ubus session token — use it as params[0]
            let rpcToken = cookie
            let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "call",
                                       "params": [rpcToken, service, method, [:] as [String: String]]]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await urlSession.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                throw NetworkError.requestFailed("LuCI proxy 403")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [Any], result.count >= 2,
                  let code = result[0] as? Int, code == 0,
                  let dict = result[1] as? [String: Any] else {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                throw NetworkError.operationFailed("luci-proxy \(service).\(method): \(preview)")
            }
            return dict
        }

        // Try dhcp.ipv4leases via proxy
        if let result = try? await proxyCall(service: "dhcp", method: "ipv4leases"),
           let deviceMap = result["device"] as? [String: Any] {
            var arp: [ARPEntry] = []; var dhcp: [DHCPLease] = []
            for (_, val) in deviceMap {
                guard let bridge = val as? [String: Any],
                      let leases = bridge["leases"] as? [[String: Any]] else { continue }
                for lease in leases {
                    guard let mac = lease["mac"] as? String, let ip = lease["ip"] as? String,
                          mac.contains(":"), ip.contains(".") else { continue }
                    let low = mac.lowercased(); let h = lease["hostname"] as? String
                    arp.append(ARPEntry(ip: ip, mac: low))
                    dhcp.append(DHCPLease(mac: low, ip: ip, hostname: (h?.isEmpty == false && h != "*") ? h : nil))
                }
            }
            if !arp.isEmpty { return (arp, dhcp) }
        }

        // Try network.get_host_hints via proxy
        let hints = try await proxyCall(service: "network", method: "get_host_hints")
        var arp: [ARPEntry] = []; var dhcp: [DHCPLease] = []
        for (ipKey, hintVal) in hints {
            guard let hint = hintVal as? [String: Any] else { continue }
            let mac = hint["macaddr"] as? String ?? hint["mac"] as? String
            guard let m = mac, m.contains(":"), m.lowercased() != "00:00:00:00:00:00" else { continue }
            let ip = ipKey.contains(".") ? ipKey : (hint["ipaddr"] as? String ?? ipKey)
            guard ip.contains(".") else { continue }
            let name = hint["name"] as? String ?? hint["hostname"] as? String
            let low = m.lowercased()
            arp.append(ARPEntry(ip: ip, mac: low))
            dhcp.append(DHCPLease(mac: low, ip: ip, hostname: (name?.isEmpty == false && name != "*") ? name : nil))
        }
        if arp.isEmpty { throw NetworkError.operationFailed("luci-proxy host_hints: 0 entries") }
        return (arp, dhcp)
    }

    // MARK: Firewall

    func getFirewallConfig() async throws -> [String: UCISection] {
        let resp: UbusResponse<UCIGetData> = try await ubusCall(
            object: "uci", method: "get",
            args: ["config": "firewall"]
        )
        return resp.result?.data?.values ?? [:]
    }

    func addBlockRule(name: String, srcMac: String) async throws -> String {
        let raw = try await ubusCallRaw(object: "uci", method: "add",
                                        params: ["config": "firewall", "type": "rule"] as [String: String])
        guard let dict = raw as? [String: Any],
              let section = dict["section"] as? String, !section.isEmpty else {
            throw NetworkError.operationFailed("Could not create UCI rule section")
        }
        try await ubusCallRaw(object: "uci", method: "set",
                               params: ["config": "firewall", "section": section,
                                        "values": ["name": name, "src": "lan", "dest": "wan",
                                                   "src_mac": srcMac.uppercased(),
                                                   "target": "REJECT", "enabled": "1"]] as [String: Any])
        try await commitFirewall()
        return section
    }

    func setRuleEnabled(section: String, enabled: Bool) async throws {
        try await ubusCallRaw(object: "uci", method: "set",
                               params: ["config": "firewall", "section": section,
                                        "values": ["enabled": enabled ? "1" : "0"]] as [String: Any])
        try await commitFirewall()
    }

    func deleteRule(section: String) async throws {
        try await ubusCallRaw(object: "uci", method: "delete",
                               params: ["config": "firewall", "section": section] as [String: String])
        try await commitFirewall()
    }

    // MARK: Router control

    func reboot() async throws {
        // Try ubus direct (rpc-sys, then sys)
        for svc in ["rpc-sys", "sys"] {
            if (try? await ubusCallRaw(object: svc, method: "reboot", params: [:] as [String: String])) != nil { return }
        }
        // Fall back to LuCI proxy
        try await rebootViaLuCIProxy()
    }

    private func rebootViaLuCIProxy() async throws {
        guard let cookie = sysauthCookie ?? authToken else { throw NetworkError.sessionExpired }
        let stok = sysauthStok ?? ""
        let emptyArgs: [String: Any] = [:]
        if (try? await proxyUbusCall(service: "rpc-sys", method: "reboot",
                                      args: emptyArgs, cookie: cookie, stok: stok)) == true { return }
        if (try? await proxyUbusCall(service: "sys", method: "reboot",
                                      args: emptyArgs, cookie: cookie, stok: stok)) == true { return }
        throw NetworkError.operationFailed("Reboot failed via proxy")
    }

    @discardableResult
    private func proxyExecCommand(_ cmd: String, cookie: String, stok: String) async throws -> Bool {
        for svc in ["rpc-sys", "sys"] {
            if (try? await proxyUbusCall(service: svc, method: "exec",
                                          args: ["command": cmd], cookie: cookie, stok: stok)) == true {
                return true
            }
        }
        return false
    }

    @discardableResult
    private func proxyUbusCall(service: String, method: String,
                                args: [String: Any], cookie: String, stok: String) async throws -> Bool {
        let scheme = useHTTPS ? "https" : "http"
        let stokSeg = stok.isEmpty ? "" : ";stok=\(stok)"
        guard let url = URL(string: "\(scheme)://\(host)/cgi-bin/luci/\(stokSeg)/admin/ubus") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("sysauth_http=\(cookie); sysauth_https=\(cookie); sysauth=\(cookie)", forHTTPHeaderField: "Cookie")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "call",
                                   "params": [cookie, service, method, args]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await urlSession.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [Any],
              let code = result.first as? Int else { return false }
        return code == 0
    }

    private func ensureACLIfNeeded() async {
        guard let username = storedUsername, let password = storedPassword else { return }

        // If direct ubus already works, nothing to do
        if (try? await ubusCallRaw(object: "file", method: "list",
                                    params: ["path": "/usr/share/acl.d"] as [String: String])) != nil { return }

        // Need a proxy session to write the file
        let cookie = sysauthCookie ?? authToken ?? ""
        let stok = sysauthStok ?? ""
        guard !cookie.isEmpty else { return }

        // ACL in this router's format (user/access/methods)
        let acl = "{\"user\":\"\(username)\",\"access\":{\"network\":{\"methods\":[\"*\"]},\"dhcp\":{\"methods\":[\"*\"]},\"rpc-sys\":{\"methods\":[\"*\"]},\"sys\":{\"methods\":[\"*\"]},\"file\":{\"methods\":[\"*\"]},\"uci\":{\"methods\":[\"*\"]},\"session\":{\"methods\":[\"*\"]}}}"
        guard let aclB64 = acl.data(using: .utf8)?.base64EncodedString() else { return }

        // Strategy 1: file.write ubus call via proxy (granted by luci-base.json)
        let wrote = (try? await proxyUbusCall(
            service: "file", method: "write",
            args: ["path": "/usr/share/acl.d/pocketluci.json", "data": aclB64],
            cookie: cookie, stok: stok
        )) ?? false

        // Strategy 2: shell exec via proxy if file.write didn't work
        if !wrote {
            let writeCmd = "printf '%s' '\(acl)' > /usr/share/acl.d/pocketluci.json"
            _ = try? await proxyUbusCall(service: "rpc-sys", method: "exec",
                                          args: ["command": writeCmd], cookie: cookie, stok: stok)
            _ = try? await proxyUbusCall(service: "sys", method: "exec",
                                          args: ["command": writeCmd], cookie: cookie, stok: stok)
        }

        // Restart rpcd: try file.exec then shell exec
        let restarted = (try? await proxyUbusCall(
            service: "file", method: "exec",
            args: ["command": "/etc/init.d/rpcd", "params": ["restart"]],
            cookie: cookie, stok: stok
        )) ?? false
        if !restarted {
            _ = try? await proxyUbusCall(service: "rpc-sys", method: "exec",
                                          args: ["command": "/etc/init.d/rpcd restart"], cookie: cookie, stok: stok)
            _ = try? await proxyUbusCall(service: "sys", method: "exec",
                                          args: ["command": "/etc/init.d/rpcd restart"], cookie: cookie, stok: stok)
        }

        // Wait for rpcd to restart
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Re-authenticate — new session will have ACL permissions
        try? await authenticate(username: username, password: password)
    }

    // MARK: Schedules (cron-based)

    func applyScheduleCron(mac: String, blockHour: Int, blockMinute: Int,
                           unblockHour: Int, unblockMinute: Int, days: [Int]) async throws {
        let m = mac.uppercased()
        let dayStr = days.map(String.init).joined(separator: ",")
        let blockCmd = "iptables -I FORWARD -m mac --mac-source \(m) -j REJECT"
        let unblockCmd = "iptables -D FORWARD -m mac --mac-source \(m) -j REJECT"
        let cron = "\(blockMinute) \(blockHour) * * \(dayStr) \(blockCmd)\n\(unblockMinute) \(unblockHour) * * \(dayStr) \(unblockCmd)"
        let cmd = "printf '%s\\n' '\(cron)' >> /etc/crontabs/root && /etc/init.d/cron restart"
        let _: UbusResponse<ExecData> = try await ubusCall(
            object: "rpc-sys", method: "exec", args: ["command": cmd]
        )
    }

    func removeScheduleCron(mac: String) async throws {
        let m = mac.uppercased()
        let cmd = "grep -v '\(m)' /etc/crontabs/root > /tmp/_cron.tmp && mv /tmp/_cron.tmp /etc/crontabs/root && /etc/init.d/cron restart"
        let _: UbusResponse<ExecData> = try await ubusCall(
            object: "rpc-sys", method: "exec", args: ["command": cmd]
        )
    }

    // MARK: Private

    // JSONSerialization-based ubus call — tolerates any result[1] type
    @discardableResult
    private func ubusCallRaw(object: String, method: String, params: Any) async throws -> Any {
        guard !host.isEmpty else { throw NetworkError.notConfigured }
        guard let token = authToken else { throw NetworkError.sessionExpired }
        let scheme = useHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host)/ubus") else {
            throw NetworkError.requestFailed("Invalid URL")
        }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "call",
                                   "params": [token, object, method, params]]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await urlSession.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [Any], !result.isEmpty,
              let code = result[0] as? Int, code == 0 else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["result"] as? [Any] }.flatMap { $0.first as? Int }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }.flatMap { $0["message"] as? String }
            throw NetworkError.operationFailed("\(object).\(method) failed (code \(code ?? -1))\(msg.map { ": \($0)" } ?? "")")
        }
        return result.count >= 2 ? result[1] : [String: Any]()
    }

    private func ubusExecString(service: String, command: String) async throws -> String {
        let raw = try await ubusCallRaw(object: service, method: "exec", params: ["command": command])
        if let str = raw as? String { return str }
        if let dict = raw as? [String: Any], let out = dict["stdout"] as? String { return out }
        throw NetworkError.operationFailed("\(service).exec: unexpected type \(type(of: raw))")
    }

    private func ubusFileRead(path: String) async throws -> String {
        let raw = try await ubusCallRaw(object: "file", method: "read", params: ["path": path])
        guard let dict = raw as? [String: Any], let data = dict["data"] as? String else {
            throw NetworkError.operationFailed("file.read: no data")
        }
        if let decoded = Data(base64Encoded: data), let text = String(data: decoded, encoding: .utf8) {
            return text
        }
        return data
    }

    private func tryLuCIRPCAuth(username: String, password: String) async {
        let scheme = useHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host)/cgi-bin/luci/rpc/auth") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONEncoder().encode(
            LuCIAuthBody(params: .init(username: username, password: password))
        ) else { return }
        req.httpBody = body
        guard let (data, _) = try? await urlSession.data(for: req),
              let resp = try? JSONDecoder().decode(LuCIAuthResponse.self, from: data),
              let token = resp.result, !token.isEmpty,
              token != "00000000000000000000000000000000" else { return }
        luciToken = token
    }

    private func luciWebLogin(username: String, password: String) async {
        let scheme = useHTTPS ? "https" : "http"
        guard let loginURL = URL(string: "\(scheme)://\(host)/cgi-bin/luci/") else { return }
        var req = URLRequest(url: loginURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let eu = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let ep = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        req.httpBody = "luci_username=\(eu)&luci_password=\(ep)".data(using: .utf8)

        // Follow redirect naturally — stok ends up in final URL, cookie in storage
        guard let (_, response) = try? await urlSession.data(for: req) else { return }

        // Extract stok from final response URL (e.g. /cgi-bin/luci/;stok=XXXX/admin/)
        if let finalStr = (response as? HTTPURLResponse)?.url?.absoluteString,
           let range = finalStr.range(of: "stok=") {
            let tail = finalStr[range.upperBound...]
            let stok = String(tail.prefix(while: { $0 != "/" && $0 != "?" && $0 != "&" && $0 != ";" }))
            if !stok.isEmpty { sysauthStok = stok }
        }

        // Extract sysauth cookie from session cookie storage
        let storage = urlSession.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        let checkURLs = [loginURL, URL(string: "\(scheme)://\(host)/")].compactMap { $0 }
        for checkURL in checkURLs {
            if let cookies = storage.cookies(for: checkURL) {
                for c in cookies where c.name.lowercased().hasPrefix("sysauth") {
                    sysauthCookie = c.value
                    return
                }
            }
        }
    }

    private func commitFirewall() async throws {
        try await ubusCallRaw(object: "uci", method: "commit",
                               params: ["config": "firewall"] as [String: String])
        // Best-effort reload — try fw4 then fw3 then legacy restart; ignore errors (ACL may deny exec)
        let reloadCmd = "fw4 reload 2>/dev/null || fw3 reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null &"
        for svc in ["rpc-sys", "sys"] {
            if (try? await ubusCallRaw(object: svc, method: "exec",
                                       params: ["command": reloadCmd] as [String: String])) != nil { return }
        }
    }

    private func ubusCall<T: Decodable>(
        path: String = "/ubus",
        object: String,
        method: String,
        args: [String: String]
    ) async throws -> UbusResponse<T> {
        guard !host.isEmpty else { throw NetworkError.notConfigured }
        guard let token = authToken else { throw NetworkError.sessionExpired }
        let scheme = useHTTPS ? "https" : "http"
        let urlStr = "\(scheme)://\(host)\(path)"
        guard let url = URL(string: urlStr) else {
            throw NetworkError.requestFailed("Invalid URL")
        }

        let body = UbusBody(params: UbusParams(
            session: token, object: object, callMethod: method, args: args
        ))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.requestFailed("No HTTP response")
        }
        if (http.statusCode == 307 || http.statusCode == 308) && !useHTTPS {
            if let location = http.value(forHTTPHeaderField: "Location"),
               location.hasPrefix("https://") {
                useHTTPS = true
                return try await ubusCall(path: path, object: object, method: method, args: args)
            }
        }
        if http.statusCode == 404 {
            throw NetworkError.rpcNotFound("\(scheme)://\(host)\(path)")
        }
        guard http.statusCode == 200 else {
            throw NetworkError.requestFailed("HTTP \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(UbusResponse<T>.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }
    }

    // /proc/net/arp format: IP HW_TYPE FLAGS MAC MASK DEVICE
    private func parseARPTable(_ raw: String) -> [ARPEntry] {
        var lines = raw.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }
        lines.removeFirst() // skip header
        return lines.compactMap { line in
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 4 else { return nil }
            let ip = String(cols[0])
            let mac = String(cols[3]).lowercased()
            guard mac.contains(":"), mac != "00:00:00:00:00:00" else { return nil }
            return ARPEntry(ip: ip, mac: mac)
        }
    }

    private func parseDHCPLeases(_ raw: String) -> [DHCPLease] {
        raw.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { return nil }
            let hostname = String(parts[3])
            return DHCPLease(
                mac: String(parts[1]).lowercased(),
                ip: String(parts[2]),
                hostname: hostname == "*" ? nil : hostname
            )
        }
    }
}

// MARK: - TLS bypass for self-signed certs

private final class TrustAllDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Only preserve POST body on 307/308 (not 302/301 which should become GET)
        guard response.statusCode == 307 || response.statusCode == 308,
              let orig = task.originalRequest, orig.httpMethod == "POST" else {
            completionHandler(request)
            return
        }
        var preserved = request
        preserved.httpMethod = "POST"
        preserved.httpBody = orig.httpBody
        orig.allHTTPHeaderFields?.forEach { preserved.setValue($1, forHTTPHeaderField: $0) }
        completionHandler(preserved)
    }
}

// MARK: - Captures sysauth cookie + stok from LuCI web-form login redirect

private final class LoginRedirectCapture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var capturedCookie: String?
    var capturedStok: String?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Extract stok from Location: /cgi-bin/luci/;stok=XXXX/admin/
        if let location = response.value(forHTTPHeaderField: "Location"),
           let range = location.range(of: "stok=") {
            let tail = location[range.upperBound...]
            capturedStok = String(tail.prefix(while: { $0 != "/" && $0 != "?" && $0 != "&" && $0 != ";" }))
        }
        // Extract sysauth cookie from Set-Cookie header
        for (key, value) in response.allHeaderFields {
            guard let k = key as? String, k.caseInsensitiveCompare("Set-Cookie") == .orderedSame,
                  let v = value as? String else { continue }
            let nameVal = v.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if nameVal.lowercased().hasPrefix("sysauth") {
                let parts = nameVal.components(separatedBy: "=")
                if parts.count >= 2 { capturedCookie = parts.dropFirst().joined(separator: "=") }
            }
        }
        completionHandler(nil) // Don't follow redirect — we have what we need
    }
}
