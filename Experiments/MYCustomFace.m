// NOT included in the app target. Intended for a later, separately validated experiment.
#import "NTKPrivateInterfaces.h"

@interface MYCustomFaceView : NTKFaceView
@end
@implementation MYCustomFaceView
- (instancetype)initWithFaceStyle:(NSUInteger)style
                        forDevice:(id)device
                clientIdentifier:(NSString *)clientIdentifier {
    self = [super initWithFaceStyle:style forDevice:device clientIdentifier:clientIdentifier];
    if (self) self.backgroundColor = [UIColor colorWithRed:0.05 green:0.12 blue:0.23 alpha:1];
    return self;
}
@end

@interface MYCustomFace : NTKFace
@end
@implementation MYCustomFace
- (Class)faceViewClass { return [MYCustomFaceView class]; }
@end
