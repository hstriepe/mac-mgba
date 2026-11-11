# GB App Builder



**Note:** I wrote this using my Claude/AI scaffold in a couple of hours because I wanted this app. 
**--**  If you object to AI, just skip past.

Turns a **Game Boy, Game Boy Color or Game Boy Advance** ROM into its own **Mac app**. You open a `.gb`, `.gbc`, `.gba` or `.zip` file and get a self-contained, double-clickable app with:

- the [mGBA](https://mgba.io) emulator core
- the game and the right BIOS
- box art as its icon

Each app keeps its own save files and settings. It has no ROM browser: the app is the game.

The game apps are native macOS apps written in Swift, with no Qt. They use mGBA's emulator core, built from the unmodified upstream source (a git submodule), so new mGBA versions come in by moving the submodule and rebuilding.

**No ROMs or BIOS files come with this project.** Use dumps of your own cartridges and console; put the BIOS files in `bios/` (git-ignored).

## Status

| Part | State (2026-11-10) |
|---|---|
| Builder | Opens ROMs and ZIPs, identifies them by CRC32 against the No-Intro DATs, fetches box art, builds and signs apps (window or command line) |
| Player | GB, GBC and GBA run with the real BIOS, sound, keyboard and game controllers. Battery saves, save states (slots and files), rewind, fast-forward, cheats, screenshots, solar sensor, rumble and tilt on controllers |
| Tested | Advance Wars (GBA) reaches its title screen. Aliens: Thanatos Encounter (GBC) reaches its Fox Interactive intro, and Balloon Kid (GB) its Nintendo boot logo. No gameplay tested yet |
| Not ported from mGBA's own app | Video shaders, the Game Boy Printer and Camera, link cable and multiplayer, video and GIF recording |

## Requirements

- A Mac with Apple silicon running macOS 14 or later
- To build: Xcode, and Homebrew's `cmake`, `ninja` and `xcodegen`. Running `scripts/setup-env.sh` installs them.
- Optional: your BIOS dumps in `bios/` (`gba_bios.bin`, `gb_bios.bin`, `gbc_bios.bin`, `sgb_bios.bin`). Without them, GBA games use mGBA's built-in BIOS replacement and Game Boy games start without the boot logo.

## Setup and build

```bash
git clone --recurse-submodules https://github.com/hstriepe/mac-mgba.git
cd mac-mgba
scripts/setup-env.sh        # tools, mGBA submodule, mGBA core library, No-Intro DATs, then a check
scripts/build-app.sh        # → build/GB App Builder.app
scripts/archive-app.sh      # or: an archive in Xcode's Organizer, signed with your Apple Development certificate
```

To work in Xcode, run `xcodegen generate` and open `GBAppBuilder.xcodeproj`.

## Making a game app

You can use the builder's window or the command line.

**In the window:** open `build/GB App Builder.app`, then drop a ROM or ZIP on it (or use **Open ROM…**). Check the name, icon and defaults, then click **Build App**. The app is written to the output folder set in Settings, `~/Applications/mGBA Games` by default.

**On the command line:**

```bash
scripts/build-game.sh "/Volumes/Shared/RETRO_GAMES/ROMs/gba/Advance Wars (USA) (Rev 1).zip"
# → apps/Advance Wars.app
# options: --name, --icon, --no-boxart, --manual <pdf>, --no-manual, --sign, --bios, --set key=value (any mGBA default)
```

When building, the builder:

1. **Identifies the ROM:** it reads the ROM header and looks the CRC32 up in the No-Intro DATs (from libretro-database). That gives the canonical name, for example "Advance Wars (USA) (Rev 1)", and the app is named "Advance Wars".
2. **Finds the manual:** it looks for the game's original manual in archive.org's Nintendo manual collections, first by No-Intro name and then by title. You can also choose or drop your own PDF.
3. **Makes the icon:** it downloads the libretro box art for that name, falling back to the title screen and then to mGBA's system icon. You can also choose or drop your own image.
4. **Adds the BIOS:** `gba_bios.bin` for GBA games. GB and GBC games get all three Game Boy BIOS files, so any Game Boy model can be chosen later.
5. **Assembles and signs:** it copies the player, adds the game, BIOS, manual, icon and your defaults, renames the app and signs it. By default it uses your Developer ID with the hardened runtime, so the apps can be notarized.

The builder's **Settings** cover the output folder, the ROM library folder (default `/Volumes/Shared/RETRO_GAMES/ROMs`), the BIOS folder, the signing identity, the bundle ID prefix, a default save folder, and whether to download box art and manuals.

## Playing

| | Keyboard | Game controller |
|---|---|---|
| A / B | X / Z | Right / bottom face button |
| L / R (GBA) | A / S | Shoulders |
| Start / Select | Return / Delete | Menu / Options |
| D-pad | Arrow keys | D-pad or left stick |
| Fast-forward (hold) | Tab | Right trigger |
| Rewind (hold) | ` | Left trigger |

You can change the keyboard keys in **Settings › Controls**.

### Menus

These are mGBA's menus, keeping only what applies to a single game:

- **File:** import or export the battery save; load a state (F1–F9) or save one (⇧F1–F9); load or save a state file; take a screenshot (F12)
- **Emulation:** pause, next frame, reset, fast-forward, cheats, and the solar sensor for carts that have one
- **View:** frame size 1×–6× (⌘1–⌘6), actual size (⌃⌘A), full screen (⌃⌘F), borderless window (⌘B), lock aspect ratio (⌘A), integer scaling, interframe blending, bilinear filtering, Super Game Boy borders (Game Boy only), mute

### Help and the game's manual

Every game app has **Help › <Game> Help** (⌘?). It covers the keys and controllers, the window, every menu and setting, saves and states, and where files go. It's fitted to the game: it shows your current keys and leaves out what doesn't apply, such as Game Boy settings in a GBA game.

When the builder found a manual (or you gave it one), **Help › Game Manual** (⌥⌘?) opens the original instruction booklet in its own window, at the last page you read. The manuals come from archive.org's Nintendo collections: about 300 Game Boy, 77 Game Boy Color and 92 Game Boy Advance titles. A scan may be from another region than your ROM; Advance Wars' is the European booklet. Downloaded manuals are kept in `~/Library/Caches/com.windholm.gb-appbuilder/Manuals`.

### The game window

The game window is a media window, like QuickTime Player's or CapturePlay's:

- **Title bar:** the picture fills the whole window. The title and window buttons appear when the mouse is at the top of the window and hide again 2 seconds later. You can drag the picture to move the window.
- **Borderless (⌘B):** no title bar or border, and the window stays above other windows. Drag the picture to move it. Full screen turns borderless off.
- **Lock Aspect Ratio (⌘A):** resizing keeps the screen's shape: 3:2 for GBA, 10:9 for Game Boy, or 8:7 with Super Game Boy borders.
- **Full screen (⌃⌘F):** the picture is letterboxed in black and the pointer hides until you move the mouse. Press Escape to leave.
- **Display sleep:** the display stays awake while the game runs and isn't paused, because a game controller doesn't count as activity. Turn this off in Settings › General.

The window's size, position and borderless setting are remembered.

### Settings

The **Settings** tabs (⌘,) are:

- **General:** where battery saves, states and screenshots go; pausing in the background; keeping the display awake
- **Audio/Video:** volume, mute, *Clean up GBA music* (GBA games), aspect ratio, borderless window, scaling and filtering
- **Emulation:** BIOS intro, fast-forward speed, idle loops, rewind
- **Game Boy:** model, colorization and palette (GB and GBC games)
- **Game Boy Advance:** Game Boy Player rumble, solar sensor level (GBA games)
- **Controls**

### GBA music

GBA games mix their music in software at a low rate that each game picks: 13,379 Hz in Advance Wars, 21,024 Hz in Golden Sun. The console plays the result as 8-bit samples without smoothing, which adds a band of harsh, metallic hiss above the music. Small speakers can't reproduce it; studio monitors and good headphones do.

**Clean up GBA music** (on by default; Settings › Audio/Video, or a default in the builder) works out each game's mixing rate while it plays. It filters out everything above that rate's limit and removes a small constant offset in the GBA's output. The music itself is unchanged. The filter also smooths the sharp edges of the GBA's square-wave channels slightly, as the console's own speaker does.

### Where files go

Everything is in `~/Library/Application Support/mGBA Games/<app name>/`:

- `config.ini`
- `saves/<ROM name>.sav`, using the same naming as mGBA, so existing mGBA saves can be copied in
- `states/`
- `screenshots/`
- `<ROM name>.cheats`

Rebuilding an app keeps its save and settings.

## Updating mGBA

```bash
git -C mgba fetch origin && git -C mgba checkout <tag or commit>
scripts/build-app.sh                  # rebuilds the core library and the player
git add mgba && git commit -m "mGBA: …"
```

Games built earlier keep their own copy of the core, so rebuild a game to give it the new one. Local changes to mGBA, if they're ever needed, go in `patches/` and are applied at build time, never committed into the submodule.

## Repository layout

| Path | What it is |
|---|---|
| `Builder/` | GB App Builder (SwiftUI) |
| `Player/` | The player each game app is made from (AppKit/SwiftUI plus a small C bridge to mGBA) |
| `Shared/` | The `game.json` format |
| `mgba/` | Git submodule [mgba-emu/mgba](https://github.com/mgba-emu/mgba), untouched |
| `patches/` | Local mGBA patches (none so far) |
| `scripts/` | Setup, build and icon scripts |
| `project.yml` | XcodeGen project spec |

## Credits

- [mGBA](https://mgba.io) by Jeffrey Pfau and contributors, under the Mozilla Public License 2.0. It's used unmodified from source, and its artwork is the basis of the builder icon and the fallback app icons.
- Box art from [libretro-thumbnails](https://github.com/libretro-thumbnails); ROM names from [libretro-database](https://github.com/libretro/libretro-database) (No-Intro DATs).
- Game Boy, Game Boy Color and Game Boy Advance are trademarks of Nintendo. This project is not affiliated with Nintendo.

© 2026 Harald Striepe. Code and documentation in this repository only.
