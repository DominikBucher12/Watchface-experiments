# NanoTimeKit Argon and bundle manager findings

**Target binary:** `NanoTimeKit.framework/NanoTimeKit`, watchOS 27.0.1 (24R365).  
**Loaded device UUID:** `4EB0531F-4C9E-343F-9A9A-04C66F69934C` (arm64e).  
**Alternate inspected slice:** `EFE5A375-CC31-37EA-B3D0-CB0AC4486A36` (arm64e.x1).

## Evidence levels

- **Runtime confirmed:** methods/classes from Objective-C introspection on physical Apple Watch; where stated, observed execution.
- **Static:** reverse engineering/disassembly of DeviceSupport NanoTimeKit. Functions and offsets refer to this specific build and were not independently retested in `ClockFace`.
- **Hypothesis:** system trust/registration behavior not demonstrated by these PoCs.

## Runtime classes

Present (`objc_getClass`): `NTKArgonManager`, `NTKArgonExtractor`, `NTKArgonKeyDescriptor`, `NTKArgonLocalKeyDatabase`, `NTKArgonCloudKitClient`, `NTKAppleEncryptedArchiveDiskExtractor`, `NTKFaceBundleManager`, `NTKFaceBundleLoader`.

`NTKFaceSupportServerInterface` returned `present=0` **as a loaded runtime class**. This does not disprove its existence as an XPC protocol or service.

Representative selectors observed:

| Class | Selectors |
| --- | --- |
| `NTKArgonManager` | `refreshWithReason:`, `extractKnownKeyDescriptorsIfNeededWithCompletion:`, `_queue_extractedKeyDescriptors`, `initWithKeyDatabase:fetchers:extractor:` |
| `NTKArgonExtractor` | `initWithSourcePath:inProgressPath:extractionPath:`, `extractUsingKeyDescriptor:completion:`, `extractionPath` |
| `NTKArgonKeyDescriptor` | `keyDescriptorFromBundle:`, `unfilteredKeyDescriptorFromBundle:`, `argon_JSONRepresentation`, `fileName`, `key` |
| `NTKArgonLocalKeyDatabase` | `enumerateKeyDescriptors:`, `keyDescriptorForFileName:`, `initWithKeyStoragePath:` |
| `NTKAppleEncryptedArchiveDiskExtractor` | `initWithArchiveURL:symmetricKey:outputDirectoryURL:fileProtection:completion:`, `verifyExtractedContentsWithError:` |
| `NTKFaceBundleManager` | `enumerateArgonKeyDescriptorsWithBlock:`, `loadKeyDescriptor:`, `argonUpdated:`, `_generateLookupsIfNecessary`, `_resetCaches`, `sharedManager` |
| `NTKFaceBundleLoader` | `faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:`, `loadFaceBundleWithIdentifier:`, `initWithURLs:bundleIdentifierPrefixes:` |

### Confirmed Objective-C type encodings

```
-[NTKFaceBundleManager enumerateArgonKeyDescriptorsWithBlock:]       v24@0:8@?16
-[NTKFaceBundleManager loadKeyDescriptor:]                           B24@0:8@16
-[NTKFaceBundleManager argonUpdated:]                                 v24@0:8@16
+[NTKFaceBundleManager sharedManager]                                 @16@0:8
+[NTKArgonKeyDescriptor keyDescriptorFromBundle:]                    @24@0:8@16
+[NTKArgonKeyDescriptor unfilteredKeyDescriptorFromBundle:]          @24@0:8@16
-[NTKArgonKeyDescriptor argon_JSONRepresentation]                    @16@0:8
-[NTKArgonManager _queue_extractedKeyDescriptors]                    @16@0:8
-[NTKArgonExtractor extractionPath]                                   @16@0:8
+[NTKFaceBundleLoader faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:] @32@0:8@16@24
```

**Critical ABI lesson:** Objective-C method encoding `@?` does **not** specify block callback arguments. Initial descriptor probe assumed one `id` argument; later disassembly suggested `void (^)(NSUInteger, id)` for this build. Both the original and corrected descriptor tests generated sandbox directory errors, **no usable final count was provided**. Do not treat descriptor enumeration as validated or `0`.

## Static architecture findings (build-specific)

- `-[NTKArgonManager refreshWithReason:]` invokes descriptor/extraction workflow via `_queue_extractKnownKeyDescriptorsIfNeededWithCompletion:`; the extraction stack includes `.aea` encrypted archive processing and key database.
- `_NTKQueryFaceSupportServerForNewFaces` uses XPC service name `com.apple.nanotimekit.facesupportserver`; associated interface exposes `knownKeyDescriptors:` and `displayUserNotificationForKeyDescriptor:completion:`.
- Internal feature flags referenced include `NanoTimeKitExtras/argon_manual_mode` and `NanoTimeKitExtras/load_unencrypted_argon_bundles`, with internal-build gating. These are **not** documented external APIs.
- `_NTKAskFaceSupportServerToAddKeyDescriptor` is called from `-[NTKFaceBundleManager loadKeyDescriptor:]` (static disassembly). The latter resets caches on success; no successful third-party registration was tested.
- `_generateLookupsIfNecessary` builds face lookup caches from loader-discovered classes; `argonUpdated:` resets caches and posts an update notification (static disassembly).
- Extracted path seen in actual logs: `/var/mobile/Library/NanoTimeKit/FaceSupport/ExtractedBundles/24R365`; the build-specific suffix was observed on device.

Conceptual pathway (some edges inferred):

```
FaceSupportServer (XPC / descriptor distribution)
      -> Argon manager / key database / extractor
      -> extracted bundle area
      -> NTKFaceBundleManager / NTKFaceBundleLoader
      -> consumer process (e.g. ClockFace)
```

## On-device access failures

The `ARGON_DESCRIPTOR` probes attempted directory enumeration. Reported:

```
/AppleInternal/Library/NanoTimeKit/FaceBundles            -> ENOENT (2)
/var/mobile/Library/NanoTimeKit/FaceSupport/ExtractedBundles/24R365 -> EPERM (1)
```

`ENOENT` = missing path. `EPERM` = WatchFaceLab denied permission (likely sandbox). It **does not establish whether the restricted directory exists**, and is not evidence that the server specifically rejected our custom bundle. A separate log `xpc connection invalidated. This is unrecoverable.` did not identify the affected XPC endpoint.

## Sysdiagnose

Read-only diagnostic on 2026-10-22: `devicectl device sysdiagnose`; `system_logs.logarchive` filtered for Argon-related eventMessage terms yielded **0 matches**. Broader scan of 1,335 small textual files (2,073 archive entries) found `logs/OSEligibility/state.plist` with `ARGON(19): NOT_ELIGIBLE`, reason `DEVICE_CLASS`; its connection to NanoTimeKit's `NTKArgonManager` is **unproven**. OTA logs mention `Argon Migration SLAM` / `Argon Load and install SLAM`—also **not proven related** to watchfaces.

Sysdiagnose may include sensitive contents; do not commit raw archives, full logs, private identifiers or Argon key material to the repository.

## Security and unresolved questions

There is no evidence that third-party app code can be registered as an authorized system `ClockFace` renderer. Discovering an archive format, metadata contract or available Objective-C class is insufficient to establish permission to load executable code. The key question is whether supported non-Apple registration exists and which code-signing/entitlement rules it enforces.
