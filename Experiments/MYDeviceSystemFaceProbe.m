// Controlled physical-device experiment for NanoTimeKit's persistent library.
// All mutations are explicit, ABI-gated and paired with a rollback entry point.
#import "MYCustomFace.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>

static NSString * const MYSystemBundleID =
    @"dev.develodom.WatchFaceLab.LocalFaceBundle";
static NSString * const MYCandidateUUIDKey =
    @"WatchFaceLab.SystemCandidateUUID";
static NSString * const MYPreviousUUIDKey =
    @"WatchFaceLab.PreviousSelectedUUID";
static NSDictionary *MYLastCollectionABI;
static BOOL MYLastMutationABIMatches;
static NSString *MYUUIDString(id value);

// sandbox.h is intentionally not part of the watchOS SDK. Resolve the
// read-only query dynamically and keep the private filter value local instead
// of adding a private header dependency.
typedef int (*MYSandboxCheckFunction)(pid_t, const char *, int, ...);
typedef CFTypeRef (*MYSecTaskCreateFromSelfFunction)(CFAllocatorRef);
typedef CFTypeRef (*MYSecTaskCopyValueForEntitlementFunction)(
    CFTypeRef, CFStringRef, CFErrorRef *);
static const int MYSandboxFilterGlobalName = 2;
static NSString * const MYCollectionServerName =
    @"com.apple.nanotimekit.collectionserver";

