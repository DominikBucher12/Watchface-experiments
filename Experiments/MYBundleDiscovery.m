#import "MYCustomFace.h"

BOOL MYDiscoverLocalFaceBundle(NSString *directoryPath) {
    if (![NSThread isMainThread] ||
        !([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"] || [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.ClockFaceLab"])) {
        NSLog(@"Local bundle PoC requires WatchFaceLab on the main thread");
        return NO;
    }
    if (directoryPath.length == 0 || !directoryPath.isAbsolutePath) return NO;
    NSURL *directoryURL = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    NSURL *bundleURL = [directoryURL URLByAppendingPathComponent:@"MYLocalFaceBundle.bundle"
                                                   isDirectory:YES];
    NSBundle *diskBundle = [NSBundle bundleWithURL:bundleURL];
    NSString *identifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
    if (!diskBundle || ![diskBundle.bundleIdentifier isEqualToString:identifier] ||
        ![[diskBundle objectForInfoDictionaryKey:@"NSPrincipalClass"] isEqual:@"MYLocalFaceBundle"]) {
        NSLog(@"Local bundle PoC: missing or unexpected metadata at %@", bundleURL.path);
        return NO;
    }
    NSLog(@"Local bundle PoC: metadata validated; alreadyLoaded=%d; directory=%@",
          diskBundle.isLoaded, directoryURL.path);
    // The installed factory forwards the directory collection to initWithURLs:.
    // NTKFaceBundleManager uses a set of file URLs; use the same collection shape.
    NTKFaceBundleLoader *loader = [NTKFaceBundleLoader faceBundleLoaderWithDirectories:
                                  [NSSet setWithObject:directoryURL]
    appBundleIdentifierPrefixes:[NSSet setWithObject:@"dev.develodom.WatchFaceLab"]];
    if (!loader) return NO;
    NSLog(@"Local bundle PoC: isolated loader created; looking up %@", identifier);
    NTKFaceBundle *bundle = [loader loadFaceBundleWithIdentifier:identifier];
    if (!bundle || ![bundle isKindOfClass:NTKFaceBundle.class] ||
        ![NSStringFromClass(bundle.class) isEqualToString:@"MYLocalFaceBundle"]) {
        NSLog(@"Local bundle PoC: unexpected result %@", bundle);
        return NO;
    }
    NSBundle *classBundle = [NSBundle bundleForClass:bundle.class];
    NSString *expectedPath = bundleURL.URLByResolvingSymlinksInPath.path;
    if (![classBundle.bundleURL.URLByResolvingSymlinksInPath.path isEqualToString:expectedPath] ||
        ![classBundle.bundleIdentifier isEqualToString:identifier] ||
        ![classBundle.bundleIdentifier isEqualToString:identifier]) {
        NSLog(@"Local bundle PoC: class identity mismatch: %@", classBundle.bundlePath);
        return NO;
    }
    if ([bundle faceClass] != MYCustomFace.class ||
        [bundle faceViewClass] != MYCustomFaceView.class) return NO;
    CLKDevice *device = [CLKDevice currentDevice];
    if (!device) return NO;
    NSLog(@"Local bundle PoC: identity verified; creating default face");
    NTKFace *face = [bundle defaultFaceForDevice:device];
    if (![face isKindOfClass:MYCustomFace.class]) return NO;
    NTKFaceView *renderer = [NTKFaceView newFaceViewForFace:face];
    if (![renderer isKindOfClass:MYCustomFaceView.class] || !renderer.timeView) return NO;
    NSLog(@"Local bundle PoC PASS: identifier=%@ bundle=%@ face=%@ renderer=%@ timeView=%@",
          classBundle.bundleIdentifier, NSStringFromClass(bundle.class),
          NSStringFromClass(face.class), NSStringFromClass(renderer.class),
          NSStringFromClass(renderer.timeView.class));
    // Local objects are released normally. NSBundle/Objective-C image loading is
    // process-wide and persists until app exit; no unloading is attempted.
    return YES;
}

