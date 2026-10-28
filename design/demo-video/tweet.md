# X post for the demo video

Attach `out/hyperpoint-demo.mp4` to the first post. Lengths are counted the way X counts them, with a link as 23
characters and ⌘⌥⇧⌃ as 2 each.

## First post, pick one

**A. The story (254/280)**

```
I ran a mouse app and Karabiner just for a gesture button and a hyper key.

So I built Hyperpoint: one 1.2 MB menu bar app for both. Remap buttons and gestures by pressing them, make the wheel glide, turn Caps Lock into ⌘⌥⇧⌃.

hyperpoint.progremir.dev
```

**B. The pitch (257/280)**

```
Replace Logi Options+. Hyper key included.

Hyperpoint is a 1.2 MB macOS menu bar app. It remaps your mouse's buttons and gestures, makes the wheel glide, and turns Caps Lock into ⌘⌥⇧⌃. One app, so nothing fights over your keys.

hyperpoint.progremir.dev
```

## Thread replies (optional)

2/ (200)

```
You set it up by pressing. Click Add Rule, press the button on your mouse, pick what it does: Mission Control, App Exposé, a Space, any shortcut, or a modifier held for as long as you hold the button.
```

3/ (162)

```
The hyper key is per keyboard. Caps Lock can be hyper on your desk keyboard and stay Caps Lock on your laptop. One switch in the menu bar turns it off everywhere.
```

4/ (160)

```
Scrolling: each wheel step glides as an eased pulse, sized by a speed curve you drag into shape. Or hold any button and move the mouse to scroll, with momentum.
```

5/ (161)

```
Everything lives in one JSON file. There's a Claude Code skill for it, so "make my back button hold ⌘" gets edited, checked and confirmed against the app's log.
```

6/ (128)

```
No account, no network code, signed and notarized. macOS 27 on Apple silicon.

Code's on GitHub: github.com/progremir/hyperpoint
```

## Video alt text

```
Demo of Hyperpoint, a macOS menu bar app. Caps Lock is held and splits into Command, Option, Shift and Control, which merge back into one hyper key ✦. In the Buttons settings, Add Rule listens, the right mouse button is pressed and a rule appears: Right button, Hold and move, Scroll. The Scrolling settings show a speed curve with a marker sweeping from 1 to 150 wheel steps per second. It ends on hyperpoint.progremir.dev.
```

## Editorial cut alt text

For `out/hyperpoint-editorial.mp4`, the calmer version.

```
Demo of Hyperpoint, a macOS menu bar app, on grey paper cards. Caps Lock is pressed, splits into Command, Option, Shift and Control, and they merge into one hyper key ✦; a list turns it on for the desk keyboard and leaves the MacBook keyboard on Caps Lock. In a table of mouse button rules, Add rule listens, the right button is pressed and a row types itself in: Right button, Hold and move, Scroll. Wheel steps become eased pulses that sum into a smooth curve, then a marker climbs the speed curve from 1 to 150 steps per second. At the end a Mac Caps Lock key, its ⇪ drawn as the Hyperpoint arrow over the Caps Lock light, is pressed and the light turns green. The symbol lifts off the key, tilts into a mouse pointer, clicks, glides and double-clicks, then settles as the logo. It ends on the Hyperpoint logo and hyperpoint.progremir.dev.
```

## Keycaps cut alt text

For `out/hyperpoint-keycaps.mp4`, the 3D keycap version.

```
Glossy 3D keycaps on black. "Your keyboard has a spare key. It's Caps Lock." A Caps Lock keycap whose ⇪ is the Hyperpoint arrow over a green bar floats in the middle while letter keys pop in around it, each named as Caps Lock plus that key, a new shortcut. The keys fly together into a full MacBook keyboard behind a large green ✦ + any key: a shortcut of your own on every key. The keyboard scatters and a Logitech MX Master 4 rises in: "And every button on your mouse. Press it, pick what it does." Its top button, thumb buttons and thumb wheel light up in turn, labeled Mission Control, Switch Spaces and App Exposé. Then "And a wheel that glides": as the wheel is flicked, a feed labeled A plain wheel jumps a notch at a time while one labeled Hyperpoint glides. The mouse and keycaps then tumble beside "One app for your mouse", which changes to "keyboard", with a Download for Mac button and hyperpoint.progremir.dev.
```

## About the video

- `keycaps.html` (22 s, 120 BPM) draws its keycaps with three.js on the GPU; `node render.cjs keycaps.html` renders it.
  The mouse is Logitech's MX Master 4 model from Sketchfab
  (https://sketchfab.com/3d-models/910-007575-mx-master-4-mac-space-black-3d2ad75a27cd4b7d96c86b34719bedaf), saved as
  `models/mx-master-4.glb`; its license allows using it in the video. At 63 MB it is not committed: download it
  from that page to render this cut.

- Two cuts: `demo.html` (15 s, fast, 140 BPM) and `editorial.html` (46 s, calm paper cards, 100 BPM, its music lifting
  as a Caps Lock key turns into the logo). `node render.cjs editorial.html` renders the second.

- 15 s, 1920×1080, 60 fps, H.264 with AAC sound. X loops it, and its first frame is the title card, so the poster reads
  before it plays.
- The settings windows are the app's own `-snapshotSettings` PNGs. The keycaps are drawn in HTML.
- The music and sound effects are an original 140 BPM track that `music.cjs` synthesizes, so there is nothing to
  license. Its hits come from the cues in `demo.html` (`window.CUES`), so they move when the video's timing does.
- To change it, edit `demo.html` (open it in a browser to watch it loop, or add `?t=12.5` to freeze a moment), then run
  `node render.cjs`, which needs Playwright's Chromium and ffmpeg. `node render.cjs --music` redoes only the sound.
