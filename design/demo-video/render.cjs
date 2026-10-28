// Renders a film (demo.html unless another .html is named) to out/hyperpoint-<film>.mp4, one seeked frame at a time,
// so the video never drops a frame, with the sound from music.cjs timed to the page's cues.
//   node render.cjs [editorial.html]                  the full video at 60 fps, with sound
//   node render.cjs [editorial.html] --music          only the sound, muxed into the video already in out/
//   node render.cjs [editorial.html] --stills 5,12.9  PNGs of single moments, to check a scene without a full render
// Needs Playwright's Chromium (npx playwright install chromium) and ffmpeg.
const { chromium } = require("playwright");
const music = require("./music.cjs");
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const FPS = 60;
const out = path.join(__dirname, "out");
const film = path.basename(process.argv.find((a) => a.endsWith(".html")) || "demo.html", ".html");
const stillsAt = process.argv.includes("--stills") ? process.argv[process.argv.indexOf("--stills") + 1].split(",").map(Number) : null;
const audioArgs = ["-c:a", "aac", "-b:a", "192k"];

function run(args) {
  return new Promise((resolve, reject) => {
    const p = spawn("ffmpeg", ["-y", "-loglevel", "error", ...args], { stdio: "inherit" });
    p.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}`))));
  });
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto(`file://${path.join(__dirname, `${film}.html`)}?capture`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 30000 });
  const total = await page.evaluate(() => window.TOTAL);
  const file = path.join(out, `hyperpoint-${film}.mp4`);
  const wav = path.join(out, `music-${film}.wav`);
  if (!stillsAt) music.write(wav, await page.evaluate(() => window.CUES));

  if (process.argv.includes("--music")) {
    await browser.close();
    const tmp = path.join(out, "remux.mp4");
    await run(["-i", file, "-i", wav, "-map", "0:v", "-map", "1:a", "-c:v", "copy", ...audioArgs, "-movflags", "+faststart", tmp]);
    fs.renameSync(tmp, file);
    console.log(`muxed ${wav} into ${file}`);
    return;
  }

  if (stillsAt) {
    for (const t of stillsAt) {
      await page.evaluate((t) => window.render(t), t);
      await page.screenshot({ path: path.join(out, `still-${film}-${t.toFixed(2)}.png`) });
    }
    await browser.close();
    return;
  }

  const ffmpeg = spawn("ffmpeg", [
    "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(FPS), "-i", "-", "-i", wav, "-map", "0:v", "-map", "1:a",
    "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p",
    // Capped, because the editorial cut's film grain would otherwise run near 40 Mbps.
    "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-maxrate", "16M", "-bufsize", "32M", "-profile:v", "high", "-tune", "animation",
    "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
    ...audioArgs, "-shortest", "-movflags", "+faststart", file,
  ], { stdio: ["pipe", "inherit", "inherit"] });
  const done = new Promise((resolve, reject) => ffmpeg.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}`)))));

  const frames = Math.round(total * FPS);
  const started = Date.now();
  for (let i = 0; i < frames; i++) {
    await page.evaluate((t) => window.render(t), i / FPS);
    const png = await page.screenshot({ type: "png" });
    if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once("drain", r));
    if (i % 120 === 0) process.stdout.write(`frame ${i}/${frames}, ${((Date.now() - started) / 1000).toFixed(0)} s\n`);
  }
  ffmpeg.stdin.end();
  await done;
  await browser.close();
  console.log(`wrote ${file}`);
})();
