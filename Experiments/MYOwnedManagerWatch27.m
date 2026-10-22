// App-process-only NanoTimeKit manager lookup experiment for watchOS 27.0.1.
// Nothing is injected into ClockFace and nothing is persisted.
#import "NTKPrivateInterfaces.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <TargetConditionals.h>
#import <string.h>

#if !TARGET_OS_WATCH || TARGET_OS_SIMULATOR || !defined(__arm64__)
#error MYOwnedManagerWatch27 requires a physical arm64 watchOS target.
#endif

static NSString * const kLocalID = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
static NTKFaceBundleManager *gManager;
static NTKFaceBundle *gExtra;
static Class gOriginal;
static Class gTemporary;
static IMP gEnumIMP;
static IMP gLookupIMP;
static BOOL gActive;

typedef void (*EnumFn)(id,SEL,CLKDevice *,BOOL,void (^)(NTKFaceBundle *));
typedef NTKFaceBundle *(*LookupFn)(id,SEL,NSString *,CLKDevice *,BOOL);

static BOOL imageVerified(void) {
    const char *path = class_getImageName(objc_getClass("NTKFaceBundleManager"));
    if (!path) return NO;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        if (strcmp(path, _dyld_get_image_name(i))) continue;
        const struct mach_header_64 *h = (const void *)_dyld_get_image_header(i);
        if (h->magic != MH_MAGIC_64 || h->cputype != CPU_TYPE_ARM64) return NO;
        const struct load_command *p = (const void *)(h + 1);
        for (uint32_t j = 0; j < h->ncmds; ++j) {
            if (p->cmdsize < sizeof(*p)) return NO;
            if (p->cmd == LC_UUID && p->cmdsize >= sizeof(struct uuid_command)) {
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)p)->uuid];
                NSString *actual = uuid.UUIDString;
                NSLog(@"OWNED27 NanoTimeKit loaded UUID=%@", actual);
                // Both architectural UUIDs were inspected from watchOS 27.0.1 24R365.
                return [actual isEqualToString:@"4EB0531F-4C9E-343F-9A9A-04C66F69934C"] ||
                       [actual isEqualToString:@"EFE5A375-CC31-37EA-B3D0-CB0AC4486A36"];
            }
            p = (const void *)((const char *)p + p->cmdsize);
        }
    }
    return NO;
}

static void interceptedEnum(id self, SEL cmd, CLKDevice *device, BOOL legacy,
                             void (^block)(NTKFaceBundle *)) {
    if (!gActive || self != gManager || !block) {
        ((EnumFn)gEnumIMP)(self,cmd,device,legacy,block);
        return;
    }
    __block BOOL alreadyThere = NO;
    ((EnumFn)gEnumIMP)(self,cmd,device,legacy,^(NTKFaceBundle *bundle){
        if ([[bundle.class identifier] isEqualToString:kLocalID]) alreadyThere = YES;
        block(bundle);
    });
    if (!alreadyThere && ![[gExtra faceClass] isRestrictedForDevice:device]) block(gExtra);
}

static NTKFaceBundle *interceptedLookup(id self, SEL cmd, NSString *identifier,
                                        CLKDevice *device, BOOL migration) {
    if (gActive && self == gManager && [identifier isEqualToString:kLocalID]) {
        return (migration || ![[gExtra faceClass] isRestrictedForDevice:device]) ? gExtra : nil;
    }
    return ((LookupFn)gLookupIMP)(self,cmd,identifier,device,migration);
}

