# Bounded `.watchface` parser research lab

Branch: `research/watchface-parser`

This branch tests how the public watch-face import path handles a small set of
malformed variants derived from a face exported by the owner of the test
device. It is intended for good-faith Apple Security Bounty research on an
owned Watch. It does not generate executable payloads, bypass signing, escape a
sandbox, or automatically fuzz a device.

Apple explicitly includes the latest public and beta watchOS releases in its
[Security Bounty guidelines](https://security.apple.com/bounty/guidelines/).
Its [terms](https://security.apple.com/terms-and-conditions/) prohibit affecting
devices or data without permission. Do not test a shared, borrowed, production,
or another person's Watch.

## Safety model

- The input must be a locally owned `.watchface` export and a ZIP-compatible
  archive smaller than 64 MiB.
- Archive paths, symlinks, encryption, entry count, expanded size, and
  compression ratio are validated before any corpus is generated.
- Mutations are deterministic and bounded: a single bit flip, half truncation,
  entry removal, an unknown metadata key/entry, and two archive-tail cases.
- The physical runner requires `--owned-device`, resolves every case through a
  hash-locked manifest, embeds exactly one case, and launches the importer once.
- A timeout is never retried automatically. Preserve evidence and inspect the
  device before doing anything else.
- Corpora and run evidence live under ignored `Corpus/` and `Runs/`
  directories. A sysdiagnose can contain private account/device metadata;
  review it before sharing it.

## 1. Export and inspect a control face

Configure a normal built-in Apple face without third-party complications and
use the system Share action to export it. Keep the export private because its
configuration may contain personal data. Do not use **Pip-Boy Monitor** for the
first baseline: Apple requires complications in an imported shared face to
have a valid App Store or TestFlight identity, while this branch is a local
development build.

The most reliable export flow is on the paired iPhone:

1. Open the **Watch** app.
2. Open **My Watch** and tap one face under **My Faces**.
3. Tap the Share button in the upper-right corner.
4. Choose **AirDrop** and select the Mac. Alternatively, choose **Save to
   Files**, then move the resulting `.watchface` to the Mac.

Apple does not document a public export API or a `simctl`/`devicectl` export
command. Its public `CLKWatchFaceLibrary` API only imports an existing
`.watchface`. The following helper cannot press Share for you, but it waits for
the AirDropped file in Downloads, validates it, and generates the corpus
immediately:

```sh
bash Experiments/watchface-parser-lab.sh capture
```

Start `capture` first, then perform the four iPhone steps within five minutes.
It prints the resulting `CORPUS` path and the exact baseline command.

For a file that is already on the Mac, inspect it directly:

```sh
git switch research/watchface-parser
git pull --ff-only
bash Experiments/watchface-parser-lab.sh inspect \
  ~/Downloads/Owned-PipBoy.watchface
```

Inspection is offline and prints entry names, classifications, sizes, and
SHA-256 hashes. It does not extract or import the archive.

## 2. Generate and verify the bounded corpus

```sh
bash Experiments/watchface-parser-lab.sh generate \
  ~/Downloads/Owned-PipBoy.watchface
```

The command prints the new corpus directory. Use that exact path below:

```sh
CORPUS='Experiments/WatchFaceParser/Corpus/Owned-PipBoy-YYYYMMDD-HHMMSS'
bash Experiments/watchface-parser-lab.sh verify "$CORPUS"
bash Experiments/watchface-parser-lab.sh list "$CORPUS"
```

`manifest.json` records the source hash, mutation description, target entry,
case hash, size, and whether Python's ZIP parser can still open the result.

## 3. Establish the baseline

Use a non-primary Watch when possible. Keep it unlocked, charged, paired, and
visible in Xcode's Devices and Simulators window. The first device action must
be the byte-identical baseline:

```sh
bash Experiments/watchface-parser-lab.sh run "$CORPUS" 000-baseline \
  --owned-device 2>&1 | tee ~/Desktop/watchface-baseline.txt
```

The runner:

1. verifies the selected case hash;
2. performs a clean build and signs the public complication host with that
   case embedded, avoiding stale incremental resource seals;
3. verifies the embedded hash and app signature;
4. installs the app and launches it exactly once;
5. calls public `CLKWatchFaceLibrary.addWatchFace` from the visible app;
6. downloads a run-ID-matched JSON result from the app container.

Passing `--owned-device` is an explicit confirmation, not a device bypass. Use
`--device COREDEVICE-ID` if automatic Watch selection is ambiguous.

Do not continue unless the baseline returns a complete result and the Watch is
responsive. A successful baseline may add another copy of the exported face to
the face library; remove test copies manually when the run is finished.

## 4. Run one mutation

Choose one case from `list`, preferably beginning with a syntactically valid,
low-impact case such as `104-metadata-unknown-key` when present or
`300-extra-unknown-entry`:

```sh
bash Experiments/watchface-parser-lab.sh run "$CORPUS" \
  300-extra-unknown-entry --owned-device \
  2>&1 | tee ~/Desktop/watchface-one-case.txt
```

Review the JSON and Watch state before selecting another case. Do not create an
unguarded loop around `run`; use the guarded batch mode below.

### Guarded batch mode

After a successful baseline, the runner can execute the remaining bounded
cases unattended. Preview the exact plan without contacting the Watch:

```sh
bash Experiments/watchface-parser-lab.sh batch "$CORPUS" --plan
```

Then run it:

```sh
bash Experiments/watchface-parser-lab.sh batch "$CORPUS" \
  --owned-device 2>&1 | tee ~/Desktop/watchface-batch.txt
```

The batch recognizes completed cases by case ID and SHA-256 and skips them. It
runs at most 12 cases in a fixed low-to-higher-impact order with a five-second
cooldown. Each case still performs a clean signed build and one import. A
timeout, invalid/missing result, build/install failure, or unavailable Watch
stops the batch immediately and is never retried. Completed API rejections are
recorded and the batch may continue because the app and device responded
normally. Per-case logs and `summary.tsv` are stored under the printed ignored
`BATCH_EVIDENCE` directory.

Use `--cases ID,ID` to run a smaller explicit subset, `--cooldown SECONDS` to
increase the pause, or `--rerun-completed` only after manually reviewing the
earlier evidence.

Expected safe outcomes are either a successful import or a completed error
from `CLKWatchFaceLibrary`. Neither result is a vulnerability by itself. An app
timeout can also be an API/UI lifecycle issue; it is not proof that a system
process crashed.

## 5. Preserve evidence after an abnormal result

If the runner prints `PARSER_RESULT=TIMEOUT`, do not immediately repeat the
case. Note the exact time, confirm whether the Watch and paired iPhone remain
responsive, and keep the printed `EVIDENCE` directory. Once the device has
recovered, fetch the last app record without importing again:

```sh
bash Experiments/watchface-parser-lab.sh result --owned-device
```

Collect a sysdiagnose only when the abnormal behavior is worth preserving:

```sh
bash Experiments/watchface-parser-lab.sh diagnose --owned-device \
  --output 'Experiments/WatchFaceParser/Runs/CASE-RUN/sysdiagnose'
```

Do not publish the corpus, crash details, or sysdiagnose before Apple has fixed
an eligible issue. Before reporting, establish at least:

- exact hardware, watchOS build, Xcode version, and source/case SHA-256;
- a reliable minimal reproduction on the latest watchOS;
- which process failed, with a symbolicated crash log when available;
- the security boundary or user data affected, beyond an ordinary rejection or
  denial of service;
- numbered reproduction steps and a nondestructive PoC.

A rejected malformed face, a crash confined to WatchFaceLab, or unsupported
custom-face rendering is not by itself evidence of a bounty-eligible issue.
Apple warns against submitting theoretical or AI-generated reports without
human validation; keep the report factual and based on captured evidence.

## Local validation

The offline generator has unit tests independent of a physical Watch:

```sh
python3 -m unittest discover \
  -s Experiments/WatchFaceParser/Tests -v
bash -n Experiments/watchface-parser-lab.sh
```
