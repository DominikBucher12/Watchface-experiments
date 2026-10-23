#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <unistd.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

// CLOCKFACE_LAB_REMOTE_MANAGER_HOOK_V1
static IMP MYOriginalRemoteComplicationSharedInstance = NULL;

// CLOCKFACE_LAB_PROVIDER_INIT_PROBE_V1
// A/B: 0 = original system behavior; 1 = try creating real manager when original returns nil.
static id MYForcedRemoteComplicationManager = nil;
static id MYRemoteComplicationSharedInstanceHook(id cls, SEL cmd) {
    const char *mode = getenv("CLOCKFACE_LAB_FORCE_REMOTE_MANAGER");
    BOOL force = mode && strcmp(mode, "1") == 0;
    id (*original)(id, SEL) = (id (*)(id, SEL))MYOriginalRemoteComplicationSharedInstance;
    id existing = original ? original(cls, cmd) : nil;
    NSLog(@"CLOCKFACE_LAB PROVIDER_INIT sharedInstance original=%@ force=%d bundle=%@",
          existing ? NSStringFromClass([existing class]) : @"nil", (int)force,
          [NSBundle mainBundle].bundleIdentifier);
    if (existing || !force) return existing;
    @synchronized (cls) {
        if (!MYForcedRemoteComplicationManager) {
            NSLog(@"CLOCKFACE_LAB PROVIDER_INIT beginning alloc/init class=%@", NSStringFromClass(cls));
            @try {
                id candidate = [[cls alloc] init];
                if (candidate) {
                    MYForcedRemoteComplicationManager = candidate;
                    NSLog(@"CLOCKFACE_LAB PROVIDER_INIT created=%@", NSStringFromClass([candidate class]));
                } else {
                    NSLog(@"CLOCKFACE_LAB PROVIDER_INIT alloc/init returned nil");
                }
            } @catch (NSException *exception) {
                NSLog(@"CLOCKFACE_LAB PROVIDER_INIT exception=%@ reason=%@",
                      exception.name, exception.reason);
            }
        }
    }
    return MYForcedRemoteComplicationManager;
}

static void MYInstallRemoteComplicationHook(void) {
    Class cls = objc_getClass("NTKRemoteComplicationManager");
    if (!cls) {
        NSLog(@"CLOCKFACE_LAB REMOTE_MANAGER hook unavailable: class absent");
        return;
    }
    Method method = class_getClassMethod(cls, sel_registerName("sharedInstance"));
    if (!method) {
        NSLog(@"CLOCKFACE_LAB REMOTE_MANAGER hook unavailable: selector absent");
        return;
    }
    MYOriginalRemoteComplicationSharedInstance = method_setImplementation(
        method, (IMP)MYRemoteComplicationSharedInstanceHook);
    NSLog(@"CLOCKFACE_LAB REMOTE_MANAGER hook installed=%d forceEnv=%s",
          MYOriginalRemoteComplicationSharedInstance != NULL,
          getenv("CLOCKFACE_LAB_FORCE_REMOTE_MANAGER") ?: "0");
}
#import <objc/runtime.h>
#import <stdint.h>
// CLOCKFACE_LAB_SCENE_SELECTOR_SHIM_V1
// Diagnostic: do not imitate an unknown window context; record and ignore one setter call.
// Its argument is passed in x2 on arm64, whether the actual type is integer or pointer.
static void MYSceneSetMainWindowContextID(id receiver, SEL selector, uintptr_t rawContextID) {
    NSLog(@"CLOCKFACE_LAB SCENE_SELECTOR invoked receiver=%@ rawContextID=0x%llx",
          NSStringFromClass([receiver class]), (unsigned long long)rawContextID);
}
static void MYInstallSceneSelectorShim(void) {
    Class cls = objc_getClass("PUICMutableApplicationSceneClientSettings");
    SEL sel = sel_registerName("setMainWindowContextID:");
    if (!cls) {
        NSLog(@"CLOCKFACE_LAB SCENE_SELECTOR class missing");
        return;
    }
    if (class_getInstanceMethod(cls, sel)) {
        NSLog(@"CLOCKFACE_LAB SCENE_SELECTOR already implemented class=%@", NSStringFromClass(cls));
        return;
    }
    BOOL added = class_addMethod(cls, sel, (IMP)MYSceneSetMainWindowContextID, "v@:Q");
    NSLog(@"CLOCKFACE_LAB SCENE_SELECTOR installed=%d class=%@", (int)added, NSStringFromClass(cls));
}