MYCustomFace *MYRestoreLocalFaceBundle(NSString *directoryPath) {
    // Preserve the original discovery assertions, including class/image identity.
    if (!MYDiscoverLocalFaceBundle(directoryPath)) return nil;
    NSString *identifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
    NSURL *directoryURL = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    NTKFaceBundleLoader *loader = [NTKFaceBundleLoader faceBundleLoaderWithDirectories:
                                  [NSSet setWithObject:directoryURL]
    appBundleIdentifierPrefixes:[NSSet setWithObject:@"dev.develodom.WatchFaceLab"]];
    NTKFaceBundle *bundle = [loader loadFaceBundleWithIdentifier:identifier];
    if (!bundle || [bundle faceClass] != MYCustomFace.class) return nil;
    CLKDevice *device = [CLKDevice currentDevice];
    if (!device) return nil;
    NSLog(@"Local identity PoC: entering bundled-face factory on MYCustomFace");
    NTKFace *face = [[bundle faceClass] bundledFaceWithIdentifier:identifier
                                                     forDevice:device initCustomization:nil];
    // The installed bundled-face factory explicitly requests 0x2c (44).
    if (![face isKindOfClass:MYCustomFace.class] || face.faceStyle != 44 ||
        ![face.bundleIdentifier isEqualToString:identifier]) {
        NSLog(@"Local identity PoC: factory failed to preserve class/identifier");
        return nil;
    }
    NSLog(@"Local identity PoC: model class=%@ style=%ld identifier=%@",
          NSStringFromClass(face.class), (long)face.faceStyle, face.bundleIdentifier);
    NSDictionary *json = [face JSONObjectRepresentation];
    if (![json isKindOfClass:NSDictionary.class] ||
        ![json[NTKFaceBundleIdentifierKey] isEqual:identifier] ||
        ![NSJSONSerialization isValidJSONObject:json]) return nil;
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (!jsonData) {
        NSLog(@"Local identity PoC: JSON encoding failed: %@", error);
        return nil;
    }
    NSLog(@"Local identity PoC: serialized faceType=%@ JSON bytes=%lu",
          json[NTKFaceBundleFaceTypeKey], (unsigned long)jsonData.length);
    NTKFaceInstanceDescriptor *descriptor = [[NTKFaceInstanceDescriptor alloc]
        initWithJSONRepresentation:jsonData resourceDirectory:nil];
    if (!descriptor) return nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:descriptor
                                         requiringSecureCoding:YES error:&error];
    if (!archive) {
        NSLog(@"Local identity PoC: descriptor archive failed: %@", error);
        return nil;
    }
    NSLog(@"Local identity PoC: entering bundle faceFromData:, archive bytes=%lu",
          (unsigned long)archive.length);
    NTKFace *restored = [bundle faceFromData:archive];
    if (![restored isKindOfClass:MYCustomFace.class] ||
        ![restored.bundleIdentifier isEqualToString:identifier] ||
        restored.faceStyle != face.faceStyle) {
        NSLog(@"Local identity PoC: restored class/style/identifier mismatch");
        return nil;
    }
    NSDictionary *restoredJSON = [restored JSONObjectRepresentation];
    if (![json isEqual:restoredJSON]) {
        NSLog(@"Local identity PoC: JSON changed during round trip; before=%@ after=%@",
              json, restoredJSON);
        return nil;
    }
    NTKFaceView *renderer = [NTKFaceView newFaceViewForFace:restored];
    if (![renderer isKindOfClass:MYCustomFaceView.class] || !renderer.timeView) return nil;
    NSLog(@"Local identity PoC PASS: class=%@ style=%ld identifier=%@ JSON equal=1 renderer=%@",
          NSStringFromClass(restored.class), (long)restored.faceStyle,
          restored.bundleIdentifier, NSStringFromClass(renderer.class));
    return (MYCustomFace *)restored;
}

BOOL MYRoundTripLocalFaceBundle(NSString *directoryPath) {
    return MYRestoreLocalFaceBundle(directoryPath) != nil;
}

BOOL MYInspectLocalFaceGallery(NSString *directoryPath) {
    if (!MYDiscoverLocalFaceBundle(directoryPath)) return NO;
    NSString *identifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
    NSURL *url = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    NTKFaceBundleLoader *loader = [NTKFaceBundleLoader faceBundleLoaderWithDirectories:
                                  [NSSet setWithObject:url]
    appBundleIdentifierPrefixes:[NSSet setWithObject:@"dev.develodom.WatchFaceLab"]];
    NTKFaceBundle *bundle = [loader loadFaceBundleWithIdentifier:identifier];
    CLKDevice *device = [CLKDevice currentDevice];
    if (!bundle || !device || [bundle faceClass] != MYCustomFace.class) return NO;
    BOOL restricted = [[bundle faceClass] isRestrictedForDevice:device];
    NSLog(@"Local gallery PoC: inherited device restriction=%d", restricted);
    if (restricted) return NO;
    NSString *title = [bundle galleryTitleForDevice:device];
    NSString *description = [bundle galleryDescriptionForDevice:device];
    if (![title isKindOfClass:NSString.class] || title.length == 0 ||
        ![description isKindOfClass:NSString.class] || description.length == 0) return NO;
    // The installed base method returns nil; no undocumented priority format is supplied.
    id priorities = [bundle galleryRowPrioritiesForDevice:device];
    NSLog(@"Local gallery PoC: title=%@ description=%@ rowPriorities=%@",
          title, description, priorities);
    NSLog(@"Local gallery PoC: requesting gallery faces");
    NSArray<NTKFace *> *faces = [bundle galleryFacesForDevice:device];
    if (![faces isKindOfClass:NSArray.class] || faces.count != 1) {
        NSLog(@"Local gallery PoC: expected one face, got %@", faces);
        return NO;
    }
    NTKFace *face = faces.firstObject;
    if (![face isKindOfClass:MYCustomFace.class] || face.faceStyle != 44 ||
        ![face.bundleIdentifier isEqualToString:identifier]) return NO;
    NSDictionary *json = [face JSONObjectRepresentation];
    if (![json isKindOfClass:NSDictionary.class] ||
        ![json[NTKFaceBundleIdentifierKey] isEqual:identifier] ||
        ![NSJSONSerialization isValidJSONObject:json]) return NO;
    NTKFaceView *renderer = [NTKFaceView newFaceViewForFace:face];
    if (![renderer isKindOfClass:MYCustomFaceView.class] || !renderer.timeView) return NO;
    NSLog(@"Local gallery PoC PASS: faces=%lu title=%@ class=%@ style=%ld identifier=%@ renderer=%@",
          (unsigned long)faces.count, title, NSStringFromClass(face.class),
          (long)face.faceStyle, face.bundleIdentifier, NSStringFromClass(renderer.class));
    return YES;
}

