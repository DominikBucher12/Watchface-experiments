# Repository cleanup manifest

Prepared on 2026-10-28 before rewriting any history. The listed generated and
external artifacts have now been removed from the `version/simulator27` working
tree. The obsolete LFS-only `.gitattributes` file was removed after the tree no
longer contained LFS pointers. `main` and `version/27` now have the same artifact
policy and branch-appropriate cleanup commits. The approved all-ref history
rewrite and coordinated force-push are the remaining steps.

## Verified backups

The sibling clone is a complete Git repository with connected objects:

```text
/Users/dominikbucher/Hacking/Watchface-experiments - zaloha
main                c0d849e6767f1db7a2888ea28c7364bc8accfa32
version/27          f8541fb10f57bbc37b15786020e1620e702ef974
version/simulator27 5c79777b5e4d60105ea9e6475e48bda4a9d61d70
```

An independent complete bundle contains all local and origin refs:

```text
/Users/dominikbucher/Hacking/Watchface-experiments-pre-cleanup-2026-10-28.bundle
size: 941 MiB
sha256: 0cfbdccd7dabeb51644a00c53a319031e2e842a791f58394594829733f3bbdd5
```

Verify or restore it with:

```sh
git bundle verify /Users/dominikbucher/Hacking/Watchface-experiments-pre-cleanup-2026-10-28.bundle
git clone /Users/dominikbucher/Hacking/Watchface-experiments-pre-cleanup-2026-10-28.bundle Watchface-experiments-restored
```

## Measured baseline

- checkout including `.git`: 971 MiB;
- `.git`: 959 MiB;
- packed ordinary Git history: 929.74 MiB;
- tracked files at `version/simulator27`: 2,514;
- LFS pointers at that head: 2,314;
- target size declared by those pointers: 3,239.56 MiB;
- `Analysis/Extracted`: 2,306 pointers declaring 2,841.55 MiB.

## Applied working-tree removal manifest

These generated products, external runtime contents, derived dumps, and personal
editor state were removed after explicit owner confirmation:

```text
Experiments/ClockFaceLab/Analysis/Extracted/
Experiments/ClockFaceLab/Analysis/NanoTimeKit-0x30799c.asm.txt
Experiments/ClockFaceLab/ClockFaceLab.app/
Experiments/Build/
Experiments/ArgonXPCLab/ArgonXPCLab
WatchFaceLab/CustomFaceLoader.swift.before-argon-xpc
Experiments/build-embedded-framework.sh.before-argon-xpc
.DS_Store (at every depth)
xcuserdata/ (at every depth)
*.xcuserstate
*.xcbkptlist
another.txt
dalsi.txt
jachciumrit.txt
mrdka.txt
mrdka2.txt
mrdka3.txt
picovina.txt
```

The one-off root search helper `sracka.sh` was removed in the same approved
cleanup.

## Files to retain

- Objective-C, Swift, shell, and Python sources;
- documentation and research conclusions;
- Xcode project structure, excluding user state;
- source bundle manifests and plists;
- `WatchFaceLab/Resources/pip-boy-reference.gif`;
- build and bootstrap scripts.

## History rewrite boundary

Deleting files in a new commit does not shrink existing clones. After the
working trees are cleaned and tested, all branches and tags must be rewritten
in a fresh mirror clone with `git-filter-repo`. The rewritten refs must be
force-pushed in a coordinated maintenance window. Existing clones must be
retired and freshly cloned so that an old ref cannot restore the removed
objects.

GitHub LFS objects remain in remote LFS storage after their pointers are removed.
Purging that quota requires recreating the GitHub repository or arranging a
purge with GitHub Support.
