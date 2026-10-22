#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// For watchOS 27.0.1 (24R365) only. Diagnostic; does not register anything.
// Verified from device NanoTimeKit disassembly at 0x12a6a4-0x12a6b0:
// enumeration invokes block with NSUInteger group/style and id descriptor.
__attribute__((visibility("default"))) void MYInspectArgonDescriptors(void) {
    NSLog(@"ARGON_DESCRIPTOR_V2 BEGIN");
    Class cls = objc_lookUpClass("NTKFaceBundleManager");
    SEL shared = @selector(sharedManager);
    SEL enumerate = sel_registerName("enumerateArgonKeyDescriptorsWithBlock:");
    Method m = cls ? class_getInstanceMethod(cls, enumerate) : NULL;
    if (!cls || !class_respondsToSelector(object_getClass(cls), shared) ||
        !m || strcmp(method_getTypeEncoding(m), "v24@0:8@?16") != 0) {
        NSLog(@"ARGON_DESCRIPTOR_V2 SKIP selector or ABI mismatch");
        NSLog(@"ARGON_DESCRIPTOR_V2 END");
        return;
    }
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
        if (!manager || ![manager isKindOfClass:cls]) {
            NSLog(@"ARGON_DESCRIPTOR_V2 SKIP no shared manager");
            NSLog(@"ARGON_DESCRIPTOR_V2 END");
            return;
        }
        __block NSUInteger count = 0;
        __block NSMutableDictionary<NSString *, NSNumber *> *types = [NSMutableDictionary dictionary];
        void (^visitor)(NSUInteger, id) = ^(NSUInteger group, id descriptor) {
            (void)group; // do not print internal keys or identifiers
            count++;
            NSString *name = descriptor ? NSStringFromClass([descriptor class]) : @"nil";
            types[name] = @([types[name] unsignedIntegerValue] + 1);
        };
        ((void (*)(id, SEL, id))objc_msgSend)(manager, enumerate, visitor);
        NSLog(@"ARGON_DESCRIPTOR_V2 completed count=%lu", (unsigned long)count);
        for (NSString *name in [[types allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSLog(@"ARGON_DESCRIPTOR_V2 class=%@ count=%@", name, types[name]);
        }
    } @catch (NSException *e) {
        NSLog(@"ARGON_DESCRIPTOR_V2 exception=%@", e.name);
    }
    NSLog(@"ARGON_DESCRIPTOR_V2 END");
}