// CLOCKFACE_LAB VISIBLE_INTEGRATION V2
// On watchOS, UIKit symbols exist privately at runtime but SDK marks UIView/UIWindow
// unavailable. Use ObjC runtime dispatch and attach to an EXISTING ClockFace window.
static id MYLabFaceBundle;
static id MYLabFace;
static id MYLabRenderedView;
static IMP MYLabOriginalLookup;
static NSString *const MYLabFaceBundleID = @"dev.develodom.WatchFaceLab.LocalFaceBundle";

static id MYLabSend0(id obj, const char *sel) {
    return obj ? ((id (*)(id, SEL))objc_msgSend)(obj,sel_registerName(sel)) : nil;
}
static id MYLabSend1(id obj, const char *sel, id arg) {
    return obj ? ((id (*)(id, SEL, id))objc_msgSend)(obj,sel_registerName(sel),arg) : nil;
}
static id MYLabBundleLookup(id self, SEL _cmd, id identifier, id device) {
    if ([identifier isKindOfClass:[NSString class]] &&
        [identifier isEqualToString:MYLabFaceBundleID] && MYLabFaceBundle) {
        NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION LOOKUP HIT id=%@", identifier);
        return MYLabFaceBundle;
    }
    return MYLabOriginalLookup ?
        ((id (*)(id, SEL, id, id))MYLabOriginalLookup)(self,_cmd,identifier,device) : nil;
}
static void MYLabShowAndIntegrate(void) {
    @try {
        NSString *path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"FaceBundles/MYLocalFaceBundle.bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        NSError *error = nil;
        BOOL loaded = bundle && [bundle loadAndReturnError:&error];
        NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION LOAD loaded=%d error=%@", loaded,error);
        if (!loaded) return;
        Class principal = [bundle principalClass];
        Class base = objc_lookUpClass("NTKFaceBundle");
        if (!principal || !base || ![principal isSubclassOfClass:base]) {
            NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION FAIL principal=%@",principal);
            return;
        }
        MYLabFaceBundle = [[principal alloc] init];
        Class managerClass = objc_lookUpClass("NTKFaceBundleManager");
        id manager = MYLabSend0((id)managerClass,"sharedManager");
        SEL lookupSel = sel_registerName("faceBundleForBundleIdentifier:onDevice:");
        Method method = manager ? class_getInstanceMethod([manager class],lookupSel) : NULL;
        if (method && method_getNumberOfArguments(method)==4 && !MYLabOriginalLookup) {
            MYLabOriginalLookup = method_setImplementation(method,(IMP)MYLabBundleLookup);
            NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION LOOKUP_HOOK installed=%d",MYLabOriginalLookup!=NULL);
        }
        id device = MYLabSend0((id)objc_lookUpClass("CLKDevice"),"currentDevice");
        if (!device) { NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION FAIL no device"); return; }
        id result = manager ? ((id (*)(id,SEL,id,id))objc_msgSend)(manager,lookupSel,MYLabFaceBundleID,device) : nil;
        NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION LOOKUP_RESULT class=%@ sameObject=%d",result ? NSStringFromClass([result class]) : @"nil",result==MYLabFaceBundle);
        id face = MYLabSend1(MYLabFaceBundle,"defaultFaceForDevice:",device);
        if (!face) { NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION FAIL no face"); return; }
        MYLabFace=face;
        id renderer = MYLabSend1((id)objc_lookUpClass("NTKFaceView"),"newFaceViewForFace:",face);
        NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION MODEL=%@ RENDERER=%@",NSStringFromClass([face class]), renderer ? NSStringFromClass([renderer class]) : @"nil");
        Class uiView = objc_lookUpClass("UIView");
        if (!uiView || !renderer || ![renderer isKindOfClass:uiView]) {
            NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION FAIL renderer is not UIView"); return;
        }
        id app = MYLabSend0((id)objc_lookUpClass("UIApplication"),"sharedApplication");
        id scenes = MYLabSend0(app,"connectedScenes");
        id hostWindow = nil;
        for (id scene in scenes) {
            if (![scene respondsToSelector:sel_registerName("windows")]) continue;
            for (id window in MYLabSend0(scene,"windows")) {
                if (!hostWindow) hostWindow = window;
                SEL keySel=sel_registerName("isKeyWindow");
                if ([window respondsToSelector:keySel] && ((BOOL (*)(id,SEL))objc_msgSend)(window,keySel)) {
                    hostWindow=window; break;
                }
            }
            if (hostWindow) break;
        }
        if (!hostWindow) { NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION FAIL no window scenes=%@",scenes); return; }
        id rootController = MYLabSend0(hostWindow,"rootViewController");
        id hostView = MYLabSend0(rootController,"view");
        if (!hostView) hostView=hostWindow;
        SEL boundsSel=sel_registerName("bounds");
        SEL frameSel=sel_registerName("setFrame:");
        CGRect bounds = ((CGRect (*)(id,SEL))objc_msgSend)(hostView,boundsSel);
        ((void (*)(id,SEL,CGRect))objc_msgSend)(renderer,frameSel,bounds);
        ((void (*)(id,SEL,id))objc_msgSend)(hostView,sel_registerName("addSubview:"),renderer);
        MYLabRenderedView=renderer;
        MYLabSend0(renderer,"setNeedsLayout");
        MYLabSend0(renderer,"layoutIfNeeded");
        NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION ATTACHED=1 host=%@ bounds=%@",NSStringFromClass([hostView class]),(NSString *)[NSString stringWithFormat:@"(%.1f, %.1f, %.1f, %.1f)", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height]);
    } @catch (NSException *e) {
        NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION EXCEPTION name=%@ reason=%@",e.name,e.reason);
    }
}

__attribute__((constructor)) static void MYClockFaceLabStart(void) {
    NSLog(@"CLOCKFACE_LAB BOOTSTRAP LOADED pid=%d", getpid());
    const char *privateLibraries[] = {
      "/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit",
      "/System/Library/PrivateFrameworks/ClockKitUI.framework/ClockKitUI"
    };
    for (int i = 0; i < 2; i++) {
        void *handle = dlopen(privateLibraries[i], RTLD_NOW | RTLD_GLOBAL);
        NSLog(@"CLOCKFACE_LAB PRIVATE path=%s loaded=%d error=%s", privateLibraries[i], handle != NULL, handle ? "none" : dlerror());
    }
    MYInstallRemoteComplicationHook();
    MYInstallSceneSelectorShim();
    NSString *frameworkPath = [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"MYCustomFaceExperiment.framework/MYCustomFaceExperiment"];
    void *handle = dlopen(frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    NSLog(@"CLOCKFACE_LAB EXPERIMENT loaded=%d error=%s", handle != NULL, handle ? "none" : dlerror());
    if (handle) {
        NSLog(@"CLOCKFACE_LAB ENTRYPOINT present=%d discovery=%d argon=%d xpc=%d",
            dlsym(handle, "MYPresentCustomFaceExperiment") != NULL,
            dlsym(handle, "MYDiscoverLocalFaceBundle") != NULL,
            dlsym(handle, "MYInspectArgonDescriptorsV3") != NULL,
            dlsym(handle, "MYProbeArgonReadOnlyXPC") != NULL);
        // CLOCKFACE_LAB ARGON_DISCOVERY_INVOKE V1
        void (*argonInspect)(void) =
            (void (*)(void))dlsym(handle, "MYInspectArgonDescriptorsV3");
        if (argonInspect) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    NSLog(@"CLOCKFACE_LAB ARGON_INVOKE BEGIN");
                    argonInspect();
                    NSLog(@"CLOCKFACE_LAB ARGON_INVOKE END");
                });
        } else {
            NSLog(@"CLOCKFACE_LAB ARGON_INVOKE MISSING_SYMBOL");
        }

        // CLOCKFACE_LAB ARGON_XPC_INVOKE V1
        void (*argonXPCProbe)(void) =
            (void (*)(void))dlsym(handle, "MYProbeArgonReadOnlyXPC");
        if (argonXPCProbe) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    NSLog(@"CLOCKFACE_LAB ARGON_XPC_INVOKE BEGIN");
                    argonXPCProbe();
                });
        }
        // CLOCKFACE_LAB NATIVE_GALLERY_INTEGRATION V1
        BOOL (*startGallery)(NSString *) = (BOOL (*)(NSString *))dlsym(handle, "MYStartNativeGalleryCollection");
        BOOL (*checkGallery)(void) = (BOOL (*)(void))dlsym(handle, "MYCheckNativeGalleryCollection");
        if (startGallery && checkGallery) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *faceDirectory = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"FaceBundles"];
                NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY BEGIN directory=%@", faceDirectory);
                @try {
                    BOOL started = startGallery(faceDirectory);
                    NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY STARTED=%d", started);
                    if (started) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            @try {
                                NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY RESULT=%d", checkGallery());
                            } @catch (NSException *e) {
                                NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY CHECK_EXCEPTION %@: %@", e.name, e.reason);
                            }
                        });
                    }
                } @catch (NSException *e) {
                    NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY START_EXCEPTION %@: %@", e.name, e.reason);
                }
            });
        } else {
            NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY MISSING_SYMBOL start=%d check=%d", startGallery != NULL, checkGallery != NULL);
        }


        // CLOCKFACE_LAB NATIVE_GALLERY_ABI_FIXED_V3
        // The exported function is BOOL MYStartNativeGalleryCollection(NSString *directoryPath).
        // Calling it as void (*)(void) causes objc_retain of a garbage argument and SIGSEGV.
        BOOL (*galleryStart)(NSString *) =
            (BOOL (*)(NSString *))dlsym(handle, "MYStartNativeGalleryCollection");
        BOOL (*galleryCheck)(void) =
            (BOOL (*)(void))dlsym(handle, "MYCheckNativeGalleryCollection");
        NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY ABI_V3 symbols start=%d check=%d",
              galleryStart != NULL, galleryCheck != NULL);
        if (galleryStart && galleryCheck) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                NSString *directory = [[[NSBundle mainBundle] bundlePath]
                    stringByAppendingPathComponent:@"FaceBundles"];
                @try {
                    NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY ABI_V3 START directory=%@", directory);
                    BOOL started = galleryStart(directory);
                    NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY ABI_V3 STARTED=%d", started);
                    if (started) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            @try {
                                BOOL result = galleryCheck();
                                NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY ABI_V3 RESULT=%d", result);
                            } @catch (NSException *e) {
                                NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY ABI_V3 CHECK_EXCEPTION %@: %@", e.name, e.reason);
                            }
                        });
                    }
                } @catch (NSException *e) {
                    NSLog(@"CLOCKFACE_LAB NATIVE_GALLERY ABI_V3 START_EXCEPTION %@: %@", e.name, e.reason);
                }
            });
        }

        // CLOCKFACE_LAB OWNED_BRIDGE_V1
        BOOL (*ownedStart)(NSString *) =
            (BOOL (*)(NSString *))dlsym(handle, "MYStartOwnedDiscoveryExperiment");
        BOOL (*ownedCheck)(void) =
            (BOOL (*)(void))dlsym(handle, "MYCheckOwnedDiscoveryExperiment");

        NSLog(@"CLOCKFACE_LAB OWNED_BRIDGE symbols start=%d check=%d",
              ownedStart != NULL, ownedCheck != NULL);

        if (ownedStart && ownedCheck) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    NSString *directory = [[[NSBundle mainBundle] bundlePath]
                        stringByAppendingPathComponent:@"FaceBundles"];

                    @try {
                        NSLog(@"CLOCKFACE_LAB OWNED_BRIDGE INSTALL directory=%@", directory);
                        BOOL installed = ownedStart(directory);
                        NSLog(@"CLOCKFACE_LAB OWNED_BRIDGE INSTALLED=%d", installed);

                        if (installed) {
                            dispatch_after(
                                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{
                                    @try {
                                        BOOL result = ownedCheck();
                                        NSLog(@"CLOCKFACE_LAB OWNED_BRIDGE RESULT=%d", result);
                                    } @catch (NSException *e) {
                                        NSLog(@"CLOCKFACE_LAB OWNED_BRIDGE CHECK_EXCEPTION %@: %@",
                                              e.name, e.reason);
                                    }
                                });
                        }
                    } @catch (NSException *e) {
                        NSLog(@"CLOCKFACE_LAB OWNED_BRIDGE INSTALL_EXCEPTION %@: %@",
                              e.name, e.reason);
                    }
                });
        }
        // CLOCKFACE_LAB MANAGER_PROBE V1
        // Observe the real ClockFace process after its initial application setup.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"CLOCKFACE_LAB MANAGER_PROBE BEGIN mainThread=%d", [NSThread isMainThread]);
            Class managerClass = objc_lookUpClass("NTKFaceBundleManager");
            SEL sharedSel = sel_registerName("sharedManager");
            if (!managerClass || ![(id)managerClass respondsToSelector:sharedSel]) {
                NSLog(@"CLOCKFACE_LAB MANAGER_PROBE FAIL manager class/sharedManager unavailable");
                return;
            }
            id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, sharedSel);
            NSLog(@"CLOCKFACE_LAB MANAGER_PROBE manager=%@", manager ? NSStringFromClass([manager class]) : @"nil");
            if (!manager) return;

            SEL lookupSel = sel_registerName("faceBundleForBundleIdentifier:onDevice:");
            BOOL hasLookup = [manager respondsToSelector:lookupSel];
            NSLog(@"CLOCKFACE_LAB MANAGER_PROBE lookupSelector=%d", hasLookup);
            if (!hasLookup) return;
            Method lookupMethod = class_getInstanceMethod([manager class], lookupSel);
            if (!lookupMethod || method_getNumberOfArguments(lookupMethod) != 4) {
                NSLog(@"CLOCKFACE_LAB MANAGER_PROBE FAIL unexpected lookup ABI");
                return;
            }

            Class deviceClass = objc_lookUpClass("CLKDevice");
            SEL currentSel = sel_registerName("currentDevice");
            if (!deviceClass || ![(id)deviceClass respondsToSelector:currentSel]) {
                NSLog(@"CLOCKFACE_LAB MANAGER_PROBE device unavailable; lookup not invoked");
                return;
            }
            id device = ((id (*)(id, SEL))objc_msgSend)((id)deviceClass, currentSel);
            if (!device) {
                NSLog(@"CLOCKFACE_LAB MANAGER_PROBE device=nil; lookup not invoked");
                return;
            }
            NSString *bundleID = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
            id faceBundle = ((id (*)(id, SEL, id, id))objc_msgSend)(manager, lookupSel, bundleID, device);
            NSLog(@"CLOCKFACE_LAB MANAGER_PROBE bundleID=%@ result=%@", bundleID, faceBundle ? NSStringFromClass([faceBundle class]) : @"nil");

            // CLOCKFACE_LAB DISCOVERY_AUDIT: inventory runtime discovery APIs and bundle placement.
            NSLog(@"CLOCKFACE_LAB DISCOVERY_AUDIT BEGIN");
            Class inspectClass = [manager class];
            for (int depth = 0; inspectClass && depth < 5; ++depth, inspectClass = class_getSuperclass(inspectClass)) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(inspectClass, &count);
                for (unsigned int i = 0; i < count; ++i) {
                    SEL sel = method_getName(methods[i]);
                    NSString *name = NSStringFromSelector(sel);
                    NSString *lower = [name lowercaseString];
                    if ([lower containsString:@"bundle"] || [lower containsString:@"loader"] ||
                        [lower containsString:@"registr"] || [lower containsString:@"director"] ||
                        [lower containsString:@"gallery"]) {
                        const char *encoding = method_getTypeEncoding(methods[i]);
                        NSLog(@"CLOCKFACE_LAB DISCOVERY_AUDIT method class=%@ selector=%@ encoding=%s", NSStringFromClass(inspectClass), name, encoding ? encoding : "?");
                    }
                }
                free(methods);
            }
            for (Class c = [manager class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
                unsigned int count = 0;
                Ivar *ivars = class_copyIvarList(c, &count);
                for (unsigned int i = 0; i < count; ++i) {
                    const char *name = ivar_getName(ivars[i]);
                    if (!name) continue;
                    NSString *lower = [[NSString stringWithUTF8String:name] lowercaseString];
                    if ([lower containsString:@"bundle"] || [lower containsString:@"loader"] ||
                        [lower containsString:@"director"]) {
                        NSLog(@"CLOCKFACE_LAB DISCOVERY_AUDIT ivar class=%@ name=%s type=%s", NSStringFromClass(c), name, ivar_getTypeEncoding(ivars[i]));
                    }
                }
                free(ivars);
            }
            NSString *bundlePath = [NSBundle mainBundle].bundlePath;
            NSArray<NSString *> *candidates = @[
                [bundlePath stringByAppendingPathComponent:@"MYLocalFaceBundle.bundle"],
                [[bundlePath stringByAppendingPathComponent:@"PlugIns"] stringByAppendingPathComponent:@"MYLocalFaceBundle.bundle"],
                [[bundlePath stringByAppendingPathComponent:@"Frameworks"] stringByAppendingPathComponent:@"MYLocalFaceBundle.bundle"],
                [bundlePath stringByAppendingPathComponent:@"FaceBundles/MYLocalFaceBundle.bundle"]
            ];
            for (NSString *path in candidates) {
                BOOL isDir = NO;
                BOOL found = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
                NSLog(@"CLOCKFACE_LAB DISCOVERY_AUDIT candidate=%@ exists=%d directory=%d", path, found, isDir);
            }
            NSLog(@"CLOCKFACE_LAB DISCOVERY_AUDIT END");

            // CLOCKFACE_LAB FACE_LOAD_TEST V2: direct NSBundle principalClass path.
            @try {
                NSString *dir = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"FaceBundles"];
                NSString *path = [dir stringByAppendingPathComponent:@"MYLocalFaceBundle.bundle"];
                NSBundle *disk = [NSBundle bundleWithPath:path];
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 BEGIN path=%@ bundleID=%@",path,disk.bundleIdentifier);
                if (!disk) { NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 FAIL missing bundle"); return; }
                NSError *err = nil;
                BOOL loaded = [disk loadAndReturnError:&err];
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 NSBundle loaded=%d error=%@",loaded,err);
                if (!loaded) return;
                Class principal = [disk principalClass];
                Class base = objc_lookUpClass("NTKFaceBundle");
                BOOL isFaceBundle = principal && base && [principal isSubclassOfClass:base];
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 principal=%@ NTKFaceBundle=%@ subclass=%d",
                      principal ? NSStringFromClass(principal) : @"nil",base ? NSStringFromClass(base) : @"nil",isFaceBundle);
                if (!isFaceBundle) return;
                SEL idSel = sel_registerName("identifier");
                SEL faceClassSel = sel_registerName("faceClass");
                SEL viewClassSel = sel_registerName("faceViewClass");
                SEL defaultSel = sel_registerName("defaultFaceForDevice:");
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 methods identifier=%d faceClass=%d viewClass=%d defaultFace=%d",
                      [(id)principal respondsToSelector:idSel], [principal instancesRespondToSelector:faceClassSel],
                      [principal instancesRespondToSelector:viewClassSel], [principal instancesRespondToSelector:defaultSel]);
                id obj = [[principal alloc] init];
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 object=%@",obj ? NSStringFromClass([obj class]) : @"nil");
                if (!obj) return;
                if ([principal respondsToSelector:idSel]) {
                    id ident = ((id (*)(id,SEL))objc_msgSend)((id)principal,idSel);
                    NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 identifier=%@",ident);
                }
                if ([obj respondsToSelector:faceClassSel] && [obj respondsToSelector:viewClassSel]) {
                    Class f = ((Class (*)(id,SEL))objc_msgSend)(obj,faceClassSel);
                    Class v = ((Class (*)(id,SEL))objc_msgSend)(obj,viewClassSel);
                    NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 faceClass=%@ viewClass=%@",
                          f ? NSStringFromClass(f) : @"nil",v ? NSStringFromClass(v) : @"nil");
                }
                if (![obj respondsToSelector:defaultSel]) return;
                id face = ((id (*)(id,SEL,id))objc_msgSend)(obj,defaultSel,device);
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 FACE=%@",face ? NSStringFromClass([face class]) : @"nil");
                if (!face) return;
                Class viewClass = objc_lookUpClass("NTKFaceView");
                SEL newSel = sel_registerName("newFaceViewForFace:");
                BOOL hasRendererFactory = viewClass && [(id)viewClass respondsToSelector:newSel];
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 rendererFactory=%d",hasRendererFactory);
                if (!hasRendererFactory) return;
                id view = ((id (*)(id,SEL,id))objc_msgSend)((id)viewClass,newSel,face);
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 RENDERER=%@",view ? NSStringFromClass([view class]) : @"nil");
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 %@",view ? @"PASS" : @"FAIL renderer nil");
            } @catch (NSException *e) {
                NSLog(@"CLOCKFACE_LAB FACE_LOAD_TEST V2 EXCEPTION name=%@ reason=%@",e.name,e.reason);
            }

            NSLog(@"CLOCKFACE_LAB MANAGER_PROBE END (read-only; no registration attempted)");
            // Render two seconds after the existing 3-second manager probe.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"CLOCKFACE_LAB VISIBLE_INTEGRATION BEGIN mainThread=%d", [NSThread isMainThread]);
                MYLabShowAndIntegrate();
            });

        });

        // Deliberately no face-manager mutation: first confirm code execution inside clone.
    }
}
