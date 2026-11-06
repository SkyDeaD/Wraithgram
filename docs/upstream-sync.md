# Updating to a new Telegram iOS release

Ghostgram is Telegram iOS plus Ghostgram's own changes, and its Git history continues Telegram's. This page
shows how to merge a new Telegram iOS release into Ghostgram and check the result.

## How the history is organized

- Telegram iOS releases are commits on `master` of
  [TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS). A release is the commit
  that changes `app` in `versions.json`, usually titled `Bump version`. The repository has had no release tags
  since 2023.
- Ghostgram's commits sit on top of Telegram's commits. Each Telegram release enters with a merge commit named
  `Merge Telegram-iOS <version> (<commit>)`.
- Ghostgram's code lives in `Ghostgram/`. Edits to Telegram's own files are small and marked `// GHOST:`.
  These edits are where merge conflicts happen.
- Ghostgram's changes inside Git submodules are kept as patch files in `build-system/GGPatches/`, not as
  submodule commits. `build-system/GGBuild.sh` applies them.

## Before you begin

You need:

- A full clone of Ghostgram with its submodules (`git clone --recursive`), not a shallow one.
- A working build as described in the README.
- The Xcode version that the new release names in `versions.json`. When it changes, install that Xcode and
  select it with `xcode-select` before you build.

## Merge a release

1. Add Telegram iOS as a remote. Skip this step if the remote exists.

   ```sh
   git remote add upstream https://github.com/TelegramMessenger/Telegram-iOS.git
   ```

2. Fetch Telegram's `master`.

   ```sh
   git fetch upstream master
   ```

3. Find the release commit. This lists the commits that changed `versions.json`, newest first:

   ```sh
   git log --format='%h %ad %s' --date=short upstream/master -- versions.json
   ```

   Check the version of a commit with `git show COMMIT:versions.json`. `COMMIT` is the hash from the list.

4. Create a branch for the update from `main`.

   ```sh
   git switch -c telegram-VERSION main
   ```

   `VERSION` is the Telegram version, for example `13.1.3`.

5. Optional: preview the files that both Telegram and Ghostgram changed. Conflicts can only happen in these
   files. `BASE` is the Telegram commit of the previous merge, `COMMIT` the new release.

   ```sh
   comm -12 <(git diff --name-only BASE COMMIT | sort) <(git diff --name-only BASE main | sort)
   ```

6. Merge the release.

   ```sh
   git merge --no-ff -m "Merge Telegram-iOS VERSION (COMMIT)" COMMIT
   ```

7. Resolve each conflict. List the conflicting files with `git diff --name-only --diff-filter=U`.

   In a conflict, keep Telegram's new code and re-apply the `// GHOST:` lines to it. For example, in 13.1.2
   Telegram added a field next to Ghostgram's equalizer field in `ChunkMediaPlayerV2.swift`, and the resolution
   kept both fields. If Telegram rewrote the code a `// GHOST:` block attached to, find the place where the new
   code does the same thing and move the block there.

   `versions.json` conflicts when Telegram changes its Xcode version, because Ghostgram sets its own `xcode`.
   Take Telegram's `app` and the other fields, and keep the newer of the two `xcode` values.

   Ghostgram deletes Telegram's `CLAUDE.md` and `AGENTS.md`. When Telegram changes one of them, it conflicts as
   deleted by us; resolve it with `git rm CLAUDE.md AGENTS.md`.

8. Finish the merge.

   ```sh
   git add -A
   git commit --no-edit
   ```

9. Check out the submodule commits that the release uses.

   ```sh
   git submodule update --init --recursive
   ```

## Check the result

1. Confirm that the only differences from Telegram are Ghostgram's. This lists the changed files outside
   `Ghostgram/`. Each one must be a source file with `// GHOST:` edits or a file Ghostgram adds or replaces,
   such as the build scripts in `build-system/`, the app's icons and name, `README.md`, `.gitignore` and
   `.gitattributes`.

   ```sh
   git diff --name-only COMMIT HEAD -- . ':!Ghostgram'
   ```

2. Build the app. `GGBuild.sh` also applies the submodule patches.

   ```sh
   build-system/GGBuild.sh --continueOnError
   ```

   If it stops with `neither applies nor is already applied`, the submodule changed under a patch. In that
   submodule, re-apply the change by hand, then write the patch again with
   `git -C SUBMODULE diff > build-system/GGPatches/PATCH.patch`. `SUBMODULE` is the submodule path and `PATCH`
   the name of the patch file from the error.

3. Run the string checks and the Ghostgram tests.

   ```sh
   python3 Ghostgram/Strings/check.py
   python3 Ghostgram/Strings/tests/test_tools.py
   ```

   The host test targets are listed by `rg -l swift_test Ghostgram -g BUILD`. Run each with
   `./build-input/bazel-BAZEL_VERSION-darwin-arm64 test TARGET`, where `BAZEL_VERSION` is the version in
   `versions.json` and `TARGET` is the target label from that `BUILD` file.

4. Install the build on a simulator and open the screens that the conflicting files draw.

5. Update the Telegram version named in `README.md` and `README.ru.md`.
