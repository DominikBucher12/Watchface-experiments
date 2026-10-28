# Routes after the physical sandbox boundary

The physical watchOS 27 result is conclusive for a normally signed third-party
Watch app: WatchFaceLab cannot look up
`com.apple.nanotimekit.collectionserver`. Its relevant private entitlement
values are absent. This is a client sandbox decision made before the collection
server can accept or reject a face descriptor.

## Stock-device route that remains implementable

`CLKWatchFaceLibrary` can import a `.watchface` file and reports explicit errors
for an invalid file, denied permission, or an unavailable face. This API imports
a configuration for a face already available to the system. It does not copy an
app-defined executable `NTKFace` subclass into `ClockFace` or extend the system
bundle loader.

The practical stock-device design is therefore:

1. implement the Pip-Boy display as a WidgetKit complication;
2. choose an existing Apple face whose complication layout fits the design;
3. ship or generate a `.watchface` configuration that selects that complication;
4. import it through `CLKWatchFaceLibrary` or the normal share sheet.

This produces a durable entry in the system face library, survives leaving the
app, and uses Apple's supported process boundary. The visual area, update rate,
animations, and interaction remain constrained by the chosen complication
family and WidgetKit timelines; it is not the full custom renderer already
demonstrated inside WatchFaceLab.

## Full custom native renderer

The current executable face needs all of the following in a separate system
process: trusted bundle distribution, code-signature acceptance, discovery by
`NTKFaceBundleManager`, collection persistence, and reconstruction by
`nanotimekitd` and `ClockFace`. The observed production device exposes those
paths only behind platform/private entitlements and system-controlled FaceSupport
storage. A full native result therefore requires either an Apple-authorized
internal/system-host environment or a deliberately modified research device OS.
Changing an Info.plist, bundle identifier, provisioning profile, or `.watchface`
descriptor cannot manufacture those privileges.

The iPhone/Watch companion synchronization pipeline can move supported face
configurations, but it does not solve executable bundle discovery or system
library validation. It is useful for the complication-based route, not as a
bypass for the custom `MYCustomFace` image.
