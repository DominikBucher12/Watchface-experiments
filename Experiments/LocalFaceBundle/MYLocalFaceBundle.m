#import "../MYCustomFace.h"
#import <unistd.h>

@interface MYLocalFaceBundle : NTKFaceBundle
@end

@implementation MYLocalFaceBundle
+ (void)load {
    NSString *enabled = NSProcessInfo.processInfo.environment[
        @"WATCHFACELAB_SYSTEM_DISCOVERY_PROBE"];
    if ([enabled isEqualToString:@"1"]) {
        NSLog(@"WATCHFACELAB_SYSTEM_BUNDLE_LOADED pid=%d host=%@ class=%@ root=%@",
              getpid(), NSBundle.mainBundle.bundleIdentifier,
              NSStringFromClass(self),
              NSProcessInfo.processInfo.environment[@"IPHONE_SIMULATOR_ROOT"]);
    }
}

// Inherit +identifier so identity is derived from the actual NSBundle.
- (Class)faceClass { return MYCustomFace.class; }
- (Class)faceViewClass { return MYCustomFaceView.class; }
- (NTKFace *)defaultFaceForDevice:(CLKDevice *)device {
    return [MYCustomFace bundledFaceWithIdentifier:[self.class identifier]
                                         forDevice:device initCustomization:nil];
}
- (NSString *)galleryTitleForDevice:(CLKDevice *)device {
    (void)device;
    return @"Custom Face PoC";
}
- (NSString *)galleryDescriptionForDevice:(CLKDevice *)device {
    (void)device;
    return @"Minimal custom digital face for the isolated WatchFaceLab experiment.";
}
- (NSArray<NTKFace *> *)galleryFacesForDevice:(CLKDevice *)device {
    // The base implementation depends on edit/pigment variants. This PoC has one face.
    NTKFace *face = [self defaultFaceForDevice:device];
    return face ? @[face] : @[];
}
@end