static id MYSendObject(id receiver, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static BOOL MYSendBool(id receiver, SEL selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static NSUInteger MYSendUnsigned(id receiver, SEL selector) {
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static id MYSendObjectUnsigned(id receiver, SEL selector, NSUInteger value) {
    return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(receiver, selector, value);
}

static BOOL MYWaitUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0.0) {
        [NSRunLoop.currentRunLoop runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return condition();
}

static NSString *MYEncoding(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
}

static id MYObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static NSNumber *MYBoolIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || strcmp(type, @encode(BOOL)) != 0) return nil;
    BOOL value = NO;
    const uint8_t *bytes = (const uint8_t *)(__bridge const void *)(object);
    memcpy(&value, bytes + ivar_getOffset(ivar), sizeof(value));
    return @(value);
}

static NSDictionary *MYSandboxBoundaryDiagnostics(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    MYSandboxCheckFunction check = (MYSandboxCheckFunction)dlsym(
        RTLD_DEFAULT, "sandbox_check");
    result[@"apiPresent"] = @(check != NULL);
    result[@"operation"] = @"mach-lookup";
    result[@"globalName"] = MYCollectionServerName;
    if (!check) return result;

    errno = 0;
    int rawResult = check(getpid(), "mach-lookup",
        MYSandboxFilterGlobalName, MYCollectionServerName.UTF8String);
    int savedErrno = errno;
    result[@"rawResult"] = @(rawResult);
    result[@"querySucceeded"] = @(rawResult >= 0);
    result[@"allowed"] = @(rawResult == 0);
    result[@"denied"] = @(rawResult > 0);
    result[@"errno"] = @(savedErrno);
    if (savedErrno != 0) {
        result[@"errnoDescription"] =
            [NSString stringWithUTF8String:strerror(savedErrno)] ?: @"unknown";
    }
    return result;
}

static NSDictionary *MYSignedEntitlementDiagnostics(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    MYSecTaskCreateFromSelfFunction createTask =
        (MYSecTaskCreateFromSelfFunction)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    MYSecTaskCopyValueForEntitlementFunction copyValue =
        (MYSecTaskCopyValueForEntitlementFunction)dlsym(
            RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    result[@"apiPresent"] = @(createTask != NULL && copyValue != NULL);
    if (!createTask || !copyValue) return result;

    CFTypeRef task = createTask(kCFAllocatorDefault);
    result[@"taskPresent"] = @(task != NULL);
    if (!task) return result;

    NSArray<NSString *> *keys = @[
        @"application-identifier",
        @"com.apple.security.exception.mach-lookup.global-name",
        @"com.apple.nanotimekit.replicator.library.entitlement",
        @"com.apple.private.security.storage.NanoTimeKit.FaceSupport",
        @"platform-application",
    ];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        CFTypeRef value = copyValue(task, (__bridge CFStringRef)key, NULL);
        values[key] = value ? CFBridgingRelease(value) : NSNull.null;
    }
    CFRelease(task);
    result[@"values"] = values;
    return result;
}

static NSDictionary *MYCurrentDeviceDiagnostics(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    Class cls = objc_lookUpClass("CLKDevice");
    SEL currentSelector = sel_registerName("currentDevice");
    result[@"classPresent"] = @(cls != Nil);
    result[@"currentEncoding"] = cls ? MYEncoding(object_getClass((id)cls), currentSelector) : @"missing";
    id device = cls && [cls respondsToSelector:currentSelector] ?
        MYSendObject((id)cls, currentSelector) : nil;
    result[@"currentPresent"] = @(device != nil);
    result[@"currentClass"] = device ? NSStringFromClass([device class]) : @"nil";

    NSMutableDictionary *uuidMethods = [NSMutableDictionary dictionary];
    unsigned int methodCount = 0;
    Method *methods = device ? class_copyMethodList([device class], &methodCount) : NULL;
    for (unsigned int index = 0; index < methodCount; index++) {
        SEL selector = method_getName(methods[index]);
        NSString *name = NSStringFromSelector(selector);
        NSString *lowercase = name.lowercaseString;
        if ([lowercase containsString:@"uuid"] || [lowercase containsString:@"pairing"]) {
            const char *encoding = method_getTypeEncoding(methods[index]);
            uuidMethods[name] = encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
        }
    }
    free(methods);
    result[@"identityMethods"] = uuidMethods;
    return result;
}

static NSDictionary *MYCollectionDiagnostics(id collection) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    id connection = MYObjectIvar(collection, "_connection");
    id seqID = MYObjectIvar(collection, "_seqId");
    id referenceOrder = MYObjectIvar(collection, "_referenceOrderedUUIDs");
    id referenceSelected = MYObjectIvar(collection, "_referenceSelectedUUID");
    NSNumber *registrationNeeded = MYBoolIvar(collection, "_registrationNeeded");
    NSNumber *lockHasLoaded = MYBoolIvar(collection, "_lock_hasLoaded");
    result[@"connectionPresent"] = @(connection != nil);
    result[@"connectionClass"] = connection ? NSStringFromClass([connection class]) : @"nil";
    result[@"registrationNeeded"] = registrationNeeded ?: @"unavailable";
    result[@"lockHasLoaded"] = lockHasLoaded ?: @"unavailable";
    result[@"seqID"] = [seqID respondsToSelector:@selector(stringValue)] ?
        [seqID stringValue] : @"nil";
    result[@"referenceOrderedCount"] = [referenceOrder respondsToSelector:@selector(count)] ?
        @([referenceOrder count]) : @(-1);
    result[@"referenceSelectedUUID"] = MYUUIDString(referenceSelected) ?: @"nil";
    SEL collectionIdentifier = sel_registerName("collectionIdentifier");
    SEL deviceUUID = sel_registerName("deviceUUID");
    result[@"collectionIdentifier"] = [collection respondsToSelector:collectionIdentifier] ?
        (MYSendObject(collection, collectionIdentifier) ?: @"nil") : @"unavailable";
    result[@"deviceUUID"] = [collection respondsToSelector:deviceUUID] ?
        (MYUUIDString(MYSendObject(collection, deviceUUID)) ?: @"nil") : @"unavailable";
    return result;
}

