//
//  HealthCheckView.swift
//  AltStore
//
//  Created by Magesh K on 11/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Minimuxer
import Darwin

struct LocalInterfaceInfo: Hashable, Identifiable {
    var id: String { name + "-" + ip }
    let name: String
    let ip: String
    let subnet: String
    let type: String
}

/*
 Minimuxer.shared.isReady Result Mapping to Core Requirements Statuses:
 
 | Ready Result Case                        | Network   | VPN       | IPSec     | Ping      | Pairing   | DDI       |
 | ---------------------------------------- | --------- | --------- | --------- | --------- | --------- | --------- |
 | .success                                 | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied |
 | .failure(.noConnection)                  | Failed    | Unknown   | Unknown   | Unknown   | Unknown   | Unknown   |
 | .failure(.noVPN) / .failure(.invalidVPN) | Satisfied | Failed    | Unknown   | Unknown   | Unknown   | Unknown   |
 | .failure(.pairingFile)                   | Satisfied | Satisfied | Satisfied | Satisfied | Failed    | Unknown   |
 | .failure(.invalidPairing)                | Satisfied | Satisfied | Satisfied | Satisfied | Failed    | Unknown   |
 | .failure(.mount)                         | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied | Failed    |
 | .failure(.muxerNotListening)             | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied | Satisfied |
 */

@MainActor
final class HealthCheckViewModel: ObservableObject {
    @Published var isWifiSatisfied = false
    @Published var isWiredSatisfied = false
    @Published var isUsbSatisfied = false
    @Published var isBridgeSatisfied = false
    @Published var isUTunAvailable = false
    @Published var isIKEv2IPSecAvailable = false
    
    @Published var tunnelIfaceIp: String? = nil
    @Published var subnetMask: String? = nil
    @Published var tunnelPeerIp: String? = nil
    @Published var overridePeerIp: String = ""
    @Published var overrideEffective = false
    
    @Published var activeProtocol = ""
    @Published var isPingSuccessful = false
    
    @Published var isDDIMounted = false
    @Published var isPairingFileVerified = false
    
    @Published var networkSatisfied: Bool? = nil
    @Published var vpnSatisfied: Bool? = nil
    @Published var ipsecSatisfied: Bool? = nil
    @Published var pingSatisfied: Bool? = nil
    @Published var pairingSatisfied: Bool? = nil
    @Published var ddiSatisfied: Bool? = nil
    
    @Published var minimuxerReadyResult: Result<Bool, MinimuxerError>? = nil
    @Published var availableInterfaces: [LocalInterfaceInfo] = []
    struct HealthCheckMetrics {
        let wifi: Bool
        let wired: Bool
        let usb: Bool
        let bridge: Bool
        let utun: Bool
        let ipsec: Bool
        let tunnelIfaceIp: String?
        let subnetMask: String?
        let tunnelPeerIp: String?
        let overridePeerIp: String?
        let overrideEffective: Bool
        let protocolStr: String
        let pingSuccess: Bool
        let ddi: Bool
        let pairingVerified: Bool
        let readyResult: Result<Bool, MinimuxerError>
        let scanned: [LocalInterfaceInfo]
    }

