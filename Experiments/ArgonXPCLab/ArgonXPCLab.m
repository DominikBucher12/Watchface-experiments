#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

// Independent test contract, deliberately NOT Apple's private NSXPCInterface.
@protocol ARGONLabReadOnly
- (void)knownKeyDescriptors:(void (^)(NSArray<NSString *> *descriptors))reply;
@end

@interface ARGONLabServer : NSObject <ARGONLabReadOnly>
@end
@implementation ARGONLabServer
- (void)knownKeyDescriptors:(void (^)(NSArray<NSString *> *))reply {
    NSLog(@"LAB SERVER received knownKeyDescriptors:");
    reply(@[@"dev.example.local-face", @"dev.example.pipboy-face"]);
}
@end

@interface ARGONLabListenerDelegate : NSObject <NSXPCListenerDelegate>
@property(nonatomic, strong) NSMutableArray<NSXPCConnection *> *connections;
@property(nonatomic, strong) ARGONLabServer *server;
@end
@implementation ARGONLabListenerDelegate
- (instancetype)init {
    if ((self = [super init])) {
        _connections = [NSMutableArray array];
        _server = [ARGONLabServer new];
    }
    return self;
}
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    (void)listener;
    NSLog(@"LAB SERVER accepting anonymous connection");
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ARGONLabReadOnly)];
    connection.exportedObject = self.server;
    [self.connections addObject:connection];
    [connection resume];
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        NSLog(@"LAB BEGIN mode=anonymous-listener; platform=macOS");
        ARGONLabListenerDelegate *delegate = [ARGONLabListenerDelegate new];
        NSXPCListener *listener = [NSXPCListener anonymousListener];
        listener.delegate = delegate;
        [listener resume];

        NSXPCConnection *client = [[NSXPCConnection alloc] initWithListenerEndpoint:listener.endpoint];
        client.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ARGONLabReadOnly)];
        __block BOOL finished = NO;
        client.interruptionHandler = ^{ NSLog(@"LAB CLIENT interrupted"); };
        client.invalidationHandler = ^{ NSLog(@"LAB CLIENT invalidated"); };
        [client resume];
        NSLog(@"LAB CLIENT sending knownKeyDescriptors:");
        id<ARGONLabReadOnly> proxy = [client remoteObjectProxyWithErrorHandler:^(NSError *error) {
            NSLog(@"LAB CLIENT error domain=%@ code=%ld message=%@", error.domain, (long)error.code, error.localizedDescription);
            @synchronized(client) { if (!finished) { finished = YES; } }
        }];
        [proxy knownKeyDescriptors:^(NSArray<NSString *> *descriptors) {
            NSLog(@"LAB CLIENT reply count=%lu descriptors=%@", (unsigned long)descriptors.count, descriptors);
            @synchronized(client) { if (!finished) { finished = YES; } }
        }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (YES) {
            @synchronized(client) { if (finished) break; }
            if ([deadline timeIntervalSinceNow] <= 0) break;
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        BOOL didFinish;
        @synchronized(client) { didFinish = finished; }
        NSLog(@"LAB END result=%@", didFinish ? @"callback-delivered" : @"timeout");
        [client invalidate];
        [listener invalidate];
        return didFinish ? 0 : 2;
    }
}
