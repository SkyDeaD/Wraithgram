# Updating to a new Telegram iOS release

Wraithgram is Telegram iOS plus Wraithgram's own changes. This page shows how to bring a new Telegram iOS
release into Wraithgram and check the result.

## How updates work

- Telegram iOS releases are commits on `master` of
  [TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS). A release is the commit
  that changes `app` in `versions.json`, usually titled `Bump version`. The repository has had no release tags
  since 2023.
- Wraithgram's Git history starts from a single commit and does not contain Telegram's commits, so releases are
  not merged. The Telegram commit that Wraithgram is based on is recorded in `build-system/upstream-base`.
- `build-system/WGUpstreamSync.sh` applies the difference between that commit and the new release as a patch,
  with a three-way fallback. Where Telegram and Wraithgram changed the same lines, the file is left with
  conflict markers. Changes to Telegram files that Wraithgram deletes (such as `CLAUDE.md` and `AGENTS.md`) are
  skipped.
- Wraithgram's code lives in `Wraithgram/`. Edits to Telegram's own files are small and marked `// WRAITH:`.
  These edits are where conflicts happen.
- Wraithgram's changes inside Git submodules are kept as patch files in `build-system/WGPatches/`, not as
  submodule commits. `build-system/WGBuild.sh` applies them.

## Before you begin

You need:

- A clone of Wraithgram with its submodules (`git clone --recursive`).
- A working build as described in the README.
- No uncommitted changes. The submodules that `WGBuild.sh` patches may stay modified.
- The Xcode version that the new release names in `versions.json`. When it changes, install that Xcode and
  select it with `xcode-select` before you build.

## Apply a release

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

5. Optional: preview the files that both Telegram and Wraithgram changed. Conflicts can only happen in these
   files.

   ```sh
   BASE=$(cat build-system/upstream-base)
   comm -12 <(git diff --name-only $BASE COMMIT | sort) <(git diff --name-only $BASE HEAD | sort)
   ```

6. Apply the release.

   ```sh
   build-system/WGUpstreamSync.sh COMMIT
   ```

   The script prints the base, the release and the skipped files, then one of these results:

   - `Applied cleanly.` — continue with step 8.
   - `Applied with conflicts.` and a list of files — continue with step 7.
   - `ERROR: the patch did not apply` — nothing was changed. The usual cause is a change to a file that
     Wraithgram also changed in a way the three-way fallback cannot handle, such as a submodule that Wraithgram
     points to a different commit. Fix that file by hand and run the script again.

7. Resolve each conflict, then stage the file with `git add FILE`. List the conflicting files with
   `git diff --name-only --diff-filter=U`.

   In a conflict, keep Telegram's new code and re-apply the `// WRAITH:` lines to it. For example, in 13.1.2
   Telegram added a field next to Wraithgram's equalizer field in `ChunkMediaPlayerV2.swift`, and the resolution
   kept both fields. If Telegram rewrote the code a `// WRAITH:` block attached to, find the place where the new
   code does the same thing and move the block there.

   `versions.json` conflicts when Telegram changes its Xcode version, because Wraithgram sets its own `xcode`.
   Take Telegram's `app` and the other fields, and keep the newer of the two `xcode` values.

8. Commit the update. The script has already staged the changes and the new `build-system/upstream-base`.

   ```sh
   git commit -m "Update to Telegram-iOS VERSION (COMMIT)"
   ```

9. Check out the submodule commits that the release uses.

   ```sh
   git submodule update --init --recursive
   ```

## Check the result

1. Confirm that the only differences from Telegram are Wraithgram's. This lists the changed files outside
   `Wraithgram/`. Each one must be a source file with `// WRAITH:` edits or a file Wraithgram adds or replaces,
   such as the build scripts in `build-system/`, the app's icons and name, the documentation, `.gitignore` and
   `.gitattributes`.

   ```sh
   git diff --name-only COMMIT HEAD -- . ':!Wraithgram'
   ```

2. Build the app. `WGBuild.sh` also applies the submodule patches.

   ```sh
   build-system/WGBuild.sh --continueOnError
   ```

   If it stops with `neither applies nor is already applied`, the submodule changed under a patch. In that
   submodule, re-apply the change by hand, then write the patch again with
   `git -C SUBMODULE diff > build-system/WGPatches/PATCH.patch`. `SUBMODULE` is the submodule path and `PATCH`
   the name of the patch file from the error.

3. Run the string checks and the Wraithgram tests.

   ```sh
   python3 Wraithgram/Strings/check.py
   python3 Wraithgram/Strings/tests/test_tools.py
   ```

   The host test targets are listed by `rg -l swift_test Wraithgram -g BUILD`. Run each with
   `./build-input/bazel-BAZEL_VERSION-darwin-arm64 test TARGET`, where `BAZEL_VERSION` is the version in
   `versions.json` and `TARGET` is the target label from that `BUILD` file.

4. Install the build on a simulator and open the screens that the conflicting files draw.

5. Update the Telegram version named in `README.md` and `README.ru.md`.