static NTKFacesBundleArrayGalleryCollection *MYNativeGallery;

static BOOL MYGalleryAppContext(void) {
    return [NSThread isMainThread] &&
        ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"] || [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.ClockFaceLab"]);
}

BOOL MYStartNativeGalleryCollection(NSString *directoryPath) {
    if (!MYGalleryAppContext()) return NO;
    if (MYNativeGallery) {
        NSLog(@"Native gallery PoC: existing collection; check/release it before starting again");
        return NO;
    }
    if (!MYInspectLocalFaceGallery(directoryPath)) return NO;
    NSURL *url = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    NTKFaceBundleLoader *loader = [NTKFaceBundleLoader faceBundleLoaderWithDirectories:
                                  [NSSet setWithObject:url]
    appBundleIdentifierPrefixes:[NSSet setWithObject:@"dev.develodom.WatchFaceLab"]];
    NTKFaceBundle *bundle = [loader loadFaceBundleWithIdentifier:
                            @"dev.develodom.WatchFaceLab.LocalFaceBundle"];
    CLKDevice *device = [CLKDevice currentDevice];
    if (!bundle || !device) return NO;
    NSLog(@"Native gallery PoC: entering initWithDevice:faceBundle:");
    NTKFacesBundleArrayGalleryCollection *collection =
        [[NTKFacesBundleArrayGalleryCollection alloc] initWithDevice:device faceBundle:bundle];
    if (!collection) return NO;
    if (![[collection title] isEqualToString:[bundle galleryTitleForDevice:device]] ||
        ![[collection descriptionText] isEqualToString:[bundle galleryDescriptionForDevice:device]]) {
        NSLog(@"Native gallery PoC: collection metadata mismatch");
        return NO;
    }
    MYNativeGallery = collection;
    NSLog(@"Native gallery PoC: metadata accepted; scheduling loadFaces");
    [collection loadFaces];
    NSLog(@"Native gallery PoC STARTED: resume the app before checking; this is not a load-success result");
    return YES;
}

BOOL MYCheckNativeGalleryCollection(void) {
    if (!MYGalleryAppContext() || !MYNativeGallery) return NO;
    NSUInteger count = [MYNativeGallery numberOfFaces];
    NSLog(@"Native gallery PoC: collection=%@ title=%@ faces=%lu",
          NSStringFromClass(MYNativeGallery.class), [MYNativeGallery title], (unsigned long)count);
    if (count != 1) {
        NSLog(@"Native gallery PoC: expected one face; zero may mean pending load or empty/failed result. Preserve logs and resume before rechecking");
        return NO;
    }
    NTKFace *face = [MYNativeGallery faceAtIndex:0];
    NSString *identifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
    if (![face isKindOfClass:MYCustomFace.class] || face.faceStyle != 44 ||
        ![face.bundleIdentifier isEqualToString:identifier]) {
        NSLog(@"Native gallery PoC: collection model class/style/identity mismatch");
        return NO;
    }
    NSDictionary *json = [face JSONObjectRepresentation];
    if (![json isKindOfClass:NSDictionary.class] ||
        ![json[NTKFaceBundleIdentifierKey] isEqual:identifier] ||
        ![NSJSONSerialization isValidJSONObject:json]) return NO;
    NTKFaceView *renderer = [NTKFaceView newFaceViewForFace:face];
    if (![renderer isKindOfClass:MYCustomFaceView.class] || !renderer.timeView) return NO;
    NSLog(@"Native gallery PoC PASS: native collection faces=1 class=%@ style=%ld identifier=%@ renderer=%@",
          NSStringFromClass(face.class), (long)face.faceStyle,
          face.bundleIdentifier, NSStringFromClass(renderer.class));
    return YES;
}

void MYReleaseNativeGalleryCollection(void) {
    if (!MYGalleryAppContext()) return;
    MYNativeGallery = nil;
    NSLog(@"Native gallery PoC: experiment collection ownership released; pending framework work is not cancelled");
}
