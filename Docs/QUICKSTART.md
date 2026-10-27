# Pip-Boy face: one-command simulator demo

Requirements: macOS with Xcode and the watchOS 26.5 x86_64 Simulator runtime,
plus an available simulator named `WatchFaceLab26 Research`.

From the repository root, run this as your normal macOS user:

```sh
bash Experiments/quickstart-system-face.sh
```

Never use `sudo`. CoreSimulator device sets are per-user, so root cannot see the
logged-in user's simulator UUID.

The quickstart automatically:

1. finds and boots the research simulator;
2. builds the custom face, bundle, probes, and guarded bootstrap;
3. creates a hybrid runtime overlay without changing Apple's runtime;
4. loads the bundle in ClockFace and `nanotimekitd`;
5. adds the face through the collection service; and
6. switches the live ClockFace UI to the animated Pip-Boy face.

If auto-discovery is ambiguous, pass a UUID:

```sh
bash Experiments/quickstart-system-face.sh SIMULATOR-UUID
```

If another watch app is in front after completion, press Digital Crown until the
watch face appears.

The final output prints an exact rollback command. The standard form is:

```sh
bash Experiments/test-system-discovery-overlay.sh rollback SIMULATOR-UUID
```

This integration is a simulator-only research technique, not a deployment path
for physical Apple Watch hardware.
