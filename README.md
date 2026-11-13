# ZMK config for beekeeb Toucan Keyboard

[The beekeeb Toucan Keyboard](https://beekeeb.com/toucan-keyboard/) is a wireless split 42-key column‑stagger keyboard that a display and a trackpad, with an aggressive stagger on the pinky columns.

# Building locally

Requires Docker ([OrbStack](https://orbstack.dev) or Docker Desktop): `brew install --cask orbstack`.

```sh
./build.sh            # build + flash left and right
./build.sh left       # just the left (central) half — enough for keymap changes
./build.sh all        # left, right and settings_reset
./build.sh --no-flash # build only
./build.sh --update   # re-fetch ZMK/modules
```

The first run downloads ZMK and Zephyr into a Docker volume, which takes a few minutes. Later builds are incremental. Firmware ends up in `firmware/*.uf2`.

After building, the script flashes each half in turn. When it asks, plug in that half and double-tap its reset button. Once `XIAO-BOOT` mounts, the script copies the firmware and waits for the drive to disappear. `settings_reset` is never flashed automatically.

# License

The code in this repo is available under the MIT license.

The included shield nice_view_gem is modified from https://github.com/M165437/nice-view-gem licensed under the MIT License.

ZMK code snippets are taken from the ZMK documentation under the MIT license.

The embedded font QuinqueFive is designed by GGBotNet, licensed under under the SIL Open Font License, Version 1.1.