__attribute__((visibility("default"))) void MYTestOwnedManagerWatch27(void) {
    NSLog(@"OWNED27 BEGIN");
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"] ||
        !imageVerified()) {
        NSLog(@"OWNED27 SKIP: host, thread or NanoTimeKit UUID mismatch");
        return;
    }

    Class base = objc_getClass("NTKFaceBundleManager");
    Class loaderClass = objc_getClass("NTKFaceBundleLoader");
    Method e = class_getInstanceMethod(base, @selector(enumerateFaceBundlesOnDevice:includingLegacy:withBlock:));
    Method l = class_getInstanceMethod(base, @selector(faceBundleForBundleIdentifier:onDevice:forMigration:));
    Method factory = class_getClassMethod(loaderClass, @selector(faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:));
    const char *et = e ? method_getTypeEncoding(e) : "MISSING";
    const char *lt = l ? method_getTypeEncoding(l) : "MISSING";
    NSLog(@"OWNED27 encoding enum=%s lookup=%s", et, lt);
    if (!e || !l || !factory || strcmp(et,"v36@0:8@16B24@?28") ||
        strcmp(lt,"@36@0:8@16@24B32")) {
        NSLog(@"OWNED27 SKIP: unverified selector ABI");
        return;
    }

    @try {
        NSURL *container = [NSBundle mainBundle].bundleURL;
        NSURL *bundleURL = [container URLByAppendingPathComponent:@"MYLocalFaceBundle.bundle" isDirectory:YES];
        NSBundle *disk = [NSBundle bundleWithURL:bundleURL];
        if (![[disk bundleIdentifier] isEqualToString:kLocalID]) {
            NSLog(@"OWNED27 FAIL: local bundle missing or invalid");
            return;
        }
        id loader = [(id)loaderClass faceBundleLoaderWithDirectories:[NSSet setWithObject:container]
                                       appBundleIdentifierPrefixes:[NSSet setWithObject:@"dev.develodom.WatchFaceLab"]];
        NTKFaceBundle *extra = [loader loadFaceBundleWithIdentifier:kLocalID];
        if (!extra || ![[extra.class identifier] isEqualToString:kLocalID]) {
            NSLog(@"OWNED27 FAIL: local loader did not return expected bundle");
            return;
        }
        gManager = [(id)base sharedManager];
        CLKDevice *device = [CLKDevice currentDevice];
        if (!gManager || !device || object_getClass(gManager) != base || gActive) {
            NSLog(@"OWNED27 SKIP: manager state not suitable");
            return;
        }
        NTKFaceBundle *before = [gManager faceBundleForBundleIdentifier:kLocalID onDevice:device forMigration:NO];
        if (before) {
            NSLog(@"OWNED27 SKIP: identifier already exists in manager");
            return;
        }
        gEnumIMP = method_getImplementation(e);
        gLookupIMP = method_getImplementation(l);
        gOriginal = base;
        gExtra = extra;
        gTemporary = objc_allocateClassPair(base, "MYWatch27OwnedManagerEphemeral", 0);
        if (!gTemporary) {
            NSLog(@"OWNED27 FAIL: cannot allocate temporary subclass (already used?)");
            return;
        }
        if (!class_addMethod(gTemporary, method_getName(e), (IMP)interceptedEnum, et) ||
            !class_addMethod(gTemporary, method_getName(l), (IMP)interceptedLookup, lt)) {
            objc_disposeClassPair(gTemporary);
            gTemporary = Nil;
            NSLog(@"OWNED27 FAIL: method registration");
            return;
        }
        objc_registerClassPair(gTemporary);
        if (class_getInstanceSize(base) != class_getInstanceSize(gTemporary)) {
            NSLog(@"OWNED27 FAIL: instance size mismatch");
            return;
        }
        @try {
            gActive = YES;
            object_setClass(gManager, gTemporary);
            NTKFaceBundle *found = [gManager faceBundleForBundleIdentifier:kLocalID onDevice:device forMigration:NO];
            __block NSUInteger matches = 0;
            [gManager enumerateFaceBundlesOnDevice:device includingLegacy:YES withBlock:^(NTKFaceBundle *bundle) {
                if ([[bundle.class identifier] isEqualToString:kLocalID]) matches++;
            }];
            NSLog(@"OWNED27 RESULT lookup=%d enumerated=%lu PASS=%d",
                  found == extra, (unsigned long)matches, found == extra && matches == 1);
        } @finally {
            if (object_getClass(gManager) == gTemporary) object_setClass(gManager, gOriginal);
            gActive = NO;
            NTKFaceBundle *after = [gManager faceBundleForBundleIdentifier:kLocalID onDevice:device forMigration:NO];
            NSLog(@"OWNED27 RESTORED class=%d absent=%d", object_getClass(gManager)==gOriginal, after==nil);
            gExtra = nil;
        }
    } @catch (NSException *ex) {
        NSLog(@"OWNED27 EXCEPTION name=%@ reason=%@", ex.name, ex.reason);
        if (gActive && gManager && object_getClass(gManager) == gTemporary)
            object_setClass(gManager, gOriginal);
        gActive = NO;
        gExtra = nil;
    }
    NSLog(@"OWNED27 END");
}
