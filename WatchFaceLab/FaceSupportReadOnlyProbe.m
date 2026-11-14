#include "FaceSupportReadOnlyProbe.h"

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <errno.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static NSString *const kFaceSupportService =
    @"com.apple.nanotimekit.facesupportserver";
static NSXPCConnection *gFaceSupportConnection = nil;
static void *gNanoTimeKitHandle = NULL;
static NSUInteger gFaceSupportSequence = 0;

typedef int (*sandbox_check_fn)(pid_t, const char *, int, ...);
typedef NSXPCInterface *(*interface_factory_fn)(void);

int32_t
watchfacelab_facesupport_readonly_probe_run(void)
{
    if (gFaceSupportConnection != nil) {
        printf("[facesupport-readonly] result=already-running\n");
        return 2;
    }

    sandbox_check_fn sandbox_check_dynamic =
        (sandbox_check_fn)dlsym(RTLD_DEFAULT, "sandbox_check");
    if (sandbox_check_dynamic == NULL) {
        printf("[facesupport-readonly] sandbox-api=0 request-sent=0\n");
        return 3;
    }
    errno = 0;
    int sandbox_result = sandbox_check_dynamic(
        getpid(), "mach-lookup", 2, kFaceSupportService.UTF8String);
    int saved_errno = errno;
    printf("[facesupport-readonly] sandbox-api=1 raw=%d allowed=%d denied=%d errno=%d\n",
           sandbox_result, sandbox_result == 0, sandbox_result > 0, saved_errno);
    if (sandbox_result != 0) {
        printf("[facesupport-readonly] result=mach-lookup-denied request-sent=0\n");
        return 1;
    }

    if (gNanoTimeKitHandle == NULL) {
        gNanoTimeKitHandle = dlopen(
            "/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit",
            RTLD_NOW | RTLD_LOCAL);
    }
    if (gNanoTimeKitHandle == NULL) {
        printf("[facesupport-readonly] result=framework-unavailable request-sent=0\n");
        return 4;
    }
    interface_factory_fn factory = (interface_factory_fn)dlsym(
        gNanoTimeKitHandle, "NTKFaceSupportServerInterface");
    if (factory == NULL) {
        printf("[facesupport-readonly] result=interface-symbol-missing request-sent=0\n");
        return 5;
    }
    NSXPCInterface *interface = factory();
    if (interface == nil) {
        printf("[facesupport-readonly] result=interface-nil request-sent=0\n");
        return 6;
    }

    SEL initializer = sel_registerName("initWithMachServiceName:options:");
    if (![NSXPCConnection instancesRespondToSelector:initializer]) {
        printf("[facesupport-readonly] result=initializer-missing request-sent=0\n");
        return 7;
    }
    NSXPCConnection *connection =
        ((id (*)(id, SEL, NSString *, NSUInteger))objc_msgSend)(
            [NSXPCConnection alloc], initializer, kFaceSupportService,
            (NSUInteger)0x1000);
    if (connection == nil) {
        printf("[facesupport-readonly] result=connection-nil request-sent=0\n");
        return 8;
    }

    gFaceSupportConnection = connection;
    NSUInteger sequence = ++gFaceSupportSequence;
    __block BOOL completed = NO;
    connection.remoteObjectInterface = interface;
    connection.interruptionHandler = ^{
        printf("[facesupport-readonly] interrupted=1\n");
    };
    connection.invalidationHandler = ^{
        printf("[facesupport-readonly] invalidated=1\n");
    };
    [connection resume];

    id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        if (completed) {
            return;
        }
        completed = YES;
        printf("[facesupport-readonly] reply=error domain=%s code=%ld\n",
               error.domain.UTF8String ?: "nil", (long)error.code);
        [connection invalidate];
        if (gFaceSupportConnection == connection) {
            gFaceSupportConnection = nil;
        }
    }];
    if (proxy == nil) {
        printf("[facesupport-readonly] result=proxy-nil request-sent=0\n");
        [connection invalidate];
        gFaceSupportConnection = nil;
        return 9;
    }

    SEL selector = sel_registerName("knownKeyDescriptors:");
    void (^reply)(id) = ^(id descriptors) {
        if (completed) {
            return;
        }
        completed = YES;
        NSUInteger count = [descriptors respondsToSelector:@selector(count)] ?
            ((NSUInteger (*)(id, SEL))objc_msgSend)(descriptors, @selector(count)) : 0;
        printf("[facesupport-readonly] reply=success type=%s count=%lu\n",
               descriptors == nil ? "nil" :
                   NSStringFromClass([descriptors class]).UTF8String,
               (unsigned long)count);
        [connection invalidate];
        if (gFaceSupportConnection == connection) {
            gFaceSupportConnection = nil;
        }
    };
    ((void (*)(id, SEL, id))objc_msgSend)(proxy, selector, reply);
    printf("[facesupport-readonly] result=request-queued request-sent=1\n");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (sequence != gFaceSupportSequence || completed) {
            return;
        }
        completed = YES;
        printf("[facesupport-readonly] reply=timeout\n");
        [connection invalidate];
        if (gFaceSupportConnection == connection) {
            gFaceSupportConnection = nil;
        }
    });
    return 0;
}
