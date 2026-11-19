# Changelog

## v1.6.0

### Added
- **Partial pause in battlegrounds/arenas.** Only party Blessing tracking turns off there now — it genuinely needs aura reads on other people, which stay hidden the whole time. Your own Seal, Righteous Fury and Aura keep tracking and alerting the same combat-safe way they already do mid-fight. Dying in a BG now correctly clears them too (previously that only worked outside BGs).
- **Righteous Fury gets the same combat-safe re-cast tracking as the Seal**, using its real 30-minute duration on this client — alerts if you haven't recast it in time.
- **Redesigned status window header.** The Seal is now a larger centered icon with a cooldown-style sweep and countdown (visualizing its 30s re-cast reminder); Righteous Fury and Aura sit below as small badges. The window also shrinks to fit when party tracking is off (e.g. in a BG) instead of showing empty rows.

### Changed
- Status borders are a thinner, softer green/red instead of the old square frame (which rendered as broken corner brackets on this client), and the window's own border is tinted warm instead of flat grey.

## v1.5.0

### Added
- **Combat-safe Seal / Righteous Fury / Aura tracking.** Casting (or re-casting) one now marks it up the moment the cast succeeds, instead of waiting for a buff scan that combat hides for the rest of the fight.
- **Seal re-cast reminder.** Every Seal cast starts a 30-second countdown; recast before it runs out and it just restarts, let it run out and you get the usual "Seal expired" alert — a backstop for exactly the situations a real scan can't reach you.
- **Blessings cast from your own action bar (not just a click-cast row) now update party tracking too**, based on whoever you're currently targeting.

### Fixed
- **False "Seal expired" when switching to a different Seal.** Swapping Seals removes the old one and adds the new one in the same update; the combat-safe tracking above checked the removal before it had registered the new Seal, misreading a swap as the Seal falling off.

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
