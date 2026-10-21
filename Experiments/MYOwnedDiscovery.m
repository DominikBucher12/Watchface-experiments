// Separate owned-app build of the guarded bridge implementation. No automatic entry point.
#define MY_BRIDGE_HOST_IDENTIFIER @"dev.develodom.WatchFaceLab"
#define MY_BRIDGE_CLASS_NAME "MYOwnedSessionBundleManager"
#define MYClockFaceBridgePreflight MYOwnedBridgePreflight
#define MYClockFaceBridgeInstall MYOwnedBridgeInstall
#define MYClockFaceBridgeCheck MYOwnedBridgeCheck
#define MYClockFaceBridgeRemove MYOwnedBridgeRemove
#include "MYClockFaceBridge.m"
#import "MYCustomFace.h"

static NSArray<NSString *> *MYBaselineIdentifiers;
static NTKFacesBundleArrayGalleryCollection *MYOwnedGallery;
static BOOL MYOwnedCycle;
static BOOL MYOwnedGalleryPassed;

static NSArray<NSString *> *MYDiscoveryIdentifiers(NTKFaceBundleManager *manager, CLKDevice *device) {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    [manager enumerateFaceBundlesOnDevice:device includingLegacy:YES withBlock:^(NTKFaceBundle *bundle) {
        NSString *identifier = [bundle.class identifier];
        // Preserve unidentified entries too, so removal checks cannot silently omit them.
        [identifiers addObject:identifier ?: [@"<unidentified>:" stringByAppendingString:NSStringFromClass(bundle.class)]];
    }];
    return [identifiers sortedArrayUsingSelector:@selector(compare:)];
}

BOOL MYStartOwnedDiscoveryExperiment(NSString *directoryPath) {
    if (!MYContext() || MYOwnedCycle || !MYOwnedBridgePreflight()) return NO;
    CLKDevice *device = [CLKDevice currentDevice];
    NTKFaceBundleManager *manager = [NTKFaceBundleManager sharedManager];
    if (!device || [manager faceBundleForBundleIdentifier:MYIdentifier onDevice:device forMigration:NO]) {
        NSLog(@"Owned discovery: expected an absent custom identifier before installation");
        return NO;
    }
    NSArray<NSString *> *baseline = MYDiscoveryIdentifiers(manager, device);
    if ([baseline containsObject:MYIdentifier]) return NO;
    if (!MYOwnedBridgeInstall(directoryPath)) return NO;
    MYBaselineIdentifiers = baseline;
    MYOwnedCycle = YES;
    MYOwnedGalleryPassed = NO;
    // Failures after installation leave the bridge available for explicit cleanup.
    if (!MYOwnedBridgeCheck()) return NO;
    NSMutableArray<NSString *> *expected = [baseline mutableCopy];
    [expected addObject:MYIdentifier];
    if (![MYDiscoveryIdentifiers(manager, device) isEqualToArray:
          [expected sortedArrayUsingSelector:@selector(compare:)]]) {
        NSLog(@"Owned discovery: original enumeration changed; remove the experiment");
        return NO;
    }
    NTKFaceBundle *bundle = [manager faceBundleForBundleIdentifier:MYIdentifier onDevice:device forMigration:NO];
    NSLog(@"Owned discovery: constructing native gallery from shared-manager lookup");
    MYOwnedGallery = [[NTKFacesBundleArrayGalleryCollection alloc] initWithDevice:device faceBundle:bundle];
    if (!MYOwnedGallery || ![[MYOwnedGallery title] isEqualToString:[bundle galleryTitleForDevice:device]] ||
        ![[MYOwnedGallery descriptionText] isEqualToString:[bundle galleryDescriptionForDevice:device]]) return NO;
    [MYOwnedGallery loadFaces];
    NSLog(@"Owned discovery STARTED: baseline bundles=%lu; resume before checking gallery; cleanup remains explicit",
          (unsigned long)baseline.count);
    return YES;
}

BOOL MYCheckOwnedDiscoveryExperiment(void) {
    if (!MYContext() || !MYOwnedCycle || !MYOwnedBridgeCheck() || !MYOwnedGallery) return NO;
    NSUInteger count = [MYOwnedGallery numberOfFaces];
    if (count != 1) {
        NSLog(@"Owned discovery: gallery faces=%lu; may still be pending; preserve logs", (unsigned long)count);
        return NO;
    }
    NTKFace *face = [MYOwnedGallery faceAtIndex:0];
    if (![face isKindOfClass:MYCustomFace.class] || face.faceStyle != 44 ||
        ![face.bundleIdentifier isEqualToString:MYIdentifier]) return NO;
    NSDictionary *json = [face JSONObjectRepresentation];
    if (![json isKindOfClass:NSDictionary.class] ||
        ![json[NTKFaceBundleIdentifierKey] isEqual:MYIdentifier] ||
        ![NSJSONSerialization isValidJSONObject:json]) return NO;
    NTKFaceView *renderer = [NTKFaceView newFaceViewForFace:face];
    if (![renderer isKindOfClass:MYCustomFaceView.class] ||
        ![renderer.timeView isKindOfClass:NTKDigitalTimeLabel.class]) return NO;
    MYOwnedGalleryPassed = YES;
    NSLog(@"Owned discovery CONSUMPTION PASS: shared lookup -> native gallery -> identified custom model/renderer/timeView");
    return YES;
}

BOOL MYRemoveOwnedDiscoveryExperiment(void) {
    if (!MYContext() || !MYOwnedCycle) return NO;
    MYOwnedGallery = nil;
    if (MYEnabled && !MYOwnedBridgeRemove()) return NO;
    CLKDevice *device = [CLKDevice currentDevice];
    BOOL restored = device && object_getClass(MYManager) == MYOriginalClass &&
        [MYDiscoveryIdentifiers(MYManager, device) isEqualToArray:MYBaselineIdentifiers] &&
        ![MYManager faceBundleForBundleIdentifier:MYIdentifier onDevice:device forMigration:NO];
    NSLog(@"Owned discovery REMOVAL: class/enumeration/absent-lookup restored=%d; consumptionPassed=%d; fullCyclePassed=%d",
          restored, MYOwnedGalleryPassed, restored && MYOwnedGalleryPassed);
    if (restored) {
        MYOwnedCycle = NO;
        MYBaselineIdentifiers = nil;
        MYOwnedGalleryPassed = NO;
    }
    // Images remain loaded and pending framework work is not cancelled. Restart for a cold cycle.
    return restored;
}
