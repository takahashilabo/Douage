# Douage - Dou-age (Championship Toss) VR Experience

A minimal VR experience (MVP) for Meta Quest 3 that lets you experience being tossed into the air by your championship teammates, right at the center of the celebration. Built with Godot 4.7 + WebXR, so no APK build or sideloading is required — you just open a URL in the Meta Quest Browser.

## What it does (current MVP)

- Placeholder stadium (grass field, infield, stands on four sides, light towers)
- 8 teammates (simple primitive models) surround the player and swing their arms up in sync with the toss
- The player's head (camera) rises and falls through the toss cycles, ending with one final high toss
- Confetti effect
- Starts the WebXR session via an "Enter VR" button
- On browsers without WebXR support (e.g. during desktop development), a "Start Preview" button lets you check the experience without VR
- Before the toss starts, the player begins lying on the ground (teammates visible all around), and pressing the A/B button on either Quest controller triggers the toss and, after it finishes, replays it
- Japanese UI text is rendered with a bundled Noto Sans JP font (Godot's default font has no Japanese glyphs)

## Not yet included (next steps)

- Crowd cheer / chant sound effects (the `CheerPlayer` node will play automatically once you assign an `AudioStream` to it — bring your own audio file)
- Proper 3D models (teammates and the stadium are all primitive-shape placeholders)
- Locomotion / other interactions (intentionally omitted — this experience is focused purely on "being tossed")

## Opening the project

Open `project.godot` in the Godot 4.7.x editor (this machine has Godot.app v4.7.2 installed).

## Desktop preview

Run `scenes/Main.tscn` in the editor (F6). Since WebXR isn't available on desktop, you'll see a "Start Preview" button. Pressing it starts the lying-down waiting pose; press Space or Enter to trigger the toss (mouse-look is also available while in preview mode — click to capture the mouse, Esc to release it).

## Testing on Quest 3

### 1. Export the project to Web

1. Open `Project > Export...`
2. The `Web` preset is already defined in `export_presets.cfg` (thread support disabled, so no COOP/COEP headers are required)
3. Click `Export Project` to build into `build/web/`

Or from the command line:

```bash
godot --headless --export-release "Web" build/web/index.html
```

### 2. Serve over local HTTPS (mkcert)

WebXR requires a secure context (HTTPS, or access from `localhost` itself). This project uses the same approach as an earlier AR piano project: generate a certificate for your LAN IP with `mkcert`, and serve it over HTTPS on the local network — no external tunnel needed.

One-time certificate setup (replace with your Mac's LAN IP, found via `ipconfig getifaddr en0`):

```bash
brew install mkcert   # if not already installed
cd server
mkcert -key-file key.pem -cert-file cert.pem 192.168.x.x localhost 127.0.0.1
```

After exporting, start the server from the project root:

```bash
python3 server/serve.py
```

This serves the build at `https://<your Mac's LAN IP>:8070/`. Open the same address in the Meta Quest Browser. Since the Quest doesn't trust mkcert's local root CA, the browser may show a "Your connection isn't private" warning — choose "Advanced" → "Proceed" to continue. The connection is still encrypted HTTPS, so WebXR works fine afterward.

### 3. Try it on Quest 3

1. Open the URL above in the Meta Quest Browser
2. Tap the "Enter VR" button in the center of the screen (WebXR sessions can only be started from a user gesture, so this click/tap is required)
3. The headset switches to VR; you start out lying on the ground surrounded by your teammates
4. Press the A or B button on either controller to get tossed — press again after it finishes to replay

## Code structure

- `scenes/Main.tscn` — Root scene. Defines only the minimal structure (`XROrigin3D`, UI, lights); the stadium, teammates, and particles are all built at runtime by `main.gd`
- `scripts/main.gd` — WebXR session management, the toss sequence (tweening the `Rig` node's Y position), teammate arm animation, controller button handling, and procedural generation of the stadium/crowd/confetti

`Rig` (a `Node3D`) is the parent of `XROrigin3D`, and the toss motion is achieved by **moving the Rig itself**. The player's own head tracking stays under `XROrigin3D`, so looking around still feels natural while the "being lifted" sensation comes from the Rig's vertical motion — this helps reduce VR motion sickness.

## Customization tips

- Tweak the constants at the top of `scripts/main.gd` (`TOSS_HEIGHT`, `TOSS_DURATION`, `TOSS_COUNT`, `TEAMMATE_COUNT`, etc.) to adjust toss height, repeat count, and number of teammates
- To use real teammate/stadium models (e.g. `.glb`), drop them into `assets/` and replace the primitive-generation code inside `_build_teammates()` / `_build_stadium()` with `load("res://assets/...")`
