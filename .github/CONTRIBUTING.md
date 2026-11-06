# Contributing to Ghostgram

This page explains where Ghostgram's code goes and which checks a change has to pass. To build the app,
follow [Building](../README.md#building) in the README.

## Where code goes

- Put new code in `Ghostgram/`. A feature is a module in `Ghostgram/Features/<Name>` with a
  `GG<Name>Module.register()` function that `Ghostgram/Features/Sources/GGFeatures.swift` calls at launch.
- A feature module can depend on any module below `TelegramUI`. It can't depend on `TelegramUI` or on another
  feature module.
- Ghostgram reaches Telegram's code through hook points in `Ghostgram/GGHooks/`. A feature registers a handler
  for a point; Telegram's code calls the point.
- Settings are `GGSetting` or `GGAccountSetting` values declared once in the feature and touched from its
  `register()`, so export, search and migrations know them. A setting that is removed or renamed needs a
  migration (`GGMigrations`, `GGRetiredSettings`).

## Change Telegram's own files

Keep edits to files outside `Ghostgram/` as small as you can, so that new Telegram releases apply cleanly
(see [Updating to a new Telegram iOS release](../docs/ios/upstream-sync.md)):

- Mark each edited line or block with a `// GHOST:` comment that says why it is there. In `BUILD` files, use
  `# GHOST:`.
- Call a hook point from the edit instead of writing feature logic in Telegram's file.
- Don't reformat or clean up Telegram's code around an edit.
- Don't commit inside a Git submodule. Put the change into a patch file in `build-system/GGPatches/` and apply
  it from `build-system/GGBuild.sh`.

## Add or change strings

Interface strings are JSON files in `Ghostgram/Strings/<language>/`. English and Russian are required;
Ukrainian and Arabic are filled in when possible. After you edit them, regenerate the Swift accessors and run
the checks:

```sh
python3 Ghostgram/Strings/generate.py
python3 Ghostgram/Strings/check.py
```

In code, use the full accessor path, such as `GGStrings.Core.requiresRestart`. `check.py` finds used keys by
these paths and reports a key as unused when the path is shortened through an alias.

## Check your change

1. Build the app with `build-system/GGBuild.sh`. Ghostgram's modules treat warnings as errors.
2. Run the tests of the modules you changed. The host test targets are listed by
   `rg -l swift_test Ghostgram -g BUILD`, and each `BUILD` file shows the command that runs its tests.
3. For a change to the interface, check it on a simulator, in light and dark themes. A change to layout also
   needs a check on iPhone Duo, folded and unfolded (see [iPhone Duo layout](../docs/iphone-duo-layout.md)).

## Open a pull request

Open the pull request against `main`.
