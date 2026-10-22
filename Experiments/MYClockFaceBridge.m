// Opt-in preparation only. No constructors, automatic hooks, or persistent writes.
#import "NTKPrivateInterfaces.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <TargetConditionals.h>
#import <string.h>

#if !TARGET_OS_WATCH || TARGET_OS_SIMULATOR || !defined(__arm64__)
#error This bridge targets arm64 physical watchOS devices only.
#endif

// IMPORTANT: This hook was reverse engineered on watchOS 26.5 simulator.
// Refuse all hooking on watchOS 27 until the exact image UUID AND method
// encodings have been independently verified on the target device.
// Supply -DMY_VERIFIED_NTK_UUID=\"UUID\" only after validation.
#ifndef MY_VERIFIED_NTK_UUID
#define MY_VERIFIED_NTK_UUID "UNVERIFIED-WATCHOS27"
#endif

#ifndef MY_BRIDGE_HOST_IDENTIFIER
#define MY_BRIDGE_HOST_IDENTIFIER @"com.apple.clockface"
#endif
#ifndef MY_BRIDGE_CLASS_NAME
#define MY_BRIDGE_CLASS_NAME "MYClockFaceSessionBundleManager"
#endif

static NSString *const MYIdentifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
static NTKFaceBundleManager *MYManager;
static NTKFaceBundle *MYBundle;
static Class MYOriginalClass;
static Class MYBridgeClass;
static BOOL MYEnabled;
typedef void (*MYEnumerateIMP)(id, SEL, CLKDevice *, BOOL, void (^)(NTKFaceBundle *));
typedef NTKFaceBundle *(*MYLookupIMP)(id, SEL, NSString *, CLKDevice *, BOOL);
static MYEnumerateIMP MYOriginalEnumerate;
static MYLookupIMP MYOriginalLookup;

static BOOL MYExpectedImage(void) {
    if (strcmp(MY_VERIFIED_NTK_UUID, "UNVERIFIED-WATCHOS27") == 0) return NO;
    const char *path = class_getImageName(NTKFaceBundleManager.class);
    if (!path) return NO;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strcmp(path, _dyld_get_image_name(i)) != 0) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) return NO;
        const struct load_command *command = (const void *)(header + 1);
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if (command->cmdsize < sizeof(*command)) return NO;
            if (command->cmd == LC_UUID) {
                if (command->cmdsize < sizeof(struct uuid_command)) return NO;
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid];
                return [uuid.UUIDString isEqualToString:[NSString stringWithUTF8String:MY_VERIFIED_NTK_UUID]];
            }
            command = (const void *)((const char *)command + command->cmdsize);
        }
    }
    return NO;
}

static BOOL MYContext(void) {
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:MY_BRIDGE_HOST_IDENTIFIER] ||
        !MYExpectedImage()) {
        NSLog(@"ClockFace bridge: rejected host/thread/runtime identity");
        return NO;
    }
    return YES;
}

static BOOL MYMethodsMatch(Class cls) {
    Method enumerate = class_getInstanceMethod(cls,
        @selector(enumerateFaceBundlesOnDevice:includingLegacy:withBlock:));
    Method lookup = class_getInstanceMethod(cls,
        @selector(faceBundleForBundleIdentifier:onDevice:forMigration:));
    return enumerate && lookup &&
        strcmp(method_getTypeEncoding(enumerate), "v36@0:8@16B24@?28") == 0 &&
        strcmp(method_getTypeEncoding(lookup), "@36@0:8@16@24B32") == 0;
}

static void MYEnumerate(id self, SEL selector, CLKDevice *device, BOOL legacy,
                        void (^block)(NTKFaceBundle *)) {
    NTKFaceBundle *extra = nil;
    @synchronized(MYManager) {
        if (MYEnabled && self == MYManager) extra = MYBundle;
    }
    if (!extra || !block) {
        MYOriginalEnumerate(self, selector, device, legacy, block);
        return;
    }
    __block BOOL seen = NO;
    MYOriginalEnumerate(self, selector, device, legacy, ^(NTKFaceBundle *bundle) {
        if ([[bundle.class identifier] isEqualToString:MYIdentifier]) seen = YES;
        block(bundle);
    });
    if (!seen && ![[extra faceClass] isRestrictedForDevice:device]) block(extra);
}

static NTKFaceBundle *MYLookup(id self, SEL selector, NSString *identifier,
                              CLKDevice *device, BOOL migration) {
    NTKFaceBundle *extra = nil;
    @synchronized(MYManager) {
        if (MYEnabled && self == MYManager && [identifier isEqualToString:MYIdentifier]) extra = MYBundle;
    }
    if (extra) return (migration || ![[extra faceClass] isRestrictedForDevice:device]) ? extra : nil;
    return MYOriginalLookup(self, selector, identifier, device, migration);
}

