//
//  SideBackupApp.swift
//  SideBackup
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

extension Bundle {
    var appName: String? {
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        return appName
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    fileprivate static let startBackupNotification = Notification.Name("io.sidestore.StartBackup")
    fileprivate static let startRestoreNotification = Notification.Name("io.sidestore.StartRestore")
    
    fileprivate static let operationDidFinishNotification = Notification.Name("io.sidestore.BackupOperationFinished")
    
    fileprivate static let operationResultKey = "result"
    
    private var currentBackupReturnURL: URL?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.operationDidFinish(_:)), name: AppDelegate.operationDidFinishNotification, object: nil)
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return self.open(url)
    }
    
    func open(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        guard let command = components.host?.lowercased() else { return false }
        
        switch command {
        case "backup":
            guard let returnString = components.queryItems?.first(where: { $0.name == "returnURL" })?.value, let returnURL = URL(string: returnString) else { return false }
            self.currentBackupReturnURL = returnURL
            NotificationCenter.default.post(name: AppDelegate.startBackupNotification, object: nil)
            return true
            
        case "restore":
            guard let returnString = components.queryItems?.first(where: { $0.name == "returnURL" })?.value, let returnURL = URL(string: returnString) else { return false }
            self.currentBackupReturnURL = returnURL
            NotificationCenter.default.post(name: AppDelegate.startRestoreNotification, object: nil)
            return true
            
        default:
            return false
        }
    }
    
    @objc func operationDidFinish(_ notification: Notification) {
        defer {
            self.currentBackupReturnURL = nil
        }
        
        // TODO: @mahee96: This doesn't account cases where backup is too long and user switched to other apps
        //                 The check for self.currentBackupReturnURL when backup/restore was still in progress but app switched
        //                 between FG/BG is improper, since it will ignore(eat up) the response(success/failure) to parent
        //
        //                 This leaves the backup/restore to show dummy animation forever
        //
        //                 This is bad (Needs fixing - never eat up response like this unless there is no context to post response to!)
        guard
            let returnURL = self.currentBackupReturnURL,
            let result = notification.userInfo?[AppDelegate.operationResultKey] as? Result<Void, Error>
        else {
            return
        }
                
        guard var components = URLComponents(url: returnURL, resolvingAgainstBaseURL: false) else {
            return      // This is ASSERTION Failure, ie RETURN URL needs to be valid. So ignoring (eating up) response is not the solution
        }
        
        switch result {
        case .success:
            components.path = "/success"
            
        case .failure(let error as NSError):
            components.path = "/failure"
            components.queryItems = ["errorDomain": error.domain,
                                     "errorCode": String(error.code),
                                     "errorDescription": error.localizedDescription].map { URLQueryItem(name: $0, value: $1) }
        }
        
        guard let responseURL = components.url else { return }
        
        Task { @MainActor in
            // Response to the caller/parent app is posted here (url is provided by caller in incoming query params)
            debugLog("[SideBackup]: Attempting to open return URL: \(responseURL.absoluteString), scheme: \(responseURL.scheme ?? "nil")")
            let success1 = await UIApplication.shared.open(responseURL, options: [:])
            debugLog("[SideBackup]: Sent response to app with success: \(success1)")
            if success1 {
                return
            }
            debugLog("[SideBackup]: WARNING - Failed to open SideStore return URL. Scheme '\(responseURL.scheme ?? "nil")' may not be registered or SideStore is not installed.")
            // fallback to sidestore://
            components.scheme = "sidestore"
            guard let responseURL2 = components.url else { return }
            let success2 = await UIApplication.shared.open(responseURL2, options: [:])
            debugLog("[SideBackup]: Sent response to app with success: \(success2)")
            if success2 {
                return
            }
            debugLog("[SideBackup]: WARNING - Failed to open SideStore return URL. Scheme '\(responseURL.scheme ?? "nil")' may not be registered or SideStore is not installed.")
            
        }
    }
}

enum BackupOperation {
    case backup
    case restore
}

@MainActor
class AppState: ObservableObject {
    @Published var currentOperation: BackupOperation? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: AppDelegate.startBackupNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.backup()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: AppDelegate.startRestoreNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.restore()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Reset UI once we've left app (but not before).
                // TODO: @mahee96: This doesn't account cases where backup is too long and user switched to other apps
                //                 Now the user has lost his progress since current operation was cancelled due to switch between FG and BG
                //                 if this just the reset for enum such that UI stops showing progress circle, then this is fine!
                self?.currentOperation = nil
            }
            .store(in: &cancellables)
    }
    
    private func backup() async {
        self.currentOperation = .backup
        
        let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")
        
        do {
            try await BackupEngine.shared.performBackup()
            self.process(.success(()), errorTitle: "")
        } catch {
            let title = String(format: NSLocalizedString("%@ could not be backed up.", comment: ""), appName)
            self.process(.failure(error), errorTitle: title)
        }
    }
    
    private func restore() async {
        self.currentOperation = .restore
        
        let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")
        
        do {
            try await BackupEngine.shared.restoreBackup()
            self.process(.success(()), errorTitle: "")
        } catch {
            let title = String(format: NSLocalizedString("%@ could not be restored.", comment: ""), appName)
            self.process(.failure(error), errorTitle: title)
        }
    }
    
    private func process(_ result: Result<Void, Error>, errorTitle: String) {
        NotificationCenter.default.post(
            name: AppDelegate.operationDidFinishNotification,
            object: nil,
            userInfo: [AppDelegate.operationResultKey: result]
        )
    }
}

@main
struct SideBackupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = appDelegate.open(url)
                }
        }
    }
}
