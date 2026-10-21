#import "../MYCustomFace.h"

@interface MYLocalFaceBundle : NTKFaceBundle
@end

@implementation MYLocalFaceBundle
// Inherit +identifier so identity is derived from the actual NSBundle.
- (Class)faceClass { return MYCustomFace.class; }
- (Class)faceViewClass { return MYCustomFaceView.class; }
- (NTKFace *)defaultFaceForDevice:(CLKDevice *)device {
    // Reuse the style already exercised in the isolated app preview.
    return [[MYCustomFace alloc] _initWithFaceStyle:0 forDevice:device];
}
@end
