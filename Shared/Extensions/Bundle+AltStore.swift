//
//  Bundle+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Security

@_silgen_name("SecTaskCreateFromSelf")
private func secTaskCreateFromSelf(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func secTaskCopyValueForEntitlement(_ task: CFTypeRef, _ entitlement: CFString, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?

public extension Bundle
{
    struct Info
    {
        public static let deviceID = "ALTDeviceID"
        public static let serverID = "ALTServerID"
        public static let certificateID = "ALTCertificateID"
        public static let appGroups = "ALTAppGroups"
        public static let altBundleID = "ALTBundleIdentifier"
        public static let storeAppBundleIdentifier =  "com.SideStore.SideStore"
        // public static var appbundleIdentifier = Bundle.main.bundleIdentifier
        public static var appbundleIdentifier: String {
            Bundle.isBundledWithLiveContainer ? "com.kdt.livecontainer" : storeAppBundleIdentifier
        }

        public static let devicePairingString = "ALTPairingFile"
        public static let urlTypes = "CFBundleURLTypes"
        public static let exportedUTIs = "UTExportedTypeDeclarations"
        public static let backgroundModes = "UIBackgroundModes"
        
        public static let untetherURL = "ALTFugu14UntetherURL"
        public static let untetherRequired = "ALTFugu14UntetherRequired"
        public static let untetherMinimumiOSVersion = "ALTFugu14UntetherMinimumVersion"
        public static let untetherMaximumiOSVersion = "ALTFugu14UntetherMaximumVersion"
    }
}

public extension Bundle
{
    var infoPlistURL: URL {
        let infoPlistURL = self.bundleURL.appendingPathComponent("Info.plist")
        return infoPlistURL
    }
    
    var provisioningProfileURL: URL {
        let provisioningProfileURL = self.bundleURL.appendingPathComponent("embedded.mobileprovision")
        return provisioningProfileURL
    }
    
    var certificateURL: URL {
        let certificateURL = self.bundleURL.appendingPathComponent("ALTCertificate.p12")
        return certificateURL
    }
    
    var altstorePlistURL: URL {
        let altstorePlistURL = self.bundleURL.appendingPathComponent("AltStore.plist")
        return altstorePlistURL
    }
}

public extension Bundle
{
    static let baseAltStoreAppGroupID = "group.com.SideStore.SideStore"
    static let isBundledWithLiveContainer = Bundle.main.bundleURL.lastPathComponent == "SideStoreApp.framework" || Bundle.main.bundleURL.lastPathComponent == "LiveWidgetExtension.appex"

    private static let entitlementAppGroups: [String] = {
        guard let task = secTaskCreateFromSelf(nil)?.takeRetainedValue(),
              let value = secTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)?.takeRetainedValue(),
              let appGroups = value as? [String] else { return [] }

        return appGroups
    }()

    var appGroups: [String] {
        return self.infoDictionary?[Bundle.Info.appGroups] as? [String] ?? []
    }
    
    static var lcBundle: Bundle? {
        Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
    }

    static var realMainBundle: Bundle {
        Bundle.isBundledWithLiveContainer ? Bundle.lcBundle ?? Bundle.main : Bundle.main
    }

    var altstoreAppGroup: String? {
        let appGroups = Bundle.entitlementAppGroups
        return appGroups.first { $0.contains(Bundle.baseAltStoreAppGroupID) } ?? appGroups.first
    }
    
    var completeInfoDictionary: [String : Any]? {
        let infoPlistURL = self.infoPlistURL
        return NSDictionary(contentsOf: infoPlistURL) as? [String : Any]
    }
}
