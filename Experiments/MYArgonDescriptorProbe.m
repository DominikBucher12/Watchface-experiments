#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Explicitly enumerates descriptors from the app process's NTKFaceBundleManager.
// Never prints keys, file names, JSON, URLs, or descriptor descriptions.
// No calls to loadKeyDescriptor:, argonUpdated:, or extraction APIs.
__attribute__((visibility("default"))) void MYInspectArgonDescriptors(void) {
    NSLog(@"ARGON_DESCRIPTOR BEGIN");
    Class managerClass = objc_lookUpClass("NTKFaceBundleManager");
    SEL sharedSel = sel_registerName("sharedManager");
    SEL enumerateSel = sel_registerName("enumerateArgonKeyDescriptorsWithBlock:");
    if (!managerClass || !class_respondsToSelector(object_getClass(managerClass), sharedSel) ||
        !class_getInstanceMethod(managerClass, enumerateSel)) {
        NSLog(@"ARGON_DESCRIPTOR unavailable manager or selectors");
        NSLog(@"ARGON_DESCRIPTOR END");
        return;
    }
    // Verified on watchOS 27.0.1: +sharedManager @16@0:8,
    // -enumerateArgonKeyDescriptorsWithBlock: v24@0:8@?16.
    Method enumerateMethod = class_getInstanceMethod(managerClass, enumerateSel);
    const char *actualEncoding = method_getTypeEncoding(enumerateMethod);
    if (!actualEncoding || strcmp(actualEncoding, "v24@0:8@?16") != 0) {
        NSLog(@"ARGON_DESCRIPTOR unsupported enumeration ABI, refusing invocation");
        NSLog(@"ARGON_DESCRIPTOR END");
        return;
    }
    @try {
        id (*getManager)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        id manager = getManager((id)managerClass, sharedSel);
        if (!manager || ![manager isKindOfClass:managerClass]) {
            NSLog(@"ARGON_DESCRIPTOR sharedManager unavailable");
            NSLog(@"ARGON_DESCRIPTOR END");
            return;
        }
        __block NSUInteger count = 0;
        __block NSMutableDictionary<NSString *, NSNumber *> *types = [NSMutableDictionary dictionary];
        // Only use the first block argument. Any additional callback args are ignored.
        void (^visitor)(id) = ^(id descriptor) {
            count++;
            NSString *type = descriptor ? NSStringFromClass([descriptor class]) : @"nil";
            types[type] = @([types[type] unsignedIntegerValue] + 1);
        };
        void (*enumerate)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        enumerate(manager, enumerateSel, visitor);
        NSLog(@"ARGON_DESCRIPTOR completed count=%lu", (unsigned long)count);
        for (NSString *type in [[types allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSLog(@"ARGON_DESCRIPTOR descriptorClass=%@ count=%@", type, types[type]);
        }
    } @catch (NSException *exception) {
        NSLog(@"ARGON_DESCRIPTOR exception name=%@ (details withheld)", exception.name);
    }
    NSLog(@"ARGON_DESCRIPTOR END");
}
