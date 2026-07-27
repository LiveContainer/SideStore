//
//  XPCServer.h
//  AltStore
//
//  Created by s s on 2025/7/20.
//  Copyright © 2025 SideStore. All rights reserved.
//
@import Foundation;

@protocol RefreshServer
- (void)updateProgress:(double)value;
- (void)finish:(NSString*)error;
- (void)finishedLaunching;
@end

@protocol RefreshClient
- (void)refreshAllApps;
@end

@interface LiveProcessSideStoreHandler
@property (class, readonly, strong) LiveProcessSideStoreHandler* shared;
@property NSXPCConnection* connection;
@property NSObject<RefreshServer>* server;

@end

@interface SideStoreClient : NSObject<RefreshClient>
@property (class, readonly) SideStoreClient* shared;
- (void)notifyFinishedLaunching;
- (void) relaunchLC;
@end

@interface LCSharedUtils : NSObject
+ (BOOL)launchToGuestAppWithClassicMode:(NSUInteger)classicMode;
@end
