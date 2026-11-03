#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>

typedef NSString *(*MYLocalizedStringIMP)(id, SEL, NSString *, NSString *, NSString *);
static MYLocalizedStringIMP MYOriginalLocalizedString;
static NSString *MYFaceTitle;

static NSString *MYLocalizedStringForKey(NSBundle *bundle, SEL selector,
                                         NSString *key, NSString *value,
                                         NSString *tableName) {
    if ([key isEqualToString:@"FACE_STYLE_44_IN_TITLE_CASE"] ||
        [key isEqualToString:@"FACE_STYLE_44"]) {
        NSLog(@"WATCHFACELAB_FACE_TITLE key=%@ value=%@", key, MYFaceTitle);
        return MYFaceTitle;
    }
    return MYOriginalLocalizedString(bundle, selector, key, value, tableName);
}

static BOOL MYInstallFaceTitleOverride(void) {
    SEL selector = @selector(localizedStringForKey:value:table:);
    Method method = class_getInstanceMethod(NSBundle.class, selector);
    if (!method) return NO;
    MYOriginalLocalizedString = (MYLocalizedStringIMP)method_setImplementation(
        method, (IMP)MYLocalizedStringForKey);
    return MYOriginalLocalizedString != NULL;
}

__attribute__((constructor))
static void MYInstallSystemDiscoveryRoot(void) {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
        BOOL allowedHost =
            [bundleIdentifier isEqualToString:@"com.apple.clockface"] ||
            [process isEqualToString:@"ClockFace"] ||
            [process isEqualToString:@"nanotimekitd"];
        if (!allowedHost) return;

        NSString *root = NSProcessInfo.processInfo.environment[
            @"WATCHFACELAB_OVERLAY_ROOT"];
        NSString *bundlePath = [root stringByAppendingPathComponent:
            @"System/Library/NanoTimeKit/FaceBundles/MYLocalFaceBundle.bundle"];
        if (![root hasPrefix:@"/tmp/WatchFaceLabSystemRoot."] ||
            ![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
            NSLog(@"WATCHFACELAB_ROOT_BOOTSTRAP_REJECTED pid=%d host=%@ process=%@ root=%@",
                  getpid(), bundleIdentifier, process, root);
            return;
        }

        int result = setenv("IPHONE_SIMULATOR_ROOT", root.fileSystemRepresentation, 1);
        NSString *configuredTitle = NSProcessInfo.processInfo.environment[
            @"WATCHFACELAB_FACE_TITLE"];
        MYFaceTitle = configuredTitle.length > 0 ? configuredTitle.copy : @"VAULT BOY";
        BOOL titleOverride = MYInstallFaceTitleOverride();
        NSLog(@"WATCHFACELAB_ROOT_BOOTSTRAP pid=%d host=%@ process=%@ root=%@ setenv=%d",
              getpid(), bundleIdentifier, process, root, result);
        NSLog(@"WATCHFACELAB_FACE_TITLE_OVERRIDE pid=%d installed=%d title=%@",
              getpid(), titleOverride, MYFaceTitle);
    }
}
