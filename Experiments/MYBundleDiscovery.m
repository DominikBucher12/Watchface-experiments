#import "MYCustomFace.h"

BOOL MYDiscoverLocalFaceBundle(NSString *directoryPath) {
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
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
                                  [NSSet setWithObject:directoryURL]];
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
        ![[bundle.class identifier] isEqualToString:identifier]) {
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
          [bundle.class identifier], NSStringFromClass(bundle.class),
          NSStringFromClass(face.class), NSStringFromClass(renderer.class),
          NSStringFromClass(renderer.timeView.class));
    // Local objects are released normally. NSBundle/Objective-C image loading is
    // process-wide and persists until app exit; no unloading is attempted.
    return YES;
}

BOOL MYRoundTripLocalFaceBundle(NSString *directoryPath) {
    // Preserve the original discovery assertions, including class/image identity.
    if (!MYDiscoverLocalFaceBundle(directoryPath)) return NO;
    NSString *identifier = @"dev.develodom.WatchFaceLab.LocalFaceBundle";
    NSURL *directoryURL = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    NTKFaceBundleLoader *loader = [NTKFaceBundleLoader faceBundleLoaderWithDirectories:
                                  [NSSet setWithObject:directoryURL]];
    NTKFaceBundle *bundle = [loader loadFaceBundleWithIdentifier:identifier];
    if (!bundle || [bundle faceClass] != MYCustomFace.class) return NO;
    CLKDevice *device = [CLKDevice currentDevice];
    if (!device) return NO;
    NSLog(@"Local identity PoC: entering bundled-face factory on MYCustomFace");
    NTKFace *face = [[bundle faceClass] bundledFaceWithIdentifier:identifier
                                                     forDevice:device initCustomization:nil];
    // The installed bundled-face factory explicitly requests 0x2c (44).
    if (![face isKindOfClass:MYCustomFace.class] || face.faceStyle != 44 ||
        ![face.bundleIdentifier isEqualToString:identifier]) {
        NSLog(@"Local identity PoC: factory failed to preserve class/identifier");
        return NO;
    }
    NSLog(@"Local identity PoC: model class=%@ style=%ld identifier=%@",
          NSStringFromClass(face.class), (long)face.faceStyle, face.bundleIdentifier);
    NSDictionary *json = [face JSONObjectRepresentation];
    if (![json isKindOfClass:NSDictionary.class] ||
        ![json[NTKFaceBundleIdentifierKey] isEqual:identifier] ||
        ![NSJSONSerialization isValidJSONObject:json]) return NO;
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (!jsonData) {
        NSLog(@"Local identity PoC: JSON encoding failed: %@", error);
        return NO;
    }
    NSLog(@"Local identity PoC: serialized faceType=%@ JSON bytes=%lu",
          json[NTKFaceBundleFaceTypeKey], (unsigned long)jsonData.length);
    NTKFaceInstanceDescriptor *descriptor = [[NTKFaceInstanceDescriptor alloc]
        initWithJSONRepresentation:jsonData resourceDirectory:nil];
    if (!descriptor) return NO;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:descriptor
                                         requiringSecureCoding:YES error:&error];
    if (!archive) {
        NSLog(@"Local identity PoC: descriptor archive failed: %@", error);
        return NO;
    }
    NSLog(@"Local identity PoC: entering bundle faceFromData:, archive bytes=%lu",
          (unsigned long)archive.length);
    NTKFace *restored = [bundle faceFromData:archive];
    if (![restored isKindOfClass:MYCustomFace.class] ||
        ![restored.bundleIdentifier isEqualToString:identifier] ||
        restored.faceStyle != face.faceStyle) {
        NSLog(@"Local identity PoC: restored class/style/identifier mismatch");
        return NO;
    }
    NSDictionary *restoredJSON = [restored JSONObjectRepresentation];
    if (![json isEqual:restoredJSON]) {
        NSLog(@"Local identity PoC: JSON changed during round trip; before=%@ after=%@",
              json, restoredJSON);
        return NO;
    }
    NTKFaceView *renderer = [NTKFaceView newFaceViewForFace:restored];
    if (![renderer isKindOfClass:MYCustomFaceView.class] || !renderer.timeView) return NO;
    NSLog(@"Local identity PoC PASS: class=%@ style=%ld identifier=%@ JSON equal=1 renderer=%@",
          NSStringFromClass(restored.class), (long)restored.faceStyle,
          restored.bundleIdentifier, NSStringFromClass(renderer.class));
    return YES;
}
