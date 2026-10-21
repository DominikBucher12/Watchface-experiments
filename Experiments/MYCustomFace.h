#import "NTKPrivateInterfaces.h"

@interface MYCustomFace : NTKFace
@end

@interface MYCustomFaceView : NTKFaceView
@end

// Explicit debugger entry point. Call on the main thread, with a researched style.
// Retain the returned view and face in the host for the duration of the experiment.
FOUNDATION_EXPORT MYCustomFaceView *MYCreateCustomFaceView(NSInteger style,
                                                         MYCustomFace **faceOut);

// Main-thread, explicitly invoked app-only preview. No registration or persistence.
FOUNDATION_EXPORT BOOL MYPresentCustomFaceExperiment(NSInteger style);
FOUNDATION_EXPORT void MYDismissCustomFaceExperiment(void);

// Native controller path. Dismiss the ordinary preview before invoking this.
// Activation is a separate experiment after successful presentation/teardown.
FOUNDATION_EXPORT BOOL MYPresentNativeControllerExperiment(NSInteger style);
FOUNDATION_EXPORT BOOL MYSetNativeControllerExperimentActive(BOOL active);
FOUNDATION_EXPORT void MYDismissNativeControllerExperiment(void);

// Searches only the explicit directory; does not use the shared bundle manager.
FOUNDATION_EXPORT BOOL MYDiscoverLocalFaceBundle(NSString *directoryPath);

FOUNDATION_EXPORT BOOL MYRoundTripLocalFaceBundle(NSString *directoryPath);

// Restores only after all existing identity/JSON/renderer assertions pass.
FOUNDATION_EXPORT MYCustomFace *MYRestoreLocalFaceBundle(NSString *directoryPath);
FOUNDATION_EXPORT BOOL MYPresentRestoredLocalFaceExperiment(NSString *directoryPath);

FOUNDATION_EXPORT BOOL MYInspectLocalFaceGallery(NSString *directoryPath);

// Start schedules native asynchronous loading; resume before checking.
FOUNDATION_EXPORT BOOL MYStartNativeGalleryCollection(NSString *directoryPath);
FOUNDATION_EXPORT BOOL MYCheckNativeGalleryCollection(void);
FOUNDATION_EXPORT void MYReleaseNativeGalleryCollection(void);