// Repeats only the collection registration request already issued by the
// framework, but supplies an error handler we control. Registration loads
// state; it does not add, remove, reorder, or select a face.
static NSDictionary *MYXPCRegistrationErrorProbe(id collection) {
    id connection = MYObjectIvar(collection, "_connection");
    SEL proxySelector = sel_registerName("remoteObjectProxyWithErrorHandler:");
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"connectionPresent"] = @(connection != nil);
    result[@"proxyEncoding"] = connection ?
        MYEncoding([connection class], proxySelector) : @"missing";
    if (!connection || ![connection respondsToSelector:proxySelector]) {
        result[@"sent"] = @NO;
        result[@"error"] = @"error-handler proxy unavailable";
        return result;
    }

    __block NSDictionary *capturedError = nil;
    void (^errorHandler)(NSError *) = ^(NSError *error) {
        capturedError = @{
            @"domain": error.domain ?: @"unknown",
            @"code": @(error.code),
            @"description": error.localizedDescription ?: @"unknown",
        };
    };
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(
        connection, proxySelector, errorHandler);
    SEL collectionIdentifier = sel_registerName("collectionIdentifier");
    SEL deviceUUID = sel_registerName("deviceUUID");
    id identifier = MYSendObject(collection, collectionIdentifier);
    id uuid = MYSendObject(collection, deviceUUID);
    id seqID = MYObjectIvar(collection, "_seqId");
    SEL registerSelector = sel_registerName(
        "registerForCollectionIdentifier:deviceUUID:withSeqId:");
    if (!proxy || !identifier) {
        result[@"sent"] = @NO;
        result[@"error"] = @"registration proxy or identifier unavailable";
        return result;
    }
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(
        proxy, registerSelector, identifier, uuid, seqID);
    result[@"sent"] = @YES;
    MYWaitUntil(^BOOL { return capturedError != nil; }, 3.0);
    result[@"errorReceived"] = @(capturedError != nil);
    if (capturedError) result[@"xpcError"] = capturedError;
    return result;
}

static NSString *MYFaceBundleIdentifier(id face) {
    SEL selector = sel_registerName("bundleIdentifier");
    return [face respondsToSelector:selector] ? MYSendObject(face, selector) : nil;
}

static NSString *MYUUIDString(id value) {
    return [value respondsToSelector:@selector(UUIDString)] ?
        [value UUIDString] : nil;
}

// Recover our UUID from the collection itself when an app update did not retain
// NSUserDefaults. A unique match is required so rollback never guesses.
static NSDictionary *MYUniqueCustomFaceEntry(id collection) {
    SEL countSelector = sel_registerName("numberOfFaces");
    SEL faceSelector = sel_registerName("faceAtIndex:");
    NSArray *order = MYSendObject(collection, sel_registerName("orderedUUIDs")) ?: @[];
    NSUInteger count = MYSendUnsigned(collection, countSelector);
    if (count != order.count) return nil;

    NSMutableArray *matches = [NSMutableArray array];
    for (NSUInteger index = 0; index < count; index++) {
        id face = MYSendObjectUnsigned(collection, faceSelector, index);
        if ([MYFaceBundleIdentifier(face) isEqualToString:MYSystemBundleID]) {
            NSString *uuid = MYUUIDString(order[index]);
            if (uuid) {
                [matches addObject:@{ @"uuid": uuid, @"face": face }];
            }
        }
    }
    return matches.count == 1 ? matches.firstObject : nil;
}

static void MYWriteRecord(NSString *stage, NSDictionary *fields, BOOL complete) {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:fields ?: @{}];
    result[@"stage"] = stage;
    result[@"complete"] = @(complete);
    NSString *runID = NSProcessInfo.processInfo.environment[@"WATCHFACELAB_SYSTEM_RUN_ID"];
    if (runID.length > 0) result[@"runID"] = runID;
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSError *writeError = nil;
    NSString *resultPath = [documents stringByAppendingPathComponent:
        @"WatchFaceLab-SystemFaceResult.json"];
    if (!data || ![data writeToFile:resultPath options:NSDataWritingAtomic error:&writeError]) {
        NSLog(@"SYSTEM_FACE_RESULT_WRITE_ERROR %@", writeError.localizedDescription ?: @"unknown");
    }
    NSLog(complete ? @"SYSTEM_FACE_RESULT %@" : @"SYSTEM_FACE_PROGRESS %@", json);
}

static void MYLogResult(NSString *stage, NSDictionary *fields) {
    MYWriteRecord(stage, fields, YES);
}

static void MYLogProgress(NSString *action) {
    MYWriteRecord(@"probe-entered", @{ @"action": action }, NO);
}

