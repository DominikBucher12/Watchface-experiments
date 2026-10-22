#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>

// Read-only probe for watchOS 27.0.1 (24R365).
// Mirrors the verified NanoTimeKit XPC client contract without ingesting descriptors.
// Exported interface factory: _NTKFaceSupportServerInterface (0x105608).
// Client reference: _NTKAskFaceSupportServerForKnownKeyDescriptors (0x106cd0).

static NSXPCConnection *MYArgonXPCConnection = nil;
static NSUInteger MYArgonXPCSequence = 0;

__attribute__((visibility("default"))) void MYProbeArgonReadOnlyXPC(void) {
    NSLog(@"ARGON_XPC BEGIN service=com.apple.nanotimekit.facesupportserver");
    if (MYArgonXPCConnection) {
        NSLog(@"ARGON_XPC SKIP probe already active");
        NSLog(@"ARGON_XPC END");
        return;
    }

    typedef NSXPCInterface *(*InterfaceFactory)(void);
    InterfaceFactory factory = (InterfaceFactory)dlsym(RTLD_DEFAULT, "NTKFaceSupportServerInterface");
    if (!factory) {
        NSLog(@"ARGON_XPC SKIP exported interface factory unavailable");
        NSLog(@"ARGON_XPC END");
        return;
    }
    NSXPCInterface *interface = factory();
    if (!interface) {
        NSLog(@"ARGON_XPC SKIP interface factory returned nil");
        NSLog(@"ARGON_XPC END");
        return;
    }
    NSLog(@"ARGON_XPC interface=%@", NSStringFromClass([interface class]));

    // Matches the OS client reference on this specific watchOS build.
    // watchOS SDK declares this initializer API_UNAVAILABLE, although the
    // watchOS 27 NanoTimeKit binary calls it. Resolve it dynamically.
    SEL machInit = sel_registerName("initWithMachServiceName:options:");
    if (![NSXPCConnection instancesRespondToSelector:machInit]) {
        NSLog(@"ARGON_XPC SKIP Mach-service initializer absent at runtime");
        NSLog(@"ARGON_XPC END result=unsupported-runtime");
        return;
    }
    NSXPCConnection *connection = ((id (*)(id, SEL, NSString *, NSUInteger))objc_msgSend)(
        [NSXPCConnection alloc],
        machInit,
        @"com.apple.nanotimekit.facesupportserver",
        (NSUInteger)0x1000);
    if (!connection) {
        NSLog(@"ARGON_XPC FAIL connection initialization returned nil");
        NSLog(@"ARGON_XPC END");
        return;
    }
    MYArgonXPCConnection = connection;
    NSUInteger sequence = ++MYArgonXPCSequence;
    __block BOOL completed = NO;

    connection.remoteObjectInterface = interface;
    connection.interruptionHandler = ^{
        NSLog(@"ARGON_XPC INTERRUPTED");
    };
    connection.invalidationHandler = ^{
        NSLog(@"ARGON_XPC INVALIDATED");
    };
    [connection resume];
    NSLog(@"ARGON_XPC request=knownKeyDescriptors (read-only)");

    id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        if (completed) return;
        completed = YES;
        NSLog(@"ARGON_XPC ERROR domain=%@ code=%ld description=%@",
              error.domain, (long)error.code, error.localizedDescription);
        NSLog(@"ARGON_XPC END result=error");
        [connection invalidate];
        if (MYArgonXPCConnection == connection) MYArgonXPCConnection = nil;
    }];

    SEL selector = sel_registerName("knownKeyDescriptors:");
    if (!proxy || ![proxy respondsToSelector:selector]) {
        // NSXPCProxy may not advertise remote selectors using respondsToSelector.
        NSLog(@"ARGON_XPC NOTE proxy respondsToSelector=%d (remote selectors can be dynamic)",
              (int)[proxy respondsToSelector:selector]);
    }
    if (!proxy) {
        NSLog(@"ARGON_XPC FAIL proxy unavailable");
        NSLog(@"ARGON_XPC END result=no-proxy");
        [connection invalidate];
        MYArgonXPCConnection = nil;
        return;
    }
    void (^reply)(id) = ^(id descriptors) {
        if (completed) return;
        completed = YES;
        NSString *type = descriptors ? NSStringFromClass([descriptors class]) : @"nil";
        if (descriptors && [descriptors respondsToSelector:@selector(count)]) {
            NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(descriptors, @selector(count));
            NSLog(@"ARGON_XPC REPLY type=%@ count=%lu", type, (unsigned long)count);
        } else {
            NSLog(@"ARGON_XPC REPLY type=%@ count=unknown", type);
        }
        NSLog(@"ARGON_XPC END result=reply");
        [connection invalidate];
        if (MYArgonXPCConnection == connection) MYArgonXPCConnection = nil;
    };
    ((void (*)(id, SEL, id))objc_msgSend)(proxy, selector, reply);

    // Timeout prevents an XPC rejection from looking like an indefinitely running probe.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (sequence != MYArgonXPCSequence || completed) return;
        completed = YES;
        NSLog(@"ARGON_XPC TIMEOUT no reply/error after 12s (inconclusive)");
        NSLog(@"ARGON_XPC END result=timeout");
        [connection invalidate];
        if (MYArgonXPCConnection == connection) MYArgonXPCConnection = nil;
    });
}
