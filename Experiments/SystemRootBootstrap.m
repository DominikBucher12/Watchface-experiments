#import <Foundation/Foundation.h>
#import <unistd.h>

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
        NSLog(@"WATCHFACELAB_ROOT_BOOTSTRAP pid=%d host=%@ process=%@ root=%@ setenv=%d",
              getpid(), bundleIdentifier, process, root, result);
    }
}
