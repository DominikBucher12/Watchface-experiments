# Container-token escape candidate for the face-library boundary

Status: the iOS mechanism was tested twice on the physical watch and stopped at
token issuance. The route is parked for this stock watchOS build.

## Confirmed mechanism on the related 27.0.1 research target

The local `iOS27-Research-Exploits` evidence demonstrates a container-manager
symlink/token bug on iOS 27.0.1. A caller replaces its own App Group
`Library/Caches` directory with a symlink, asks `containermanagerd` for the
class-7/part-3 path, and consumes the returned sandbox extension. The measured
grant crosses into application, internal-daemon, plug-in, App Group, and
SystemGroup containers. It does not grant `/var/mobile/Library`, and it does not
grant Mach lookup.

This is a filesystem sandbox escape, not a kernel exploit and not a way to mint
private entitlements.

## Relevance to NanoTimeKit

The primitive could matter only if a required `nanotimekitd` collection store
or trusted face resource is located in one of the container classes it can
grant. Current physical-watch evidence instead places FaceSupport extraction at:

```text
/var/mobile/Library/NanoTimeKit/FaceSupport/ExtractedBundles/24R365
```

That path is outside the demonstrated grant set. The persistent collection
store is derived from `_NTKHomeDirectory()/CollectionStores/...`; its resolved
watchOS path has not yet been observed. Even a writable collection store would
not make the custom executable bundle discoverable: the daemon loader currently
uses system, AppleInternal, and FaceSupport roots, not the app bundle.

The escape also does not solve the already measured denial of
`mach-lookup` for `com.apple.nanotimekit.collectionserver`.

## Physical watchOS result (2026-11-14)

With explicit approval, WatchFaceLab was given the dedicated App Group
`group.dev.develodom.WatchFaceLab`. Xcode successfully built, signed, installed,
and launched it on the physical watch. The group container API returned a URL,
which confirms the prerequisite was active in the running process.

The opt-in probe replaced only the empty `Library/Caches` directory in that
dedicated group with a symlink to
`/private/var/containers/Shared/SystemGroup`. It then issued the same class-7,
part-3 query used by the related iOS research. Both known operation flags were
tested:

```text
candidate=0 flags=0x8000000000 query-result=1 token=0
candidate=1 flags=0x800000000  query-result=1 token=0
result=no-token-all-candidates
cleanup=restored result=8
```

`containermanagerd` returned a query result for both variants but did not include
a sandbox extension token. The probe restored the App Group `Library/Caches`
directory on both runs and made no write outside its own group. The scheme
opt-in was disabled afterward.

This is stronger than a missing-entitlement failure: the App Group exists and
the query is answered, but watchOS declines the token. After two runs with the
same issuance boundary, this exact route should not be repeated.

## Remaining combination possibilities

The combination idea remains valid only with a different first primitive: a
watchOS-specific sandbox extension bug, a confused deputy that already owns
FaceSupport storage, or a verified kernel sandbox escape. The iOS class-7 token
issuance itself does not transfer to the measured watchOS 27.0.1 build.

No `LibraryFaces` install/select action should run until both the filesystem
path and collection-server boundary have a reversible, verified route.