static id MYLoadedCollection(BOOL requireMutationABI) {
    if (![NSThread isMainThread] ||
        ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
        MYLogResult(@"preflight", @{ @"pass": @NO, @"error": @"unexpected host or thread" });
        return nil;
    }

    Class cls = objc_lookUpClass("NTKPersistentFaceCollection");
    SEL shared = sel_registerName("sharedLibraryCollection");
    SEL loaded = sel_registerName("hasLoaded");
    SEL count = sel_registerName("numberOfFaces");
    SEL faceAtIndex = sel_registerName("faceAtIndex:");
    SEL ordered = sel_registerName("orderedUUIDs");
    SEL selected = sel_registerName("selectedUUID");
    SEL add = sel_registerName("addFace:atIndex:suppressingCallbackToObserver:");
    SEL remove = sel_registerName("removeFace:suppressingCallbackToObserver:");
    SEL select = sel_registerName("_selectFaceUUID:notify:");
    if (!cls || ![cls respondsToSelector:shared]) {
        MYLogResult(@"preflight", @{ @"pass": @NO,
            @"error": @"NTKPersistentFaceCollection unavailable" });
        return nil;
    }

    id collection = MYSendObject((id)cls, shared);
    Class concrete = object_getClass(collection);
    NSDictionary *abi = @{
        @"loaded": MYEncoding(concrete, loaded),
        @"count": MYEncoding(concrete, count),
        @"faceAtIndex": MYEncoding(concrete, faceAtIndex),
        @"orderedUUIDs": MYEncoding(concrete, ordered),
        @"selectedUUID": MYEncoding(concrete, selected),
        @"add": MYEncoding(concrete, add),
        @"remove": MYEncoding(concrete, remove),
        @"select": MYEncoding(concrete, select),
    };
    BOOL readABI =
        [abi[@"loaded"] isEqualToString:@"B16@0:8"] &&
        [abi[@"count"] isEqualToString:@"Q16@0:8"] &&
        [abi[@"faceAtIndex"] isEqualToString:@"@24@0:8Q16"] &&
        [abi[@"orderedUUIDs"] isEqualToString:@"@16@0:8"] &&
        [abi[@"selectedUUID"] isEqualToString:@"@16@0:8"];
    BOOL mutationABI =
        [abi[@"add"] isEqualToString:@"v40@0:8@16Q24@32"] &&
        [abi[@"remove"] isEqualToString:@"v32@0:8@16@24"] &&
        [abi[@"select"] isEqualToString:@"v28@0:8@16B24"];
    MYLastCollectionABI = abi;
    MYLastMutationABIMatches = mutationABI;
    if (!collection || !readABI || (requireMutationABI && !mutationABI)) {
        MYLogResult(@"preflight", @{ @"pass": @NO, @"abi": abi,
            @"readABI": @(readABI), @"mutationABI": @(mutationABI) });
        return nil;
    }
    NSDictionary *initialState = MYCollectionDiagnostics(collection);
    NSDictionary *deviceState = MYCurrentDeviceDiagnostics();
    if (!MYWaitUntil(^BOOL { return MYSendBool(collection, loaded); }, 12.0)) {
        NSDictionary *timeoutState = MYCollectionDiagnostics(collection);
        NSDictionary *xpcRegistrationProbe = MYXPCRegistrationErrorProbe(collection);
        if (MYWaitUntil(^BOOL { return MYSendBool(collection, loaded); }, 5.0)) {
            return collection;
        }
        BOOL retryAttempted = NO;
        if ([timeoutState[@"registrationNeeded"] boolValue] &&
            [MYEncoding(concrete, sel_registerName("_registerIfNeeded")) isEqualToString:@"v16@0:8"]) {
            retryAttempted = YES;
            ((void (*)(id, SEL))objc_msgSend)(collection, sel_registerName("_registerIfNeeded"));
            if (MYWaitUntil(^BOOL { return MYSendBool(collection, loaded); }, 8.0)) {
                return collection;
            }
        }
        MYLogResult(@"preflight", @{ @"pass": @NO, @"abi": abi,
            @"error": @"collection load timeout",
            @"initialState": initialState,
            @"timeoutState": timeoutState,
            @"finalState": MYCollectionDiagnostics(collection),
            @"deviceState": deviceState,
            @"xpcRegistrationProbe": xpcRegistrationProbe,
            @"retryAttempted": @(retryAttempted),
            @"registerIfNeededEncoding": MYEncoding(concrete,
                sel_registerName("_registerIfNeeded")) });
        return nil;
    }
    return collection;
}

