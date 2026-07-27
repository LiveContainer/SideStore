//
//  XPCClient.m
//  AltStore
//
//  Created by s s on 2025/7/20.
//  Copyright © 2025 SideStore. All rights reserved.
//
#include "XPCServer.h"

@interface SideStoreClient(Swift)
- (void)performRefreshForRealWithServer:(id <RefreshServer> _Nonnull)server;

@end

static SideStoreClient* sharedClient = nil;
static Class LiveProcessHandlerClass = nil;

@implementation SideStoreClient

+ (SideStoreClient*)shared {
    if(!sharedClient) {
        sharedClient = [SideStoreClient new];
        LiveProcessHandlerClass = NSClassFromString(@"LiveProcessSideStoreHandler");
    }
    return sharedClient;
}

- (void)refreshAllApps {
    if(!LiveProcessHandlerClass) {
        return;
    }
    LiveProcessSideStoreHandler* handler = [LiveProcessHandlerClass shared];
    [self performRefreshForRealWithServer:handler.server];

}

- (void)notifyFinishedLaunching {
    if(!LiveProcessHandlerClass) {
        return;
    }
    LiveProcessSideStoreHandler* handler = [LiveProcessHandlerClass shared];
    handler.connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RefreshClient)];
    handler.connection.exportedObject = self;
    [handler.server finishedLaunching];
}

- (void) relaunchLC {
    [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithClassicMode:0];
}

@end


//class SideStoreClient: NSObject, RefreshClient {
//    static let lpHandlerClass = NSClassFromString("LiveProcessHandler") as? LiveProcessHandler.Type
//
//    private static var _shared: SideStoreClient? = nil
//    static var shared: SideStoreClient {
//        get {
//            if let _shared {
//                return _shared
//            } else {
//                _shared = SideStoreClient()
//                return _shared!
//            }
//        }
//    }
//
//    func refreshAllApps() {
//        guard let lpc = SideStoreClient.lpHandlerClass, let lpHandler = lpc.shared else {
//            return
//        }
//        lpHandler.server.finish("NMSL")
//    }

//    func notifyFinishedLaunching() {
//        guard let lpc = SideStoreClient.lpHandlerClass, let lpHandler = lpc.shared else {
//            return
//        }
//        lpHandler.server.finishedLaunching()

//    }
//}
