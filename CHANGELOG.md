# Changelog

## v1.4.1

### Fixed
- **False "Aura not active" / "Blessing expired" after a hearthstone, portal or any loading screen.** For a few seconds after loading, the client may report no auras, or forget who cast them. Missing buffs are now ignored for 5 seconds after a loading screen, and your own buffs are recognised by the client's "cast by you" flag, not only by caster unit.

### Added
- **One alert for the whole party.** When several Blessings run out together, you get one banner and one sound, "Blessing expired: A, B, C", instead of one per person.
- **Pauses in battlegrounds and arenas.** Buff data is hidden there the whole time, so the addon used to sit stuck in "(combat)". Inside BGs and arenas it now stops scanning and alerting and hides the status window, then resumes when you leave. You can turn this off in settings or with `/sealalert pvp off`.
- **Addon menu button** (by the minimap): left-click opens settings, right-click shows/hides the status window.

## v1.4.0

### Fixed
- **No more alert spam when you or a party member dies.** Death wipes every buff; that's no longer reported as "Seal expired" / "Blessing expired: X".
- **No more false "Blessing expired" when a party member zones out or goes offline.** The client returns no auras for members out of sight, which used to read as a dropped Blessing. Those members are now skipped and keep their last known state.
- **Status window in combat.** The window is protected in combat (it holds the click-to-cast rows), so resizing it mid-fight was blocked. That's what left the "(combat)" row sticking out past the border. The window now keeps its layout during combat and catches up after; the "(combat)" note hangs just below it.
- **Hiding, resizing or rescaling the window during combat** now happens right after the fight instead of failing with "Interface action failed because of an AddOn".
- **Your click-cast bindings now apply right after login.** Before, rows used Kings/Might/Wisdom until you changed a binding again.
- **The Aura badge only counts your own aura.** Another paladin's Devotion Aura, or a hunter's Trueshot Aura, no longer hides that yours is off.
- **Blessing of Protection, Freedom and Sacrifice no longer fire "Blessing expired"** a few seconds after you cast them on someone.
- `/sealalert reset` now applies right away (popups, window, bindings, settings panel) instead of after a `/reload`.
- Sound channel commands reject typos instead of silently saving a channel that plays nothing.
- Future updates no longer wipe saved settings and window position when the settings format changes.

### Added
- **Works on every client language.** Seals, Auras, Righteous Fury and Blessings are recognised by spell, not only by English/Russian name. Click-to-cast uses your client's spell names, so it now works on non-English clients too.
- **Separate early warning for party Blessings** (default 10s, `/sealalert groupwarn <sec>`). The old 3s warning was too late to rebuff a 5-minute Blessing.
- Party rows show **"(dead)"**.
- Sliders in the settings panel show their current value.
- Group popup duration is now in the settings panel.
- Clearing an alert's text makes that alert sound-only.
- Non-paladin characters no longer get the status window.
- Addon list icon (`IconTexture`).
