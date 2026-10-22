#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Read-only runtime metadata probe. Never invokes private NanoTimeKit selectors.
static void MYPrintSelectors(Class cls, BOOL classMethods) {
    if (!cls) return;
    Class target = classMethods ? object_getClass((id)cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *raw = sel_getName(method_getName(methods[i]));
        if (raw) [names addObject:[NSString stringWithUTF8String:raw]];
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    NSLog(@"ARGON_PROBE %@ %@ ownMethodCount=%lu", NSStringFromClass(cls),
          classMethods ? @"class" : @"instance", (unsigned long)names.count);
    for (NSString *name in names) {
        NSLog(@"ARGON_PROBE   %@%@", classMethods ? @"+" : @"-", name);
    }
}

static void MYPrintPath(NSString *label, NSString *path) {
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    BOOL readable = exists && [[NSFileManager defaultManager] isReadableFileAtPath:path];
    NSLog(@"ARGON_PROBE path=%@ exists=%d directory=%d readable=%d", label, exists, isDir, readable);
}

__attribute__((visibility("default"))) void MYInspectArgonRuntime(void) {
    if (![NSThread isMainThread]) {
        NSLog(@"ARGON_PROBE FAIL: must run on main thread");
        return;
    }
    NSLog(@"ARGON_PROBE BEGIN bundle=%@ os=%@", NSBundle.mainBundle.bundleIdentifier,
          NSProcessInfo.processInfo.operatingSystemVersionString);

    const char *classNames[] = {
        "NTKArgonManager", "NTKArgonExtractor", "NTKArgonKeyDescriptor",
        "NTKArgonLocalKeyDatabase", "NTKArgonCloudKitClient",
        "NTKAppleEncryptedArchiveDiskExtractor", "NTKFaceBundleManager",
        "NTKFaceBundleLoader", "NTKFaceSupportServerInterface"
    };
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < sizeof(classNames)/sizeof(classNames[0]); ++i) {
        Class cls = objc_lookUpClass(classNames[i]);
        NSLog(@"ARGON_PROBE class=%s present=%d", classNames[i], cls != Nil);
        if (!cls) continue;
        found++;
        MYPrintSelectors(cls, NO);
        MYPrintSelectors(cls, YES);
    }

    NSString *home = NSHomeDirectory();
    MYPrintPath(@"appHome/Library/NanoTimeKit/FaceSupport/ExtractedBundles",
        [home stringByAppendingPathComponent:@"Library/NanoTimeKit/FaceSupport/ExtractedBundles"]);
    MYPrintPath(@"appBundle/FaceBundles", [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"FaceBundles"]);
    MYPrintPath(@"appBundle/MYLocalFaceBundle.bundle", [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"MYLocalFaceBundle.bundle"]);
    MYPrintPath(@"system/NanoTimeKit/FaceBundles", @"/System/Library/NanoTimeKit/FaceBundles");
    NSLog(@"ARGON_PROBE END knownClassesPresent=%lu/%lu (paths checked only in app sandbox)",
          (unsigned long)found, (unsigned long)(sizeof(classNames)/sizeof(classNames[0])));
}
