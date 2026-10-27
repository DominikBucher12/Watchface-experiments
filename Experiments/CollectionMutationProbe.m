#import "NTKPrivateInterfaces.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static NSString *const MYBundleIdentifier =
    @"dev.develodom.WatchFaceLab.LocalFaceBundle";

static id MYSendObject(id receiver, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static id MYSendObjectUnsigned(id receiver, SEL selector, NSUInteger value) {
    return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(receiver, selector, value);
}

static BOOL MYSendBool(id receiver, SEL selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static NSUInteger MYSendUnsigned(id receiver, SEL selector) {
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static BOOL MYMethodMatches(Class cls, SEL selector, const char *encoding) {
    Method method = class_getInstanceMethod(cls, selector);
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

static BOOL MYWaitUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0.0) {
        [NSRunLoop.currentRunLoop runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return condition();
}

static NSString *MYFaceIdentifier(id face) {
    SEL selector = sel_registerName("bundleIdentifier");
    return [face respondsToSelector:selector] ? MYSendObject(face, selector) : nil;
}

static id MYCustomFaceInCollection(id collection) {
    SEL countSelector = sel_registerName("numberOfFaces");
    SEL faceSelector = sel_registerName("faceAtIndex:");
    NSUInteger count = MYSendUnsigned(collection, countSelector);
    for (NSUInteger index = 0; index < count; index++) {
        id face = MYSendObjectUnsigned(collection, faceSelector, index);
        if ([MYFaceIdentifier(face) isEqualToString:MYBundleIdentifier]) return face;
    }
    return nil;
}

static void MYPrint(NSDictionary *result) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc == 2 ? [NSString stringWithUTF8String:argv[1]] : nil;
        NSDictionary *environment = NSProcessInfo.processInfo.environment;
        NSString *root = environment[@"IPHONE_SIMULATOR_ROOT"];
        NSString *marker = environment[@"WATCHFACELAB_SYSTEM_DISCOVERY_PROBE"];
        NSString *bundlePath = [root stringByAppendingPathComponent:
            @"System/Library/NanoTimeKit/FaceBundles/MYLocalFaceBundle.bundle"];
        if ((![@"install" isEqualToString:mode] && ![@"remove" isEqualToString:mode]) ||
            ![marker isEqualToString:@"1"] ||
            ![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
            MYPrint(@{@"error": @"usage/overlay guard rejected", @"root": root ?: @"nil"});
            return 64;
        }

        Class collectionClass = NSClassFromString(@"NTKPersistentFaceCollection");
        SEL sharedSelector = sel_registerName("sharedLibraryCollection");
        SEL loadedSelector = sel_registerName("hasLoaded");
        SEL countSelector = sel_registerName("numberOfFaces");
        SEL faceSelector = sel_registerName("faceAtIndex:");
        SEL orderedSelector = sel_registerName("orderedUUIDs");
        SEL selectedSelector = sel_registerName("selectedUUID");
        SEL addSelector = sel_registerName("addFace:atIndex:suppressingCallbackToObserver:");
        SEL removeSelector = sel_registerName("removeFace:suppressingCallbackToObserver:");
        SEL selectSelector = sel_registerName("_selectFaceUUID:notify:");
        if (!collectionClass || ![collectionClass respondsToSelector:sharedSelector]) return 65;

        id collection = MYSendObject((id)collectionClass, sharedSelector);
        Class concreteClass = [collection class];
        BOOL abiMatches =
            MYMethodMatches(concreteClass, loadedSelector, "B16@0:8") &&
            MYMethodMatches(concreteClass, countSelector, "Q16@0:8") &&
            MYMethodMatches(concreteClass, faceSelector, "@24@0:8Q16") &&
            MYMethodMatches(concreteClass, orderedSelector, "@16@0:8") &&
            MYMethodMatches(concreteClass, selectedSelector, "@16@0:8") &&
            MYMethodMatches(concreteClass, addSelector, "v40@0:8@16Q24@32") &&
            MYMethodMatches(concreteClass, removeSelector, "v32@0:8@16@24") &&
            MYMethodMatches(concreteClass, selectSelector, "v28@0:8@16B24");
        if (!abiMatches) {
            MYPrint(@{@"error": @"collection ABI mismatch"});
            return 66;
        }
        if (!MYWaitUntil(^BOOL { return MYSendBool(collection, loadedSelector); }, 10.0)) {
            MYPrint(@{@"error": @"collection load timeout"});
            return 67;
        }

        NSUInteger beforeCount = MYSendUnsigned(collection, countSelector);
        id existing = MYCustomFaceInCollection(collection);
        if ([mode isEqualToString:@"remove"]) {
            if (!existing) {
                MYPrint(@{@"mode": mode, @"removed": @NO,
                          @"reason": @"custom face absent", @"count": @(beforeCount)});
                return 0;
            }
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                collection, removeSelector, existing, nil);
            BOOL removed = MYWaitUntil(^BOOL {
                return !MYCustomFaceInCollection(collection);
            }, 10.0);
            MYPrint(@{@"mode": mode, @"removed": @(removed),
                      @"countBefore": @(beforeCount),
                      @"countAfter": @(MYSendUnsigned(collection, countSelector))});
            return removed ? 0 : 68;
        }

        if (existing) {
            MYPrint(@{@"error": @"custom face already present", @"count": @(beforeCount)});
            return 69;
        }
        CLKDevice *device = [CLKDevice currentDevice];
        NTKFaceBundleManager *manager = [NTKFaceBundleManager sharedManager];
        NTKFaceBundle *bundle = [manager faceBundleForBundleIdentifier:MYBundleIdentifier
                                                              onDevice:device
                                                          forMigration:NO];
        NTKFace *face = [bundle defaultFaceForDevice:device];
        if (!bundle || !face || ![MYFaceIdentifier(face) isEqualToString:MYBundleIdentifier]) {
            MYPrint(@{@"error": @"custom bundle/face unavailable from shared manager"});
            return 70;
        }

        NSArray *beforeOrder = [MYSendObject(collection, orderedSelector) copy];
        NSUUID *beforeSelectedUUID = [MYSendObject(collection, selectedSelector) copy];
        ((void (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(
            collection, addSelector, face, beforeCount, nil);
        BOOL added = MYWaitUntil(^BOOL {
            return MYSendUnsigned(collection, countSelector) == beforeCount + 1;
        }, 10.0);
        NSArray *afterOrder = [MYSendObject(collection, orderedSelector) copy];
        NSMutableSet *newUUIDs = [NSMutableSet setWithArray:afterOrder ?: @[]];
        [newUUIDs minusSet:[NSSet setWithArray:beforeOrder ?: @[]]];
        NSUUID *newUUID = newUUIDs.count == 1 ? newUUIDs.anyObject : nil;
        if (!added || !newUUID) {
            id partialFace = MYCustomFaceInCollection(collection);
            if (partialFace) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(
                    collection, removeSelector, partialFace, nil);
            }
            BOOL rolledBack = MYWaitUntil(^BOOL {
                return !MYCustomFaceInCollection(collection) &&
                    MYSendUnsigned(collection, countSelector) == beforeCount;
            }, 10.0);
            MYPrint(@{@"error": @"add did not produce exactly one UUID",
                      @"countBefore": @(beforeCount),
                      @"countAfter": @(MYSendUnsigned(collection, countSelector)),
                      @"newUUIDCount": @(newUUIDs.count),
                      @"rolledBack": @(rolledBack)});
            return 71;
        }

        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
            collection, selectSelector, newUUID, YES);
        BOOL selected = MYWaitUntil(^BOOL {
            return [MYSendObject(collection, selectedSelector) isEqual:newUUID];
        }, 10.0);
        if (!selected) {
            id addedFace = MYCustomFaceInCollection(collection);
            if (addedFace) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(
                    collection, removeSelector, addedFace, nil);
            }
            if (beforeSelectedUUID) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                    collection, selectSelector, beforeSelectedUUID, YES);
            }
            BOOL rolledBack = MYWaitUntil(^BOOL {
                BOOL faceRestored = !MYCustomFaceInCollection(collection) &&
                    MYSendUnsigned(collection, countSelector) == beforeCount;
                BOOL selectionRestored = !beforeSelectedUUID ||
                    [MYSendObject(collection, selectedSelector)
                        isEqual:beforeSelectedUUID];
                return faceRestored && selectionRestored;
            }, 10.0);
            MYPrint(@{@"error": @"selection verification failed",
                      @"uuid": newUUID.UUIDString,
                      @"rolledBack": @(rolledBack),
                      @"countBefore": @(beforeCount),
                      @"countAfter": @(MYSendUnsigned(collection, countSelector))});
            return 72;
        }
        MYPrint(@{@"mode": mode, @"added": @YES, @"selected": @(selected),
                  @"uuid": newUUID.UUIDString,
                  @"countBefore": @(beforeCount),
                  @"countAfter": @(MYSendUnsigned(collection, countSelector))});
        return selected ? 0 : 72;
    }
}