static NSDictionary *MYCollectionSnapshot(id collection) {
    SEL countSelector = sel_registerName("numberOfFaces");
    SEL faceSelector = sel_registerName("faceAtIndex:");
    SEL orderSelector = sel_registerName("orderedUUIDs");
    SEL selectedSelector = sel_registerName("selectedUUID");
    NSUInteger count = MYSendUnsigned(collection, countSelector);
    NSArray *order = MYSendObject(collection, orderSelector) ?: @[];
    NSMutableArray *identifiers = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        id face = MYSendObjectUnsigned(collection, faceSelector, index);
        [identifiers addObject:MYFaceBundleIdentifier(face) ?: @"nil"];
    }
    NSString *candidate = [NSUserDefaults.standardUserDefaults stringForKey:MYCandidateUUIDKey];
    NSString *candidateSource = candidate ? @"defaults" : @"none";
    BOOL candidateOrdered = NO;
    for (id uuid in order) {
        if ([[MYUUIDString(uuid) uppercaseString] isEqualToString:[candidate uppercaseString]]) {
            candidateOrdered = YES;
            break;
        }
    }
    if (!candidateOrdered) {
        NSDictionary *entry = MYUniqueCustomFaceEntry(collection);
        candidate = entry[@"uuid"];
        if (candidate) {
            candidateSource = @"collection";
            candidateOrdered = YES;
        }
    }
    return @{
        @"count": @(count),
        @"orderedCount": @(order.count),
        @"selectedUUID": MYUUIDString(MYSendObject(collection, selectedSelector)) ?: @"nil",
        @"candidateUUID": candidate ?: @"nil",
        @"candidateSource": candidateSource,
        @"candidateOrdered": @(candidateOrdered),
        @"bundleIdentifiers": identifiers,
        @"customResolved": @([identifiers containsObject:MYSystemBundleID]),
    };
}

static BOOL MYSystemFaceBoundaryPreflightImpl(void) {
    if (![NSThread isMainThread] ||
        ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
        MYLogResult(@"boundary", @{ @"pass": @NO,
            @"error": @"unexpected host or thread" });
        return NO;
    }

    NSDictionary *sandbox = MYSandboxBoundaryDiagnostics();
    NSDictionary *entitlements = MYSignedEntitlementDiagnostics();
    BOOL apiPresent = [sandbox[@"apiPresent"] boolValue];
    BOOL querySucceeded = [sandbox[@"querySucceeded"] boolValue];
    BOOL allowed = [sandbox[@"allowed"] boolValue];
    NSString *error = nil;
    if (!apiPresent) {
        error = @"sandbox_check unavailable";
    } else if (!querySucceeded) {
        error = @"sandbox_check query failed";
    } else if (!allowed) {
        error = @"collection server Mach lookup denied by app sandbox";
    }
    NSMutableDictionary *record = [@{
        @"pass": @(apiPresent && querySucceeded && allowed),
        @"probeOnly": @YES,
        @"xpcRequestSent": @NO,
        @"sandbox": sandbox,
        @"signedEntitlements": entitlements,
    } mutableCopy];
    if (error) record[@"error"] = error;
    MYLogResult(@"boundary", record);
    return apiPresent && querySucceeded && allowed;
}

static BOOL MYSystemFaceCollectionPreflightImpl(void) {
    id collection = MYLoadedCollection(NO);
    if (!collection) return NO;
    NSMutableDictionary *snapshot = [MYCollectionSnapshot(collection) mutableCopy];
    snapshot[@"pass"] = @YES;
    snapshot[@"abi"] = MYLastCollectionABI ?: @{};
    snapshot[@"mutationABI"] = @(MYLastMutationABIMatches);
    MYLogResult(@"preflight", snapshot);
    return YES;
}

