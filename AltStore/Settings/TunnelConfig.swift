//
//  TunnelConfig.swift
//  AltStore
//
//  Created by Magesh K on 02/03/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

final class TunnelConfig: ObservableObject {
    static let shared = TunnelConfig()

    private static let defaultOverrideIP: String = "10.7.0.1"

    @Published var tunnelIfaceIp: String?
    @Published var subnetMask: String?
    @Published var tunnelPeerIp: String?
    @Published var overridePeerIp: String = overrideIPStorage {
        didSet { Self.overrideIPStorage = overridePeerIp }
    }
    @Published var overrideEffective: Bool = false
 
    private static var overrideIPStorage: String {
        get { UserDefaults.standard.string(forKey: "TunnelOverridePeerIp") ?? defaultOverrideIP }
        set { UserDefaults.standard.set(newValue, forKey: "TunnelOverridePeerIp") }
    }

    var overrideActive: ActiveState { overrideEffective ? .yes : .no }
}
