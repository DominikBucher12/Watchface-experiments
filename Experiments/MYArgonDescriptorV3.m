#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Read-only validation of synthetic local Argon metadata; no server access or ingestion.
static void MYArgonLocalParserTest(void) {
    NSLog(@"ARGON_LOCAL BEGIN");
    @try {
        Class descriptorClass = objc_lookUpClass("NTKArgonKeyDescriptor");
        SEL parse = sel_registerName("keyDescriptorFromBundle:");
        SEL filename = sel_registerName("fileName");
        Method parserMethod = descriptorClass ? class_getClassMethod(descriptorClass, parse) : NULL;
        Method filenameMethod = descriptorClass ? class_getInstanceMethod(descriptorClass, filename) : NULL;
        if (!parserMethod || !filenameMethod ||
            strcmp(method_getTypeEncoding(parserMethod), "@24@0:8@16") != 0 ||
            strcmp(method_getTypeEncoding(filenameMethod), "@16@0:8") != 0) {
            NSLog(@"ARGON_LOCAL SKIP unexpected descriptor ABI parser=%s filename=%s",
                  parserMethod ? method_getTypeEncoding(parserMethod) : "absent",
                  filenameMethod ? method_getTypeEncoding(filenameMethod) : "absent");
            NSLog(@"ARGON_LOCAL END");
            return;
        }
        NSBundle *bundle = nil;
        Class localClass = objc_lookUpClass("MYLocalFaceBundle");
        if (localClass) bundle = [NSBundle bundleForClass:localClass];
        if (![[bundle.bundleIdentifier lowercaseString] isEqualToString:@"dev.develodom.watchfacelab.localfacebundle"]) {
            bundle = nil;
        }
        if (!bundle) {
            // Search only our own application container, never /var/mobile/Library/NanoTimeKit.
            NSDirectoryEnumerator<NSURL *> *files = [[NSFileManager defaultManager]
                enumeratorAtURL:[NSURL fileURLWithPath:[NSBundle mainBundle].bundlePath]
                includingPropertiesForKeys:nil options:0 errorHandler:nil];
            for (NSURL *url in files) {
                if ([[url lastPathComponent] isEqualToString:@"MYLocalFaceBundle.bundle"]) {
                    NSBundle *candidate = [NSBundle bundleWithURL:url];
                    if ([candidate.bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab.LocalFaceBundle"]) {
                        bundle = candidate;
                        break;
                    }
                }
            }
        }
        if (!bundle) {
            NSLog(@"ARGON_LOCAL SKIP local face bundle not found in application container");
            NSLog(@"ARGON_LOCAL END");
            return;
        }
        id argon = bundle.infoDictionary[@"Argon"];
        BOOL metadataOK = [argon isKindOfClass:[NSDictionary class]] &&
            [argon[@"FileName"] isEqualToString:@"WatchFaceLab-Test.aea"] &&
            [argon[@"Key"] isEqualToString:@"WatchFaceLab-Test-NotARealKey"];
        NSLog(@"ARGON_LOCAL metadata=%@ bundle=%@", metadataOK ? @"PASS" : @"FAIL", bundle.bundleIdentifier);
        if (!metadataOK) {
            NSLog(@"ARGON_LOCAL END");
            return;
        }
        id descriptor = ((id (*)(id, SEL, id))objc_msgSend)((id)descriptorClass, parse, bundle);
        if (!descriptor || ![descriptor isKindOfClass:descriptorClass]) {
            NSLog(@"ARGON_LOCAL parser=FAIL descriptor=nil-or-invalid");
        } else {
            id value = ((id (*)(id, SEL))objc_msgSend)(descriptor, filename);
            NSLog(@"ARGON_LOCAL parser=%@ class=%@ filename=%@",
                  [value isEqualToString:@"WatchFaceLab-Test.aea"] ? @"PASS" : @"FAIL",
                  NSStringFromClass([descriptor class]),
                  [value isKindOfClass:[NSString class]] ? value : @"<invalid>");
        }
    } @catch (NSException *exception) {
        NSLog(@"ARGON_LOCAL exception=%@", exception.name);
    }
    NSLog(@"ARGON_LOCAL END");
}

// watchOS 27.0.1 24R365. Read-only: no extraction, XPC requests or database mutation.
// Isolated, read-only local bundle discovery. Never touches the shared manager.
static void MYArgonDiscoveryV1(void) {
    NSLog(@"ARGON_DISCOVERY BEGIN");
    @try {
        NSString *expected = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
        NSURL *root = [NSBundle mainBundle].bundleURL;
        NSBundle *local = [NSBundle bundleWithURL:[root URLByAppendingPathComponent:@"MYLocalFaceBundle.bundle" isDirectory:YES]];
        if (![local.bundleIdentifier isEqualToString:expected]) {
            NSLog(@"ARGON_DISCOVERY SKIP local bundle missing at app root");
            NSLog(@"ARGON_DISCOVERY END");
            return;
        }
        Class loaderClass = objc_lookUpClass("NTKFaceBundleLoader");
        Class descriptorClass = objc_lookUpClass("NTKArgonKeyDescriptor");
        SEL make = sel_registerName("faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:");
        SEL enumerate = sel_registerName("enumerateFaceBundleClassesIgnoringCache:withBlock:");
        SEL parser = sel_registerName("keyDescriptorFromBundle:");
        SEL filename = sel_registerName("fileName");
        Method factoryMethod = loaderClass ? class_getClassMethod(loaderClass, make) : NULL;
        Method enumMethod = loaderClass ? class_getInstanceMethod(loaderClass, enumerate) : NULL;
        Method parserMethod = descriptorClass ? class_getClassMethod(descriptorClass, parser) : NULL;
        Method filenameMethod = descriptorClass ? class_getInstanceMethod(descriptorClass, filename) : NULL;
        const char *factoryABI = factoryMethod ? method_getTypeEncoding(factoryMethod) : "missing";
        const char *enumABI = enumMethod ? method_getTypeEncoding(enumMethod) : "missing";
        NSLog(@"ARGON_DISCOVERY ABI factory=%s enumerate=%s", factoryABI, enumABI);
        if (!factoryMethod || !enumMethod || !parserMethod || !filenameMethod ||
            strcmp(factoryABI, "@32@0:8@16@24") != 0 ||
            strcmp(enumABI, "v28@0:8B16@?20") != 0 ||
            strcmp(method_getTypeEncoding(parserMethod), "@24@0:8@16") != 0 ||
            strcmp(method_getTypeEncoding(filenameMethod), "@16@0:8") != 0) {
            NSLog(@"ARGON_DISCOVERY SKIP unexpected ABI (send this log)");
            NSLog(@"ARGON_DISCOVERY END");
            return;
        }
        id loader = ((id (*)(id, SEL, id, id))objc_msgSend)((id)loaderClass, make,
              [NSSet setWithObject:root], [NSSet setWithObject:@"dev.develodom.WatchFaceLab"]);
        if (!loader) {
            NSLog(@"ARGON_DISCOVERY FAIL loader=nil");
            NSLog(@"ARGON_DISCOVERY END");
            return;
        }
        __block NSUInteger visited = 0;
        __block NSUInteger ownMatches = 0;
        __block NSUInteger parsed = 0;
        void (^visitor)(Class) = ^(Class faceBundleClass) {
            visited++;

            NSLog(@"ARGON_DISCOVERY CALLBACK raw=%p",
                  (__bridge void *)faceBundleClass);

            if (!faceBundleClass) {
                NSLog(@"ARGON_DISCOVERY CALLBACK nil");
                return;
            }

            BOOL isClass = object_isClass(faceBundleClass);
            NSLog(@"ARGON_DISCOVERY CALLBACK isClass=%d objectType=%s",
                  isClass,
                  object_getClassName((id)faceBundleClass));

            if (!isClass) {
                Class resolvedClass = object_getClass((id)faceBundleClass);
                NSLog(@"ARGON_DISCOVERY CALLBACK resolvedClass=%@",
                      NSStringFromClass(resolvedClass));
                faceBundleClass = resolvedClass;
            }

            NSLog(@"ARGON_DISCOVERY CALLBACK className=%@",
                  NSStringFromClass(faceBundleClass));
            NSBundle *found = [NSBundle bundleForClass:faceBundleClass];
            NSLog(@"ARGON_DISCOVERY CLASS name=%@ bundle=%@ path=%@",
      NSStringFromClass(faceBundleClass),
      found.bundleIdentifier,
      found.bundlePath);
NSLog(@"ARGON_DISCOVERY LOCAL bundle=%@ path=%@",
      local.bundleIdentifier,
      local.bundlePath);
if (![found.bundleIdentifier isEqualToString:expected]) return;
            ownMatches++;
            id desc = ((id (*)(id, SEL, id))objc_msgSend)((id)descriptorClass, parser, found);
            if (desc && [desc isKindOfClass:descriptorClass]) {
                parsed++;
                id name = ((id (*)(id, SEL))objc_msgSend)(desc, filename);
                NSLog(@"ARGON_DISCOVERY match=YES class=%@ parser=PASS filename=%@",
                      NSStringFromClass(faceBundleClass),
                      [name isKindOfClass:NSString.class] ? name : @"<invalid>");
            } else {
                NSLog(@"ARGON_DISCOVERY match=YES class=%@ parser=FAIL", NSStringFromClass(faceBundleClass));
            }
        };
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(loader, enumerate, YES, visitor);
        NSLog(@"ARGON_DISCOVERY RESULT visited=%lu ownMatches=%lu parsed=%lu status=%@",
              (unsigned long)visited, (unsigned long)ownMatches, (unsigned long)parsed,
              (ownMatches && parsed == ownMatches) ? @"PASS" : @"NOT_DISCOVERED");
    } @catch (NSException *ex) {
        NSLog(@"ARGON_DISCOVERY exception=%@", ex.name);
    }
    NSLog(@"ARGON_DISCOVERY END");
}

// Factory-chain experiment, confined to WatchFaceLab. No Face Library mutation.
static id MYFCManager = nil;
static id MYFCBundle = nil;
static Class MYFCOriginalClass = Nil;
static Class MYFCTestClass = Nil;
static IMP MYFCOriginalLookupIMP = NULL;
static BOOL MYFCEnabled = NO;
static NSString *const MYFCIdentifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";

typedef id (*MYFCLookupFn)(id, SEL, id, id, BOOL);
static id MYFCLookup(id receiver, SEL selector, id identifier, id device, BOOL migration) {
    if (MYFCEnabled && receiver == MYFCManager && [identifier isEqual:MYFCIdentifier]) {
        NSLog(@"FACE_FACTORY lookup=LOCAL matched=1");
        return MYFCBundle;
    }
    return ((MYFCLookupFn)MYFCOriginalLookupIMP)(receiver, selector, identifier, device, migration);
}

static void MYFactoryChainV1(void) {
    NSLog(@"FACE_FACTORY BEGIN");
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
        NSLog(@"FACE_FACTORY SKIP unexpected host/thread");
        NSLog(@"FACE_FACTORY END");
        return;
    }
    Class managerClass = objc_lookUpClass("NTKFaceBundleManager");
    Class loaderClass = objc_lookUpClass("NTKFaceBundleLoader");
    Class descriptorClass = objc_lookUpClass("NTKFaceDescriptor");
    Class faceClass = objc_lookUpClass("NTKFace");
    Class deviceClass = objc_lookUpClass("CLKDevice");
    Class customClass = objc_lookUpClass("MYCustomFace");
    SEL shared = sel_registerName("sharedManager");
    SEL loaderFactory = sel_registerName("faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:");
    SEL loadBundle = sel_registerName("loadFaceBundleWithIdentifier:");
    SEL lookup = sel_registerName("faceBundleForBundleIdentifier:onDevice:forMigration:");
    SEL descriptorInit = sel_registerName("initWithBundleIdentifier:");
    SEL faceFactory = sel_registerName("defaultFaceFromFaceDescriptor:forDevice:");
    SEL currentDevice = sel_registerName("currentDevice");
    SEL faceStyle = sel_registerName("faceStyle");
    SEL bundleID = sel_registerName("bundleIdentifier");
    Method lm = managerClass ? class_getInstanceMethod(managerClass, lookup) : NULL;
    Method lf = loaderClass ? class_getClassMethod(loaderClass, loaderFactory) : NULL;
    Method li = loaderClass ? class_getInstanceMethod(loaderClass, loadBundle) : NULL;
    Method di = descriptorClass ? class_getInstanceMethod(descriptorClass, descriptorInit) : NULL;
    Method ff = faceClass ? class_getClassMethod(faceClass, faceFactory) : NULL;
    Method fs = faceClass ? class_getInstanceMethod(faceClass, faceStyle) : NULL;
    Method bi = faceClass ? class_getInstanceMethod(faceClass, bundleID) : NULL;
    NSLog(@"FACE_FACTORY ABI lookup=%s descriptor=%s factory=%s",
          lm ? method_getTypeEncoding(lm) : "missing",
          di ? method_getTypeEncoding(di) : "missing",
          ff ? method_getTypeEncoding(ff) : "missing");
    if (!lm || !lf || !li || !di || !ff || !fs || !bi || !deviceClass || !customClass ||
        strcmp(method_getTypeEncoding(lm), "@36@0:8@16@24B32") ||
        strcmp(method_getTypeEncoding(lf), "@32@0:8@16@24") ||
        strcmp(method_getTypeEncoding(li), "@24@0:8@16") ||
        strcmp(method_getTypeEncoding(di), "@24@0:8@16") ||
        strcmp(method_getTypeEncoding(ff), "@32@0:8@16@24") ||
        strcmp(method_getTypeEncoding(fs), "q16@0:8") ||
        strcmp(method_getTypeEncoding(bi), "@16@0:8")) {
        NSLog(@"FACE_FACTORY SKIP ABI mismatch (send log)");
        NSLog(@"FACE_FACTORY END");
        return;
    }
    id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, shared);
    id device = ((id (*)(id, SEL))objc_msgSend)((id)deviceClass, currentDevice);
    if (!manager || !device || object_getClass(manager) != managerClass) {
        NSLog(@"FACE_FACTORY SKIP manager/device unavailable or manager already hooked");
        NSLog(@"FACE_FACTORY END");
        return;
    }
    NSURL *root = [NSBundle mainBundle].bundleURL;
    NSBundle *local = [NSBundle bundleWithURL:[root URLByAppendingPathComponent:@"MYLocalFaceBundle.bundle" isDirectory:YES]];
    if (![local.bundleIdentifier isEqualToString:MYFCIdentifier]) {
        NSLog(@"FACE_FACTORY SKIP local bundle not found");
        NSLog(@"FACE_FACTORY END");
        return;
    }
    id loader = ((id (*)(id, SEL, id, id))objc_msgSend)((id)loaderClass, loaderFactory,
        [NSSet setWithObject:root], [NSSet setWithObject:@"dev.develodom.WatchFaceLab"]);
    id bundle = loader ? ((id (*)(id, SEL, id))objc_msgSend)(loader, loadBundle, MYFCIdentifier) : nil;
    if (!bundle || ![NSStringFromClass([bundle class]) isEqualToString:@"MYLocalFaceBundle"]) {
        NSLog(@"FACE_FACTORY SKIP isolated loader failed");
        NSLog(@"FACE_FACTORY END");
        return;
    }
    BOOL installed = NO;
    BOOL success = NO;
    @try {
        id baseline = ((id (*)(id, SEL, id, id, BOOL))objc_msgSend)(manager, lookup, MYFCIdentifier, device, NO);
        NSLog(@"FACE_FACTORY baselineAbsent=%d", baseline == nil);
        if (baseline) return;
        if (!MYFCTestClass) {
            if (objc_lookUpClass("MYFaceFactoryV1ScopedManager")) return;
            MYFCTestClass = objc_allocateClassPair(managerClass, "MYFaceFactoryV1ScopedManager", 0);
            if (!MYFCTestClass || !class_addMethod(MYFCTestClass, lookup, (IMP)MYFCLookup, method_getTypeEncoding(lm))) return;
            objc_registerClassPair(MYFCTestClass);
        }
        if (class_getInstanceSize(managerClass) != class_getInstanceSize(MYFCTestClass)) return;
        MYFCOriginalClass = managerClass;
        MYFCManager = manager;
        MYFCBundle = bundle;
        MYFCOriginalLookupIMP = method_getImplementation(lm);
        @synchronized(manager) {
            MYFCEnabled = YES;
            object_setClass(manager, MYFCTestClass);
            installed = YES;
        }
        id descriptor = ((id (*)(id, SEL, id))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)((id)descriptorClass, @selector(alloc)), descriptorInit, MYFCIdentifier);
        if (!descriptor) { NSLog(@"FACE_FACTORY descriptor=nil"); return; }
        id face = ((id (*)(id, SEL, id, id))objc_msgSend)((id)faceClass, faceFactory, descriptor, device);
        NSInteger style = face ? ((NSInteger (*)(id, SEL))objc_msgSend)(face, faceStyle) : -1;
        id identifier = face ? ((id (*)(id, SEL))objc_msgSend)(face, bundleID) : nil;
        success = face && [face isKindOfClass:customClass] && style == 44 && [identifier isEqual:MYFCIdentifier];
        NSLog(@"FACE_FACTORY RESULT class=%@ style=%ld identifier=%@ pass=%d",
              face ? NSStringFromClass([face class]) : @"nil", (long)style, identifier, success);
    } @catch (NSException *ex) {
        NSLog(@"FACE_FACTORY EXCEPTION name=%@ reason=%@", ex.name, ex.reason);
    } @finally {
        if (installed) {
            @synchronized(manager) {
                if (object_getClass(manager) == MYFCTestClass) {
                    object_setClass(manager, MYFCOriginalClass);
                    MYFCEnabled = NO;
                    MYFCBundle = nil;
                    MYFCManager = nil;
                } else {
                    NSLog(@"FACE_FACTORY WARNING class unexpectedly changed; restart app");
                }
            }
            BOOL restored = object_getClass(manager) == managerClass;
            NSLog(@"FACE_FACTORY RESTORED=%d success=%d", restored, success);
        }
        NSLog(@"FACE_FACTORY END");
    }
}

