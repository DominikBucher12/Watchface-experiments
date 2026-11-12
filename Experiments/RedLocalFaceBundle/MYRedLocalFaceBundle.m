#import "../MYCustomFace.h"
#import <unistd.h>

@interface MYRedLocalFaceBundle : NTKFaceBundle
@end

@implementation MYRedLocalFaceBundle
+ (void)load {
    NSString *enabled = NSProcessInfo.processInfo.environment[
        @"WATCHFACELAB_SYSTEM_DISCOVERY_PROBE"];
    if ([enabled isEqualToString:@"1"]) {
        NSLog(@"WATCHFACELAB_RED_BUNDLE_LOADED pid=%d host=%@ class=%@ root=%@",
              getpid(), NSBundle.mainBundle.bundleIdentifier,
              NSStringFromClass(self),
              NSProcessInfo.processInfo.environment[@"IPHONE_SIMULATOR_ROOT"]);
    }
}

- (Class)faceClass { return MYRedCustomFace.class; }
- (Class)faceViewClass { return MYRedCustomFaceView.class; }
- (NTKFace *)defaultFaceForDevice:(CLKDevice *)device {
    return [MYRedCustomFace bundledFaceWithIdentifier:[self.class identifier]
                                            forDevice:device
                                    initCustomization:nil];
}
- (NSString *)galleryTitleForDevice:(CLKDevice *)device {
    (void)device;
    NSString *configuredTitle = NSProcessInfo.processInfo.environment[
        @"WATCHFACELAB_FACE_TITLE"];
    NSString *baseTitle = configuredTitle.length > 0 ? configuredTitle : @"VAULT BOY";
    return [baseTitle stringByAppendingString:@" RED"];
}
- (NSString *)galleryDescriptionForDevice:(CLKDevice *)device {
    (void)device;
    return @"Red Vault Boy variant for the isolated WatchFaceLab experiment.";
}
- (NSArray<NTKFace *> *)galleryFacesForDevice:(CLKDevice *)device {
    NTKFace *face = [self defaultFaceForDevice:device];
    return face ? @[face] : @[];
}
@end
