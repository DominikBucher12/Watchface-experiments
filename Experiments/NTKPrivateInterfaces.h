// Minimal declarations verified against watchOS 26.5 (23T570), x86_64 metadata.
#import <Foundation/Foundation.h>
// UIKit exists in the runtime but its SDK declarations exclude watchOS.
// Suppress only unavailable annotations while parsing UIKit for this experiment.
#pragma push_macro("API_UNAVAILABLE")
#undef API_UNAVAILABLE
#define API_UNAVAILABLE(...)
#import <UIKit/UIKit.h>
#pragma pop_macro("API_UNAVAILABLE")

@interface CLKDevice : NSObject
+ (instancetype)currentDevice;
@end

@interface NTKFace : NSObject
- (instancetype)_initWithFaceStyle:(NSInteger)style forDevice:(CLKDevice *)device;
- (Class)faceViewClass;
@end

@interface NTKFaceView : UIView
- (instancetype)initWithFaceStyle:(NSInteger)style
                        forDevice:(CLKDevice *)device
                clientIdentifier:(NSString *)clientIdentifier;
+ (instancetype)newFaceViewForFace:(NTKFace *)face;
@end
