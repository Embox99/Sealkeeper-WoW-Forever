# Sealkeeper: Forever

A lightweight Paladin buff-tracking addon for **WoW: Forever**. It tells you the moment your Seal, Righteous Fury, or Aura falls off, and keeps an eye on whether your party actually has your Blessing — so you're not squinting at buff icons mid-pull.

## Features

- **Seal / Righteous Fury / Aura alerts** — a popup banner and/or sound the instant one of these drops, with an optional early warning a few seconds before it expires.
- **Party Blessing tracking** — watches whether *your* Blessing (not just any paladin's) is up on each party member, with its own separate alert style so it's never confused with your own buffs.
- **Status window** — a small, movable panel that shows Seal / Righteous Fury / Aura at a glance, plus one row per party member colored by whether they have your Blessing. Right-click it to jump straight to the settings.
- **Fully configurable** — pick your own sounds (built-in presets or a custom file), colors, text size, and messages for every alert, all from an in-game settings panel (no need to memorize slash commands, though they're there too).
- **Class-colored names, per-paladin icons** — the status window shows each member's class color and the actual Blessing icon (yours on the left, someone else's on the right, if present).

## Installation

1. Download the latest release and unzip it.
2. Copy the `PaladinSealAlert` folder into your `World of Warcraft\_classic_beta_\Interface\AddOns\` directory.
3. Restart the game or reload your UI (`/reload`).

## Getting started

Type `/sealalert options` in-game to open the full settings panel, or `/sealalert` for a list of every slash command. A quick sample:

```
/sealalert sound on|off
/sealalert group on|off
/sealalert scale 1.2
/sealalert options
```

## Known limitations (WoW: Forever beta)

This addon was built and tested during the first weeks of the WoW: Forever beta, which has a few client-side quirks worth knowing about:

- **Custom sound files** (`PlaySoundFile`) are currently silent on this client — a client bug, not an addon bug. Stick to the built-in sound presets until Blizzard fixes it.
- **Buff reads are blocked entirely while you're in combat.** This is a deliberate client restriction (aura data is hidden from addons during combat), so the status window shows the last known state instead of live data until combat ends.
- Clicking things in the status window doesn't trigger targeting or casting — the client's secure-action system isn't functional yet for addon-created buttons. This should resolve itself once Blizzard patches it; no addon changes will be needed.

None of these affect the addon's core alerting — they only limit what's possible during combat lockdown and with custom audio.

## License

MIT — see [LICENSE](LICENSE).