__attribute__((visibility("default"))) void MYInspectArgonDescriptorsV3(void) {
    NSLog(@"ARGON_V3 BEGIN");
    MYFactoryChainV1();
    MYArgonDiscoveryV1();
    MYArgonLocalParserTest();
    Class managerClass = objc_lookUpClass("NTKFaceBundleManager");
    SEL shared = sel_registerName("sharedManager");
    SEL enumerate = sel_registerName("enumerateArgonKeyDescriptorsWithBlock:");
    Class descriptorClass = objc_lookUpClass("NTKArgonKeyDescriptor");
    SEL fileName = sel_registerName("fileName");
    Method enumerator = managerClass ? class_getInstanceMethod(managerClass, enumerate) : NULL;
    Method filenameGetter = descriptorClass ? class_getInstanceMethod(descriptorClass, fileName) : NULL;
    if (!managerClass || !descriptorClass || !enumerator || !filenameGetter ||
        !class_respondsToSelector(object_getClass(managerClass), shared) ||
        strcmp(method_getTypeEncoding(enumerator), "v24@0:8@?16") != 0 ||
        strcmp(method_getTypeEncoding(filenameGetter), "@16@0:8") != 0) {
        NSLog(@"ARGON_V3 SKIP unexpected runtime ABI");
        NSLog(@"ARGON_V3 END");
        return;
    }
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, shared);
        if (!manager || ![manager isKindOfClass:managerClass]) {
            NSLog(@"ARGON_V3 SKIP sharedManager unavailable");
            NSLog(@"ARGON_V3 END");
            return;
        }
        __block NSUInteger count = 0;
        __block NSMutableDictionary<NSNumber *, NSNumber *> *groups = [NSMutableDictionary dictionary];
        void (^visitor)(NSUInteger, id) = ^(NSUInteger group, id descriptor) {
            NSUInteger index = count++;
            NSNumber *key = @(group);
            groups[key] = @([groups[key] unsignedIntegerValue] + 1);
            if (!descriptor || ![descriptor isKindOfClass:descriptorClass]) {
                NSLog(@"ARGON_V3 item=%lu group=%lu class=unexpected", (unsigned long)index, (unsigned long)group);
                return;
            }
            id name = ((id (*)(id, SEL))objc_msgSend)(descriptor, fileName);
            if (![name isKindOfClass:[NSString class]]) {
                NSLog(@"ARGON_V3 item=%lu group=%lu filename=<non-string>", (unsigned long)index, (unsigned long)group);
                return;
            }
            // Deliberately print the archive basename only. Never call -key or -argon_JSONRepresentation.
            NSString *basename = [(NSString *)name lastPathComponent];
            if (basename.length > 180) basename = [[basename substringToIndex:180] stringByAppendingString:@"…"];
            NSLog(@"ARGON_V3 item=%lu group=%lu filename=%@", (unsigned long)index, (unsigned long)group, basename);
        };
        ((void (*)(id, SEL, id))objc_msgSend)(manager, enumerate, visitor);
        NSLog(@"ARGON_V3 completed count=%lu groupCount=%lu", (unsigned long)count, (unsigned long)groups.count);
    } @catch (NSException *exception) {
        NSLog(@"ARGON_V3 exception=%@", exception.name);
    }
    NSLog(@"ARGON_V3 END");
}