    nonisolated private func fetchMetrics() async -> HealthCheckMetrics {
        let wifi = Minimuxer.network.isWifiSatisfied
        let wired = Minimuxer.network.isWiredSatisfied
        let usb = Minimuxer.network.isUsbSatisfied
        let bridge = Minimuxer.network.isBridgeSatisfied
        let utun = Minimuxer.network.isUTunAvailable
        let ipsec = Minimuxer.network.isIKEv2IPSecAvailable
        
        let tunnelIfaceIp = TunnelConfig.shared.tunnelIfaceIp
        let subnetMask = TunnelConfig.shared.subnetMask
        let tunnelPeerIp = TunnelConfig.shared.tunnelPeerIp
        let overridePeerIp = TunnelConfig.shared.overridePeerIp
        let overrideEffective = TunnelConfig.shared.overrideEffective
        
        let pairingType = Minimuxer.shared.getPairingFileType()
        let isRp = pairingType == .rppairing
        let protocolStr: String
        switch pairingType {
        case .rppairing:
            protocolStr = "Remote Pairing"
        case .lockdown:
            protocolStr = "Lockdown"
        case .unknown:
            protocolStr = "Unknown"
        }
        
        let pingSuccess = Minimuxer.shared.testDeviceConnection(ifaddr: overridePeerIp)
        
        let ddi = (try? await Minimuxer.shared.isDDIMounted()) ?? false
        let pairingVerified = (try? await Minimuxer.shared.fetchUDID() != nil) ?? false
        let readyResult = await Minimuxer.shared.isReady
        let scanned = self.scanLocalInterfaces()
        
        return HealthCheckMetrics(
            wifi: wifi, wired: wired, usb: usb, bridge: bridge, utun: utun, ipsec: ipsec,
            tunnelIfaceIp: tunnelIfaceIp, subnetMask: subnetMask, tunnelPeerIp: tunnelPeerIp,
            overridePeerIp: overridePeerIp, overrideEffective: overrideEffective,
            protocolStr: protocolStr, pingSuccess: pingSuccess,
            ddi: ddi, pairingVerified: pairingVerified, readyResult: readyResult, scanned: scanned
        )
    }

