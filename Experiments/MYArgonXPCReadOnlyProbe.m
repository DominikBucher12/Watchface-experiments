#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Read-only NanoTimeKit face-support probe for watchOS Simulator.
// Never sends ingestKeyDescriptor: or any mutation request.
@protocol MYArgonFaceSupportReadOnly
- (void)knownKeyDescriptors:(void (^)(id descriptors))reply;
@end

static NSXPCConnection *MYArgonConnection = nil;
static NSUInteger MYArgonGeneration = 0;

static void MYArgonFinish(NSXPCConnection *connection, NSUInteger generation,
                          NSString *result) {
    // All mutable probe state lives exclusively on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != MYArgonGeneration || MYArgonConnection != connection) {
            NSLog(@"ARGON_XPC LATE result=%@ generation=%lu", result,
                  (unsigned long)generation);
            return;
        }
        NSLog(@"ARGON_XPC END result=%@", result);
        MYArgonConnection = nil;
        [connection invalidate];
    });
}

__attribute__((visibility("default"))) void MYProbeArgonReadOnlyXPC(void) {
    // Enforce serial client setup even if called off main thread.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ MYProbeArgonReadOnlyXPC(); });
        return;
    }
    NSLog(@"ARGON_XPC V4 BEGIN service=com.apple.nanotimekit.facesupportserver");
    if (MYArgonConnection) {
        NSLog(@"ARGON_XPC SKIP previous probe still active");
        return;
    }

    typedef NSXPCInterface *(*InterfaceFactory)(void);
    InterfaceFactory factory = (InterfaceFactory)dlsym(RTLD_DEFAULT,
                                                       "NTKFaceSupportServerInterface");
    if (!factory) {
        NSLog(@"ARGON_XPC FAIL missing NTKFaceSupportServerInterface");
        return;
    }
    NSXPCInterface *interface = factory();
    if (!interface) {
        NSLog(@"ARGON_XPC FAIL interface=nil");
        return;
    }

    SEL selector = @selector(knownKeyDescriptors:);
    Protocol *actualProtocol = interface.protocol;
    struct objc_method_description desc = {NULL, NULL};
    if (actualProtocol) {
        desc = protocol_getMethodDescription(actualProtocol, selector, YES, YES);
        if (!desc.name) {
            desc = protocol_getMethodDescription(actualProtocol, selector, NO, YES);
        }
    }
    NSLog(@"ARGON_XPC V3 protocol=%s selector=%s encoding=%s",
          actualProtocol ? protocol_getName(actualProtocol) : "(nil)",
          sel_getName(selector), desc.types ?: "(not exposed)");
    if (!desc.name) {
        NSLog(@"ARGON_XPC FAIL simulator interface does not declare knownKeyDescriptors:");
        return;
    }

    SEL machInit = sel_registerName("initWithMachServiceName:options:");
    if (![NSXPCConnection instancesRespondToSelector:machInit]) {
        NSLog(@"ARGON_XPC FAIL Mach service initializer unavailable");
        return;
    }

    const NSUInteger options = 0x1000; // Match Apple's known privileged client path.
    NSXPCConnection *connection = ((id (*)(id, SEL, NSString *, NSUInteger))objc_msgSend)(
        [NSXPCConnection alloc], machInit,
        @"com.apple.nanotimekit.facesupportserver", options);
    if (!connection) {
        NSLog(@"ARGON_XPC FAIL connection=nil");
        return;
    }

    NSUInteger generation = ++MYArgonGeneration;
    MYArgonConnection = connection;
    connection.remoteObjectInterface = interface;
    connection.interruptionHandler = ^{
        NSLog(@"ARGON_XPC V3 INTERRUPTED generation=%lu", (unsigned long)generation);
        MYArgonFinish(connection, generation, @"interrupted");
    };
    connection.invalidationHandler = ^{
        NSLog(@"ARGON_XPC V3 INVALIDATED generation=%lu", (unsigned long)generation);
    };
    [connection resume];

    id<MYArgonFaceSupportReadOnly> proxy =
        (id<MYArgonFaceSupportReadOnly>)[connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            NSLog(@"ARGON_XPC V3 ERROR domain=%@ code=%ld description=%@",
                  error.domain, (long)error.code, error.localizedDescription);
            MYArgonFinish(connection, generation, @"error");
        }];
    if (!proxy) {
        MYArgonFinish(connection, generation, @"no-proxy");
        return;
    }

    NSLog(@"ARGON_XPC V3 SEND options=0x%lx remotePID=%d thread=%@",
          (unsigned long)options, connection.processIdentifier,
          [NSThread isMainThread] ? @"main" : @"background");
    // Objective-C protocol dispatch instead of casting objc_msgSend to an ad-hoc ABI.
    [proxy knownKeyDescriptors:^(id descriptors) {
        NSString *kind = descriptors ? NSStringFromClass([descriptors class]) : @"nil";
        NSString *count = @"unknown";
        if ([descriptors respondsToSelector:@selector(count)]) {
            count = [NSString stringWithFormat:@"%lu",
                     (unsigned long)((NSUInteger (*)(id, SEL))objc_msgSend)(
                         descriptors, @selector(count))];
        }
        NSLog(@"ARGON_XPC V3 REPLY type=%@ count=%@", kind, count);
        MYArgonFinish(connection, generation, @"reply");
    }];
    NSLog(@"ARGON_XPC V3 SENT async (not an acknowledgement)");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != MYArgonGeneration || MYArgonConnection != connection) return;
        NSLog(@"ARGON_XPC V4 TIMEOUT 12s remotePID=%d; connection remains OPEN", connection.processIdentifier);
        NSLog(@"ARGON_XPC V4 WAITING for late reply/error/interruption; no local invalidation");
    });
}
