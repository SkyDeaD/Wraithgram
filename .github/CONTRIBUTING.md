# Contributing to Wraithgram

This page explains where Wraithgram's code goes and which checks a change has to pass. To build the app,
follow [Building](../README.md#building) in the README.

## Where code goes

- Put new code in `Wraithgram/`. A feature is a module in `Wraithgram/Features/<Name>` with a
  `WG<Name>Module.register()` function that `Wraithgram/Features/Sources/WGFeatures.swift` calls at launch.
- A feature module can depend on any module below `TelegramUI`. It can't depend on `TelegramUI` or on another
  feature module.
- Wraithgram reaches Telegram's code through hook points in `Wraithgram/WGHooks/`. A feature registers a handler
  for a point; Telegram's code calls the point.
- Settings are `WGSetting` or `WGAccountSetting` values declared once in the feature and touched from its
  `register()`, so export, search and migrations know them. A setting that is removed or renamed needs a
  migration (`WGMigrations`, `WGRetiredSettings`).

## Change Telegram's own files

Keep edits to files outside `Wraithgram/` as small as you can, so that new Telegram releases apply cleanly
(see [Updating to a new Telegram iOS release](../docs/ios/upstream-sync.md)):

- Mark each edited line or block with a `// WRAITH:` comment that says why it is there. In `BUILD` files, use
  `# WRAITH:`.
- Call a hook point from the edit instead of writing feature logic in Telegram's file.
- Don't reformat or clean up Telegram's code around an edit.
- Don't commit inside a Git submodule. Put the change into a patch file in `build-system/WGPatches/` and apply
  it from `build-system/WGBuild.sh`.

## Add or change strings

Interface strings are JSON files in `Wraithgram/Strings/<language>/`. English and Russian are required;
Ukrainian and Arabic are filled in when possible. After you edit them, regenerate the Swift accessors and run
the checks:

```sh
python3 Wraithgram/Strings/generate.py
python3 Wraithgram/Strings/check.py
```

In code, use the full accessor path, such as `WGStrings.Core.requiresRestart`. `check.py` finds used keys by
these paths and reports a key as unused when the path is shortened through an alias.

## Check your change

1. Build the app with `build-system/WGBuild.sh`. Wraithgram's modules treat warnings as errors.
2. Run the tests of the modules you changed. The host test targets are listed by
   `rg -l swift_test Wraithgram -g BUILD`, and each `BUILD` file shows the command that runs its tests.
3. For a change to the interface, check it on a simulator, in light and dark themes. A change to layout also
   needs a check on iPhone Duo, folded and unfolded (see [iPhone Duo layout](../docs/iphone-duo-layout.md)).

## Open a pull request

Open the pull request against `main`.
