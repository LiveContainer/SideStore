//
//  PatchAppIconOperation.swift
//  AltStore
//
//  Created by Magesh K on 23/7/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import UIKit
import Foundation
import AltStoreCore

@objc(PatchAppIconOperation)
class PatchAppIconOperation: ResultOperation<Void>, OperationLogging {
    
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext) {
        self.context = context
        super.init()
    }
    
    override func main() {
        super.main()
        
        Task {
            do {
                try await self.execute()
                self.finish(.success(()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private func execute() async throws {
        if let error = self.context.error {
            throw error
        }
        
        guard let app = self.context.app else {
            throw OperationError.invalidParameters("PatchAppIconOperation.execute: self.context.app is nil")
        }
        
        let bundleIdentifier = self.context.bundleIdentifier
        let alternateIconURL = InstalledApp.alternateIconURL(forBundleIdentifier: bundleIdentifier)
        
        guard FileManager.default.fileExists(atPath: alternateIconURL.path) else {
            return
        }
        
        let appBundleURL = app.fileURL
        
        let data = try Data(contentsOf: alternateIconURL)
        guard let image = UIImage(data: data) else {
            throw OperationError.invalidParameters("Invalid icon image data")
        }
        
        let iconScale = await MainActor.run { Int(UIScreen.main.scale) }
        guard let icon = image.resizing(toFill: CGSize(width: 60 * iconScale, height: 60 * iconScale)),
              let iconData = icon.pngData()
        else {
            throw OperationError.invalidParameters("Failed to resize icon image")
        }
        
        let iconName = "AltIcon"
        let iconURL = appBundleURL.appendingPathComponent(iconName + "@\(iconScale)x.png")
        try iconData.write(to: iconURL, options: .atomic)
        
        let plistURL = appBundleURL.appendingPathComponent("Info.plist")
        guard var infoPlist = NSMutableDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw OperationError.invalidParameters("Failed to load Info.plist from app bundle")
        }
        
        let iconDictionary = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": [iconName]]]
        infoPlist["CFBundleIcons"] = iconDictionary
        
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: plistURL, options: .atomic)
    }
}
