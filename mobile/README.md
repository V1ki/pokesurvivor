# PokéSurvivor for Android (Capacitor)

The web game packaged as a native Android app: **single player, fully offline**
(no internet permission, no accounts). The game runs in app mode
(`window.PS_APP = true`, set by `build-www.js`):

- no login screen: it plays straight away with the save stored on the device;
- online-only parts are hidden (friends/co-op, leaderboard, support link,
  logout, fullscreen button, auto-updater, service worker);
- Settings › Account becomes "your game is saved on this device" + "Delete save".

Native side (`android/app/src/main/java/com/v1ki/pokesurvivor/MainActivity.java`,
`shell.js`):

- immersive fullscreen (status and navigation bars hidden), landscape lock,
  screen kept on while playing, sound without a first tap;
- highest display refresh rate requested (note: Android System WebView still
  paces `requestAnimationFrame` at 60 fps; the game runs a steady 60);
- Back button: pauses/resumes during a run, closes the open screen in menus,
  and sends the app to the background from the main menu;
- short vibration when the player is hit (`@capacitor/haptics`);
- app icon and splash generated from the game's own icons (`make-icons.py`).

## Build

Requirements: Node, **JDK 17** (Capacitor 6), Android SDK with API 34.

```bash
node tools/build.js                    # in the repo root: index.html + js/app.min.js
cd mobile
npm install
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
npm run apk                            # build-www.js + cap sync + gradle assembleDebug
```

The APK is `android/app/build/outputs/apk/debug/app-debug.apk` (~85 MB).
Install it on a phone with USB debugging enabled:

```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

If `npm` times out on this network, prefix the command with
`NODE_OPTIONS=--no-network-family-autoselection`.

Icons/splash after changing `assets/icons/`: `python3 mobile/make-icons.py` (needs Pillow).

## Notes

- Saves live in the app's WebView storage: they survive app updates
  (`adb install -r`) but are erased if the app is uninstalled or its data cleared.
- For personal use only: Pokémon is a trademark of Nintendo / Creatures / GAME FREAK /
  The Pokémon Company, and the sprites are CC BY-NC 4.0 (non-commercial). Do not
  publish this app on app stores.