    func pollMetrics() async {
        while !Task.isCancelled {
            if UIApplication.shared.applicationState == .active {
                // Hop to background thread to perform all synchronous FFI/network checks
                let metrics = await self.fetchMetrics()
                
                let status = self.computeStatuses(
                    readyResult: metrics.readyResult,
                    isRp: metrics.protocolStr == "Remote Pairing",
                    wifi: metrics.wifi,
                    wired: metrics.wired,
                    usb: metrics.usb,
                    bridge: metrics.bridge,
                    utun: metrics.utun,
                    ipsec: metrics.ipsec,
                    pingSuccess: metrics.pingSuccess,
                    pairingVerified: metrics.pairingVerified,
                    ddi: metrics.ddi
                )
                
                // Update UI back on Main Actor
                self.updateUI(
                    wifi: metrics.wifi, wired: metrics.wired, usb: metrics.usb, bridge: metrics.bridge,
                    utun: metrics.utun, ipsec: metrics.ipsec, tunnelIfaceIp: metrics.tunnelIfaceIp,
                    subnetMask: metrics.subnetMask, tunnelPeerIp: metrics.tunnelPeerIp,
                    overridePeerIp: metrics.overridePeerIp, overrideEffective: metrics.overrideEffective,
                    protocolStr: metrics.protocolStr, pingSuccess: metrics.pingSuccess,
                    ddi: metrics.ddi, pairingVerified: metrics.pairingVerified,
                    netSat: status.netSat, vpnSat: status.vpnSat, ipsecSat: status.ipsecSat,
                    pingSat: status.pingSat, pairingSat: status.pairingSat, ddiSat: status.ddiSat,
                    readyResult: metrics.readyResult, scanned: metrics.scanned
                )
            }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    nonisolated private func computeStatuses(
        readyResult: Result<Bool, MinimuxerError>,
        isRp: Bool,
        wifi: Bool,
        wired: Bool,
        usb: Bool,
        bridge: Bool,
        utun: Bool,
        ipsec: Bool,
        pingSuccess: Bool,
        pairingVerified: Bool,
        ddi: Bool
    ) -> (
        netSat: Bool?,
        vpnSat: Bool?,
        ipsecSat: Bool?,
        pingSat: Bool?,
        pairingSat: Bool?,
        ddiSat: Bool?
    ) {
        var netSat: Bool? = nil
        var vpnSat: Bool? = nil
        var ipsecSat: Bool? = nil
        var pingSat: Bool? = nil
        var pairingSat: Bool? = nil
        var ddiSat: Bool? = nil
        
        switch readyResult {
        case .success:
            netSat = true
            vpnSat = true
            ipsecSat = isRp ? nil : true
            pingSat = true
            pairingSat = true
            ddiSat = true
            
        case .failure(let error):
            switch error {
            case .noConnection:
                netSat = false
                vpnSat = nil
                ipsecSat = nil
                pingSat = nil
                pairingSat = nil
                ddiSat = nil
                
            case .noVPN:
                netSat = true
                vpnSat = false
                ipsecSat = nil
                pingSat = nil
                pairingSat = nil
                ddiSat = nil
                
            case .invalidVPN(let reason):
                netSat = true
                vpnSat = true
                if reason.contains("ipsec") || reason.contains("IKEv2") {
                    ipsecSat = false
                    pingSat = nil
                    pairingSat = nil
                    ddiSat = nil
                } else {
                    ipsecSat = isRp ? nil : true
                    pingSat = false
                    pairingSat = nil
                    ddiSat = nil
                }
                
            case .pairingFile, .invalidPairing:
                netSat = true
                vpnSat = true
                ipsecSat = isRp ? nil : true
                pingSat = true
                pairingSat = false
                ddiSat = nil
                
            case .mount:
                netSat = true
                vpnSat = true
                ipsecSat = isRp ? nil : true
                pingSat = true
                pairingSat = true
                ddiSat = false
                
            case .muxerNotListening:
                netSat = true
                vpnSat = true
                ipsecSat = isRp ? nil : true
                pingSat = true
                pairingSat = true
                ddiSat = true
                
            default:
                netSat = wifi // || wired || usb || bridge
                vpnSat = utun
                ipsecSat = isRp ? nil : ipsec
                pingSat = pingSuccess
                pairingSat = pairingVerified
                ddiSat = ddi
            }
        }
        
        if pairingSat == nil {
            pairingSat = Minimuxer.shared.isPairingFileLoaded ? nil : false
        }
        
        return (netSat, vpnSat, ipsecSat, pingSat, pairingSat, ddiSat)
    }
    
    @MainActor
    private func updateUI(
        wifi: Bool, wired: Bool, usb: Bool, bridge: Bool, utun: Bool, ipsec: Bool,
        tunnelIfaceIp: String?, subnetMask: String?, tunnelPeerIp: String?, overridePeerIp: String?, overrideEffective: Bool,
        protocolStr: String, pingSuccess: Bool, ddi: Bool, pairingVerified: Bool,
        netSat: Bool?, vpnSat: Bool?, ipsecSat: Bool?, pingSat: Bool?, pairingSat: Bool?, ddiSat: Bool?,
        readyResult: Result<Bool, MinimuxerError>, scanned: [LocalInterfaceInfo]
    ) {
        self.isWifiSatisfied = wifi
        self.isWiredSatisfied = wired
        self.isUsbSatisfied = usb
        self.isBridgeSatisfied = bridge
        self.isUTunAvailable = utun
        self.isIKEv2IPSecAvailable = ipsec
        
        self.tunnelIfaceIp = tunnelIfaceIp
        self.subnetMask = subnetMask
        self.tunnelPeerIp = tunnelPeerIp
        self.overridePeerIp = overridePeerIp ?? "N/A"
        self.overrideEffective = overrideEffective
        
        self.activeProtocol = protocolStr
        self.isPingSuccessful = pingSuccess
        
        self.isDDIMounted = ddi
        self.isPairingFileVerified = pairingVerified
        
        self.networkSatisfied = netSat
        self.vpnSatisfied = vpnSat
        self.ipsecSatisfied = ipsecSat
        self.pingSatisfied = pingSat
        self.pairingSatisfied = pairingSat
        self.ddiSatisfied = ddiSat
        
        self.minimuxerReadyResult = readyResult
        self.availableInterfaces = scanned
    }

    func updateUIInTask(metrics: HealthCheckMetrics, status: (netSat: Bool?, vpnSat: Bool?, ipsecSat: Bool?, pingSat: Bool?, pairingSat: Bool?, ddiSat: Bool?)) {
        self.updateUI(
            wifi: metrics.wifi, wired: metrics.wired, usb: metrics.usb, bridge: metrics.bridge,
            utun: metrics.utun, ipsec: metrics.ipsec, tunnelIfaceIp: metrics.tunnelIfaceIp,
            subnetMask: metrics.subnetMask, tunnelPeerIp: metrics.tunnelPeerIp,
            overridePeerIp: metrics.overridePeerIp, overrideEffective: metrics.overrideEffective,
            protocolStr: metrics.protocolStr, pingSuccess: metrics.pingSuccess,
            ddi: metrics.ddi, pairingVerified: metrics.pairingVerified,
            netSat: status.netSat, vpnSat: status.vpnSat, ipsecSat: status.ipsecSat,
            pingSat: status.pingSat, pairingSat: status.pairingSat, ddiSat: status.ddiSat,
            readyResult: metrics.readyResult, scanned: metrics.scanned
        )
    }

    
    nonisolated private func scanLocalInterfaces() -> [LocalInterfaceInfo] {
        var interfaces = [LocalInterfaceInfo]()
        var head: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let e = p.pointee
            let flags = Int32(e.ifa_flags)
            
            let ipv4 = e.ifa_addr?.pointee.sa_family == UInt8(AF_INET)
            let active = (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING)
            
            if ipv4 && active {
                if let name = String(utf8String: e.ifa_name),
                   let addr = e.ifa_addr,
                   let mask = e.ifa_netmask {
                    
                    var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0,
                       getnameinfo(mask, socklen_t(mask.pointee.sa_len), &maskBuf, socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        
                        let ipStr = String(cString: hostBuf)
                        let maskStr = String(cString: maskBuf)
                        
                        let type: String
                        if name.hasPrefix("utun") {
                            type = "VPN (uTun)"
                        } else if name.hasPrefix("ipsec") {
                            type = "VPN (IPSec)"
                        } else if name.hasPrefix("en") {
                            type = "Wi-Fi / Ethernet"
                        } else if name.hasPrefix("pdp") {
                            type = "Cellular"
                        } else if name.hasPrefix("lo") {
                            type = "Loopback"
                        } else if name.hasPrefix("bridge") || name.hasPrefix("ap") {
                            type = "Bridge"
                        } else {
                            type = "Other"
                        }
                        
                        interfaces.append(LocalInterfaceInfo(name: name, ip: ipStr, subnet: maskStr, type: type))
                    }
                }
            }
            cur = e.ifa_next
        }
        
        return interfaces.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

struct HealthCheckView: View {
    @StateObject private var viewModel = HealthCheckViewModel()
    
    var body: some View {
        List {
            // Section 1: Overall Health Status Card
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if case .success = viewModel.minimuxerReadyResult {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                                Text("System Healthy")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("SideStore is fully configured and ready.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            } else if case .failure(let error) = viewModel.minimuxerReadyResult {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.orange)
                                Text("Action Required")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(Minimuxer.shared.describeError(error))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.5)
                                    .padding(.vertical, 10)
                                Text("Checking status...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            
            // Section 2: Core Dependencies
            Section(header: Text("Core Requirements")) {
                DependencyRow(
                    title: "Network Connectivity",
                    subtitle: viewModel.isWifiSatisfied ? "Wi-Fi Active" : /* (viewModel.isUsbSatisfied ? "USB Connection Active" : (viewModel.isWiredSatisfied ? "Ethernet Active" : (viewModel.isBridgeSatisfied ? "Bridge Active" : "No Connection"))) */ "No Connection",
                    isSatisfied: viewModel.networkSatisfied
                )
                
                DependencyRow(
                    title: "VPN Tunnel (utun)",
                    subtitle: viewModel.isUTunAvailable ? "Connected" : "Disconnected",
                    isSatisfied: viewModel.vpnSatisfied
                )
                
                if !Minimuxer.shared.isrppairing {
                    if #available(iOS 26.4, *) {
                        DependencyRow(
                            title: "IPSec/IKEv2 Tunnel",
                            subtitle: viewModel.isIKEv2IPSecAvailable ? "Connected" : "Disconnected",
                            isSatisfied: viewModel.ipsecSatisfied
                        )
                    }
                }
                
                DependencyRow(
                    title: "Device Reachability (Ping)",
                    subtitle: viewModel.isPingSuccessful ? "Reachable" : "Unreachable",
                    isSatisfied: viewModel.pingSatisfied
                )
                
                DependencyRow(
                    title: "Pairing file",
                    subtitle: viewModel.isPairingFileVerified ? "Verified" : (Minimuxer.shared.isPairingFileLoaded ? "Loaded (Connection down)" : "Unverified / Missing"),
                    isSatisfied: viewModel.pairingSatisfied
                )
                
                DependencyRow(
                    title: "Developer Disk Image (DDI)",
                    subtitle: viewModel.isDDIMounted ? "Mounted" : "Not Mounted",
                    isSatisfied: viewModel.ddiSatisfied
                )
            }
            
            // Section 3: Discovered Configs
            Section(header: Text("VPN IP Configuration")) {
                ConfigRow(label: "Tunnel Iface IP", value: viewModel.tunnelIfaceIp)
                ConfigRow(label: "Subnet Mask", value: viewModel.subnetMask)
                ConfigRow(label: "Tunnel Peer IP", value: viewModel.tunnelPeerIp)
                ConfigRow(label: "Override Peer IP", value: viewModel.overridePeerIp.isEmpty ? nil : viewModel.overridePeerIp)
                HStack {
                    Text("Override Status")
                    Spacer()
                    Text(viewModel.overrideEffective ? "Active" : "Inactive")
                        .foregroundColor(viewModel.overrideEffective ? .green : .secondary)
                }
                HStack {
                    Text("Active Protocol")
                    Spacer()
                    Text(viewModel.activeProtocol)
                        .foregroundColor(.secondary)
                }
            }
            
            // Section 4: All Active Interfaces
            Section(header: Text("Active Network Interfaces")) {
                if viewModel.availableInterfaces.isEmpty {
                    Text("No active interfaces scanned.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    let vpnInterfaces = viewModel.availableInterfaces.filter { $0.type.contains("VPN") }
                    let localInterfaces = viewModel.availableInterfaces.filter { !$0.type.contains("VPN") }
                    
                    if !vpnInterfaces.isEmpty {
                        ForEach(vpnInterfaces) { iface in
                            InterfaceRow(iface: iface)
                        }
                    }
                    
                    if !localInterfaces.isEmpty {
                        ForEach(localInterfaces) { iface in
                            InterfaceRow(iface: iface)
                        }
                    }
                }
            }
        }
        .navigationTitle("Health Check")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.pollMetrics()
        }
    }
}

struct DependencyRow: View {
    let title: String
    let subtitle: String
    let isSatisfied: Bool?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let satisfied = isSatisfied {
                Image(systemName: satisfied ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(satisfied ? .green : .red)
                    .font(.title3)
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
    }
}

struct ConfigRow: View {
    let label: String
    let value: String?
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "N/A")
                .foregroundColor(.secondary)
        }
    }
}

struct InterfaceRow: View {
    let iface: LocalInterfaceInfo
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(iface.name)
                        .fontWeight(.semibold)
                    Text(iface.type)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(iface.type.contains("VPN") ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                        .foregroundColor(iface.type.contains("VPN") ? .blue : .primary)
                        .cornerRadius(4)
                }
                Text("Subnet: \(iface.subnet)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(iface.ip)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}
