# cesosag.settings

Schema-driven **Settings** GUI for [Omarchy](https://omarchy.org): edit Setup surfaces that used to open raw config files (`shell.json`, Hypr Lua, `hyprsunset.conf`, `xdph.conf`, …) from a panel with live auto-apply.

## Install

```bash
omarchy plugin add https://github.com/cesosag/cesosag.settings.git --enable
```

Then either open the panel once (it self-wires the Setup menu) or run:

```bash
~/.config/omarchy/plugins/cesosag.settings/bin/install
```

### Uninstall

```bash
~/.config/omarchy/plugins/cesosag.settings/bin/uninstall
omarchy plugin remove cesosag.settings --yes
```

`uninstall` removes only this plugin’s Setup menu keys (other overrides in `~/.config/omarchy/extensions/omarchy-menu.jsonc` are kept) and disables the plugin.

## What you get

| Sidebar | Config |
|---------|--------|
| Shell | `~/.config/omarchy/shell.json` (idle, dock, bar) |
| Monitors | `monitors.lua` |
| Input | `input.lua` |
| Keybindings | full Omarchy catalog + overrides → `bindings.lua` |
| Hyprland | binding packs + look & feel → `hyprland.lua` / `looknfeel.lua` |
| Night light | `hyprsunset.conf` (+ optional autostart) |
| Screen share | `xdph.conf` |

Changes **auto-apply** after a short debounce (no Apply button). Managed Lua/`.conf` sections keep a `# >>> cesosag.settings:custom` / `-- >>> …` block for hand-written extras. Backups are written next to each file on save.

Open via **Setup** menu, or:

```bash
omarchy-shell shell summon cesosag.settings 'shell'
```

## Enable / disable (without removing)

```bash
python3 ~/.config/omarchy/plugins/cesosag.settings/bin/settings ensure   # idempotent
python3 ~/.config/omarchy/plugins/cesosag.settings/bin/settings disable
python3 ~/.config/omarchy/plugins/cesosag.settings/bin/settings status
```

## For contributors

```bash
omarchy plugin validate .
python3 bin/selftest
```

Architecture notes: declarative `schemas/`, generic `SchemaForm` / `SchemaPage`, backends in `bin/settings`, `bin/lua-settings`, `bin/conf_settings.py`. Custom views: `MonitorsPage`, `KeybindingsPage`.

## License

MIT — see [LICENSE](LICENSE).
