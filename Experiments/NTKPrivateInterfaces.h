// Experimental declarations derived from watchOS 26.5 simulator x86_64 metadata.
// NOT yet ABI-verified on watchOS 27.0.1 device (arm64/arm64e).
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
+ (instancetype)bundledFaceWithIdentifier:(NSString *)identifier
                               forDevice:(CLKDevice *)device
                       initCustomization:(void (^)(NTKFace *face))customization;
- (NSString *)bundleIdentifier;
- (NSInteger)faceStyle;
- (NSDictionary *)JSONObjectRepresentation;
+ (BOOL)isRestrictedForDevice:(CLKDevice *)device;
@end

// Factory is inherited by NTKDigitalTimeLabel from ClockKitUI.
@interface CLKUITimeLabel : UIView
+ (instancetype)labelWithOptions:(NSUInteger)options forDevice:(CLKDevice *)device;
- (void)setFont:(UIFont *)font;
@end

@interface NTKDigitalTimeLabel : CLKUITimeLabel
- (void)setTextColor:(UIColor *)color;
@end

@interface NTKFaceView : UIView
- (instancetype)initWithFaceStyle:(NSInteger)style
                        forDevice:(CLKDevice *)device
                clientIdentifier:(NSString *)clientIdentifier;
+ (instancetype)newFaceViewForFace:(NTKFace *)face;
- (UIView *)timeView;
- (void)setTimeView:(UIView *)timeView;
- (UIView *)rootContainerView;
@end

// UIViewController superclass and these encodings verified in 23T570 metadata.
@class NTKFaceViewController;
@interface NTKFaceViewController : UIViewController
- (instancetype)initWithFace:(NTKFace *)face
               configuration:(void (^)(NTKFaceViewController *controller))configuration;
- (NTKFaceView *)faceView;
- (void)becomeActive;
- (void)resignActive;
@end

@interface NTKFaceBundle : NSObject
+ (NSString *)identifier;
- (Class)faceClass;
- (Class)faceViewClass;
- (NTKFace *)defaultFaceForDevice:(CLKDevice *)device;
- (NTKFace *)faceFromData:(NSData *)data;
- (NSArray<NTKFace *> *)galleryFacesForDevice:(CLKDevice *)device;
- (NSString *)galleryTitleForDevice:(CLKDevice *)device;
- (NSString *)galleryDescriptionForDevice:(CLKDevice *)device;
- (id)galleryRowPrioritiesForDevice:(CLKDevice *)device;
@end

@interface NTKFaceBundleLoader : NSObject
+ (instancetype)faceBundleLoaderWithDirectories:(NSSet<NSURL *> *)directories
                      appBundleIdentifierPrefixes:(NSSet<NSString *> *)prefixes;
- (NTKFaceBundle *)loadFaceBundleWithIdentifier:(NSString *)identifier;
@end

// Descriptor JSON payload is NSData, consumed by NSJSONSerialization in faceFromData:.
@interface NTKFaceInstanceDescriptor : NSObject <NSSecureCoding>
- (instancetype)initWithJSONRepresentation:(NSData *)data resourceDirectory:(id)directory;
@end

FOUNDATION_EXPORT NSString * const NTKFaceBundleIdentifierKey;
FOUNDATION_EXPORT NSString * const NTKFaceBundleFaceTypeKey;

@interface NTKGalleryCollection : NSObject
- (NSString *)title;
- (NSString *)descriptionText;
@end

@interface NTKFacesArrayGalleryCollection : NTKGalleryCollection
- (NSUInteger)numberOfFaces;
- (NTKFace *)faceAtIndex:(NSUInteger)index;
@end

@interface NTKFacesBundleArrayGalleryCollection : NTKFacesArrayGalleryCollection
- (instancetype)initWithDevice:(CLKDevice *)device faceBundle:(NTKFaceBundle *)bundle;
- (void)loadFaces;
@end

@interface NTKFaceBundleManager : NSObject
+ (instancetype)sharedManager;
- (void)enumerateFaceBundlesOnDevice:(CLKDevice *)device
                   includingLegacy:(BOOL)includingLegacy
                         withBlock:(void (^)(NTKFaceBundle *bundle))block;
- (NTKFaceBundle *)faceBundleForBundleIdentifier:(NSString *)identifier
                                       onDevice:(CLKDevice *)device
                                   forMigration:(BOOL)migration;
@end
