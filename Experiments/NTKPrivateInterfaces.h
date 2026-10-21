// EXPERIMENTAL ONLY. Reconstructed from watchOS 26.5 (23T570) x86_64 metadata.
// Not Apple SDK headers; selectors/types need runtime validation.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface NTKFace : NSObject
- (instancetype)_initWithFaceStyle:(NSUInteger)style forDevice:(id)device;
- (Class)faceViewClass;
@end

@interface NTKFaceView : UIView
- (instancetype)initWithFaceStyle:(NSUInteger)style
                              forDevice:(id)device
                      clientIdentifier:(NSString *)clientIdentifier;
+ (instancetype)newFaceViewForFace:(NTKFace *)face;
@end