BOOL MYClockFaceBridgePreflight(void) {
    if (!MYContext()) return NO;
    NTKFaceBundleManager *manager = [NTKFaceBundleManager sharedManager];
    Class cls = object_getClass(manager);
    BOOL valid = cls == NTKFaceBundleManager.class && MYMethodsMatch(cls);
    NSLog(@"ClockFace bridge preflight: managerClass=%@ methodsMatch=%d; no interception installed",
          NSStringFromClass(cls), valid);
    return valid;
}

BOOL MYClockFaceBridgeInstall(NSString *directoryPath) {
    if (!MYContext() || MYEnabled || !MYClockFaceBridgePreflight()) return NO;
    if (directoryPath.length == 0 || !directoryPath.isAbsolutePath) return NO;
    NSURL *url = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    NSURL *bundleURL = [url URLByAppendingPathComponent:@"MYLocalFaceBundle.bundle"];
    NSBundle *diskBundle = [NSBundle bundleWithURL:bundleURL];
    if (![diskBundle.bundleIdentifier isEqualToString:MYIdentifier]) return NO;
    NTKFaceBundleLoader *loader = [NTKFaceBundleLoader faceBundleLoaderWithDirectories:
                                  [NSSet setWithObject:url]];
    NTKFaceBundle *bundle = [loader loadFaceBundleWithIdentifier:MYIdentifier];
    if (!bundle || ![NSStringFromClass(bundle.class) isEqualToString:@"MYLocalFaceBundle"] ||
        ![[bundle.class identifier] isEqualToString:MYIdentifier] ||
        ![[NSBundle bundleForClass:bundle.class].bundleURL.URLByResolvingSymlinksInPath.path
          isEqualToString:bundleURL.URLByResolvingSymlinksInPath.path]) return NO;
    NTKFaceBundleManager *manager = [NTKFaceBundleManager sharedManager];
    Class original = object_getClass(manager);
    if (original != NTKFaceBundleManager.class || !MYMethodsMatch(original)) return NO;
    Method enumerate = class_getInstanceMethod(original,
        @selector(enumerateFaceBundlesOnDevice:includingLegacy:withBlock:));
    Method lookup = class_getInstanceMethod(original,
        @selector(faceBundleForBundleIdentifier:onDevice:forMigration:));
    if (!MYBridgeClass) {
        if (objc_lookUpClass(MY_BRIDGE_CLASS_NAME)) return NO;
        Class bridge = objc_allocateClassPair(original, MY_BRIDGE_CLASS_NAME, 0);
        if (!bridge) return NO;
        if (!class_addMethod(bridge, method_getName(enumerate), (IMP)MYEnumerate, method_getTypeEncoding(enumerate)) ||
            !class_addMethod(bridge, method_getName(lookup), (IMP)MYLookup, method_getTypeEncoding(lookup))) {
            objc_disposeClassPair(bridge);
            return NO;
        }
        objc_registerClassPair(bridge);
        MYBridgeClass = bridge;
    }
    if (class_getInstanceSize(original) != class_getInstanceSize(MYBridgeClass)) return NO;
    MYOriginalEnumerate = (MYEnumerateIMP)method_getImplementation(enumerate);
    MYOriginalLookup = (MYLookupIMP)method_getImplementation(lookup);
    MYManager = manager;
    MYOriginalClass = original;
    @synchronized(manager) {
        MYBundle = bundle;
        MYEnabled = YES;
        object_setClass(manager, MYBridgeClass);
    }
    NSLog(@"ClockFace bridge INSTALLED: one manager instance; original discovery forwarded; no manager caches edited");
    return YES;
}

BOOL MYClockFaceBridgeCheck(void) {
    if (!MYContext() || !MYEnabled || object_getClass(MYManager) != MYBridgeClass) return NO;
    CLKDevice *device = [CLKDevice currentDevice];
    if (!device) return NO;
    __block NSUInteger matches = 0;
    [MYManager enumerateFaceBundlesOnDevice:device includingLegacy:YES withBlock:^(NTKFaceBundle *bundle) {
        if ([[bundle.class identifier] isEqualToString:MYIdentifier]) matches++;
    }];
    NTKFaceBundle *found = [MYManager faceBundleForBundleIdentifier:MYIdentifier onDevice:device forMigration:NO];
    BOOL valid = matches == 1 && found == MYBundle;
    NSLog(@"ClockFace bridge CHECK: matches=%lu identifierLookupMatches=%d success=%d",
          (unsigned long)matches, found == MYBundle, valid);
    return valid;
}

BOOL MYClockFaceBridgeRemove(void) {
    if (!MYContext() || !MYEnabled) return NO;
    @synchronized(MYManager) {
        if (object_getClass(MYManager) != MYBridgeClass) {
            NSLog(@"ClockFace bridge: class changed by another component; refusing to overwrite it; restart process");
            return NO;
        }
        object_setClass(MYManager, MYOriginalClass);
        MYEnabled = NO;
        MYBundle = nil;
    }
    BOOL restored = object_getClass(MYManager) == MYOriginalClass;
    NSLog(@"ClockFace bridge REMOVED: original manager class restored=%d; loaded images remain until exit", restored);
    return restored;
}
