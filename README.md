# mac-keyboard-swap

Use Windows-layout keyboards on a Mac with the same muscle memory as an Apple keyboard.

On a Windows keyboard, macOS treats **Win as Command** and **Alt as Option**, so Command
ends up next to Ctrl instead of next to the space bar. `kbswap` swaps them back, **per
keyboard**, so your Apple keyboard is left alone.

It uses the macOS built-in per-keyboard modifier setting (the one behind
*System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys*), but from the command
line, so you can script it and reproduce it on a new Mac.

- No kernel or DriverKit extension, no background daemon, no Input Monitoring permission.
- Survives reboots and replugging, because macOS itself re-applies it whenever the keyboard connects.
- Swaps both sides: Left/Right Alt ↔ Command, Left/Right Win ↔ Option.

## Install

```sh
git clone https://github.com/kailin5/mac-keyboard-swap.git
cd mac-keyboard-swap
make install            # symlinks bin/kbswap into /usr/local/bin (PREFIX=... to change)
```

## Use

```sh
kbswap list                    # connected keyboards with their VID:PID and current mapping
kbswap enable 1133:50475       # swap on that keyboard (hex works too: 0x46d:0xc52b)
kbswap doctor                  # verify saved + live state; non-zero exit on problems
kbswap disable 1133:50475      # undo
kbswap uninstall               # undo everything kbswap did
```

Every command accepts `--dry-run` first (`kbswap --dry-run enable …`) to print what it would do.

If a keyboard already has a mapping you set in System Settings, `enable` refuses to replace
it unless you pass `--force`. Then the old mapping is backed up and `disable` puts it back.

For a new Mac, add the `kbswap enable …` lines to your dotfiles bootstrap.

## Check it works

Run `kbswap doctor`, then check by hand. On the Windows keyboard:

1. The key **next to the space bar** + Tab opens the app switcher (it is Command now).
2. The key **next to Ctrl** + `e` types the `´` dead key (it is Option now).
3. Unplug and replug the keyboard; repeat 1.
4. Reboot; repeat 1.
5. On an Apple keyboard, the same positions still behave the same as before.

## Limits: read before enabling

- **Receivers and dongles.** macOS sees the receiver (for example a Logitech Unifying
  receiver), not the keyboard behind it. Every keyboard paired to that receiver gets the swap.
- **Keyboards with a Mac/Windows switch** (Keychron, Logitech K380/MX in Mac mode, …) already
  swap in hardware. Use the switch instead; enabling kbswap too would swap twice.
- **KVM switches** that emulate a keyboard report their own ID. If an Apple keyboard goes
  through the same KVM, the two can't be told apart.
- **The preference format is undocumented.** It has been stable for years, but Apple could
  change it. Run `kbswap doctor` after macOS updates. Tested on macOS 26 (Tahoe) on Apple Silicon.
- Only modifier keys. Home/End, Print Screen and similar keys are out of scope; use
  [Karabiner-Elements](https://karabiner-elements.pqrs.org/) if you need more.

## How it works

For each enabled keyboard, kbswap writes
`com.apple.keyboard.modifiermapping.<VendorID>-<ProductID>-0` in the current-host global
preferences, the same entry System Settings writes. macOS applies it every time that
keyboard connects. kbswap also runs `hidutil property --matching … --set` so the change
takes effect immediately, without a replug. State (which keyboards it manages, plus backups)
lives in `~/.config/kbswap/`.

## Development

```sh
make test    # uses a throwaway preferences domain and a fake hidutil; never touches real mappings
make lint    # shellcheck
```

The tests can't press real keys, so a release also needs the manual checklist above on a real Mac.

## License

MIT