static BOOL MYSystemFaceInstallCandidateImpl(NSString *directoryPath) {
    id collection = MYLoadedCollection(YES);
    if (!collection) return NO;
    NSDictionary *before = MYCollectionSnapshot(collection);
    if ([before[@"candidateOrdered"] boolValue] || [before[@"customResolved"] boolValue]) {
        MYLogResult(@"install", @{ @"pass": @NO,
            @"error": @"candidate already present", @"snapshot": before });
        return NO;
    }
    MYCustomFace *face = MYRestoreLocalFaceBundle(directoryPath);
    if (!face || ![MYFaceBundleIdentifier(face) isEqualToString:MYSystemBundleID]) {
        MYLogResult(@"install", @{ @"pass": @NO,
            @"error": @"local custom face creation failed" });
        return NO;
    }

    SEL countSelector = sel_registerName("numberOfFaces");
    SEL orderSelector = sel_registerName("orderedUUIDs");
    SEL addSelector = sel_registerName("addFace:atIndex:suppressingCallbackToObserver:");
    NSUInteger countBefore = MYSendUnsigned(collection, countSelector);
    NSArray *orderBefore = [MYSendObject(collection, orderSelector) copy] ?: @[];
    NSString *selectedBefore = before[@"selectedUUID"];
    ((void (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(
        collection, addSelector, face, countBefore, nil);
    BOOL added = MYWaitUntil(^BOOL {
        return MYSendUnsigned(collection, countSelector) == countBefore + 1;
    }, 12.0);
    NSArray *orderAfter = [MYSendObject(collection, orderSelector) copy] ?: @[];
    NSMutableSet *newUUIDs = [NSMutableSet setWithArray:orderAfter];
    [newUUIDs minusSet:[NSSet setWithArray:orderBefore]];
    id candidateObject = newUUIDs.count == 1 ? newUUIDs.anyObject : nil;
    NSString *candidate = MYUUIDString(candidateObject);
    if (candidate) {
        // Persist the recovery handle even if a later acceptance check fails.
        [NSUserDefaults.standardUserDefaults setObject:candidate forKey:MYCandidateUUIDKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    if (!added || !candidate) {
        MYLogResult(@"install", @{ @"pass": @NO,
            @"error": @"add did not produce one UUID",
            @"countBefore": @(countBefore), @"countAfter": @(MYSendUnsigned(collection, countSelector)),
            @"newUUIDCount": @(newUUIDs.count) });
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:candidate forKey:MYCandidateUUIDKey];
    if (![selectedBefore isEqualToString:@"nil"]) {
        [defaults setObject:selectedBefore forKey:MYPreviousUUIDKey];
    }
    [defaults synchronize];
    MYLogResult(@"install", @{ @"pass": @YES, @"candidateUUID": candidate,
        @"selected": @NO, @"snapshot": MYCollectionSnapshot(collection) });
    return YES;
}

static BOOL MYSystemFaceSelectCandidateImpl(void) {
    id collection = MYLoadedCollection(YES);
    if (!collection) return NO;
    NSDictionary *snapshot = MYCollectionSnapshot(collection);
    if (![snapshot[@"customResolved"] boolValue]) {
        MYLogResult(@"select", @{ @"pass": @NO,
            @"error": @"candidate bundle is not resolvable in this process",
            @"snapshot": snapshot });
        return NO;
    }
    NSString *candidate = snapshot[@"candidateUUID"];
    if ([candidate isEqualToString:@"nil"]) {
        MYLogResult(@"select", @{ @"pass": @NO, @"error": @"candidate UUID missing" });
        return NO;
    }
    NSArray *order = MYSendObject(collection, sel_registerName("orderedUUIDs")) ?: @[];
    id candidateObject = nil;
    for (id uuid in order) {
        if ([[MYUUIDString(uuid) uppercaseString] isEqualToString:[candidate uppercaseString]]) {
            candidateObject = uuid;
            break;
        }
    }
    if (!candidateObject) {
        MYLogResult(@"select", @{ @"pass": @NO,
            @"error": @"candidate not returned by system collection",
            @"snapshot": MYCollectionSnapshot(collection) });
        return NO;
    }
    SEL selectSelector = sel_registerName("_selectFaceUUID:notify:");
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(collection, selectSelector, candidateObject, YES);
    BOOL selected = MYWaitUntil(^BOOL {
        return [MYSendObject(collection, sel_registerName("selectedUUID")) isEqual:candidateObject];
    }, 12.0);
    MYLogResult(@"select", @{ @"pass": @(selected), @"candidateUUID": candidate,
        @"snapshot": MYCollectionSnapshot(collection) });
    return selected;
}

static BOOL MYSystemFaceRollbackCandidateImpl(void) {
    id collection = MYLoadedCollection(YES);
    if (!collection) return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *candidate = [defaults stringForKey:MYCandidateUUIDKey];
    if (!candidate) {
        candidate = MYUniqueCustomFaceEntry(collection)[@"uuid"];
    }
    if (!candidate) {
        MYLogResult(@"rollback", @{ @"pass": @YES, @"removed": @NO,
            @"reason": @"candidate UUID absent" });
        return YES;
    }
    NSArray *order = MYSendObject(collection, sel_registerName("orderedUUIDs")) ?: @[];
    NSUInteger index = NSNotFound;
    id candidateObject = nil;
    for (NSUInteger i = 0; i < order.count; i++) {
        if ([[MYUUIDString(order[i]) uppercaseString] isEqualToString:[candidate uppercaseString]]) {
            index = i;
            candidateObject = order[i];
            break;
        }
    }
    if (index == NSNotFound) {
        [defaults removeObjectForKey:MYCandidateUUIDKey];
        [defaults removeObjectForKey:MYPreviousUUIDKey];
        [defaults synchronize];
        MYLogResult(@"rollback", @{ @"pass": @YES, @"removed": @NO,
            @"reason": @"candidate already absent" });
        return YES;
    }
    id face = MYSendObjectUnsigned(collection, sel_registerName("faceAtIndex:"), index);
    if (!face) {
        MYLogResult(@"rollback", @{ @"pass": @NO,
            @"error": @"candidate UUID has no removable face object" });
        return NO;
    }
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        collection, sel_registerName("removeFace:suppressingCallbackToObserver:"), face, nil);
    BOOL removed = MYWaitUntil(^BOOL {
        NSArray *current = MYSendObject(collection, sel_registerName("orderedUUIDs")) ?: @[];
        return ![current containsObject:candidateObject];
    }, 12.0);
    NSString *previous = [defaults stringForKey:MYPreviousUUIDKey];
    if (removed && previous) {
        NSArray *current = MYSendObject(collection, sel_registerName("orderedUUIDs")) ?: @[];
        for (id uuid in current) {
            if ([[MYUUIDString(uuid) uppercaseString] isEqualToString:[previous uppercaseString]]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(collection,
                    sel_registerName("_selectFaceUUID:notify:"), uuid, YES);
                break;
            }
        }
    }
    if (removed) {
        [defaults removeObjectForKey:MYCandidateUUIDKey];
        [defaults removeObjectForKey:MYPreviousUUIDKey];
        [defaults synchronize];
    }
    MYLogResult(@"rollback", @{ @"pass": @(removed), @"removed": @(removed),
        @"snapshot": MYCollectionSnapshot(collection) });
    return removed;
}

static BOOL MYRunProtected(NSString *stage, BOOL (^operation)(void)) {
    @try {
        return operation();
    } @catch (NSException *exception) {
        MYLogResult(stage, @{ @"pass": @NO, @"error": @"Objective-C exception",
            @"exception": exception.name ?: @"unknown",
            @"reason": exception.reason ?: @"unknown" });
        return NO;
    }
}

__attribute__((visibility("default"))) BOOL MYSystemFaceCollectionPreflight(void) {
    MYLogProgress(@"preflight");
    return MYRunProtected(@"preflight", ^BOOL {
        return MYSystemFaceCollectionPreflightImpl();
    });
}

__attribute__((visibility("default"))) BOOL MYSystemFaceBoundaryPreflight(void) {
    MYLogProgress(@"boundary");
    return MYRunProtected(@"boundary", ^BOOL {
        return MYSystemFaceBoundaryPreflightImpl();
    });
}

__attribute__((visibility("default"))) BOOL MYSystemFaceInstallCandidate(NSString *directoryPath) {
    MYLogProgress(@"install");
    return MYRunProtected(@"install", ^BOOL {
        return MYSystemFaceInstallCandidateImpl(directoryPath);
    });
}

__attribute__((visibility("default"))) BOOL MYSystemFaceSelectCandidate(void) {
    MYLogProgress(@"select");
    return MYRunProtected(@"select", ^BOOL {
        return MYSystemFaceSelectCandidateImpl();
    });
}

__attribute__((visibility("default"))) BOOL MYSystemFaceRollbackCandidate(void) {
    MYLogProgress(@"rollback");
    return MYRunProtected(@"rollback", ^BOOL {
        return MYSystemFaceRollbackCandidateImpl();
    });
}
