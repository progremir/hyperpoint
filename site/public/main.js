// Motion for the landing page, after the keycaps launch film (design/demo-video/keycaps.html). Everything here is
// progressive: without this file, or with reduced motion, every section shows its own picture, still.
(() => {
  window.hpReady = true;

  // The feeds' rows, the same in the still picture and on the stage
  const dots = ["#52e07a", "#e8dcc2", "#8794a3", "#5a5e66"];
  let seed = 41;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
  const rows = Array.from({ length: 30 }, () => [dots[Math.floor(rnd() * 4)], 40 + rnd() * 50, 25 + rnd() * 50]);
  const html = rows.map(([c, a, b]) => `<div class="frow"><i style="background:${c}"></i><div><u style="width:${a}%"></u><u style="width:${b}%"></u></div></div>`).join("");
  for (const l of document.querySelectorAll(".flist")) l.innerHTML = html;

  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  /* Scroll reveal ------------------------------------------------------------ */

  const reveal = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      reveal.unobserve(entry.target);
    }
  }, { threshold: 0.15 });
  document.querySelectorAll(".reveal").forEach((el) => reveal.observe(el));

  /* The stage ------------------------------------------------------------------- */

  // The film's objects live on one stage behind the whole page, and only the text scrolls past: the mouse, Caps
  // Lock, the keys it turns into shortcuts, and six loose keys. Their labels ride on them.
  const key = (name, w, h) => `<div class="sprite" data-sprite="${name}" style="aspect-ratio: ${w} / ${h}"><img src="assets/sprite-key-${name}.webp" alt=""></div>`;
  const stage = document.createElement("div");
  stage.className = "stage";
  stage.setAttribute("aria-hidden", "true");
  stage.innerHTML = `
    <div class="sprite" data-sprite="clusters" style="aspect-ratio: 2880 / 913"><img src="assets/sprite-clusters.webp" alt=""></div>
    ${key("k", 411, 414)}${key("j", 373, 370)}
    <div class="sprite" data-sprite="caps" style="aspect-ratio: 984 / 708">
      <img src="assets/sprite-caps.webp" alt="">
      <span class="tag label hero-tag" data-show="0"><b>Caps Lock</b> → <span class="glyphs">⌘⌥⇧⌃</span></span>
      <div class="caps-note label" data-show="3"><span class="pill">Hold it and it's <b class="glyphs">⌘⌥⇧⌃</b></span><span class="count">Caps Lock + <b data-count>A</b> is a new shortcut</span></div>
    </div>
    <div class="sprite mouse" data-sprite="mouse" style="aspect-ratio: 1340 / 812">
      <img class="front" src="assets/sprite-mouse.webp" alt="">
      <div class="side"><img src="assets/sprite-mouse-side.webp" alt=""><i class="spin"></i></div>
      <div class="callouts-film" data-show="1">
        <i class="glow" style="--x: 23.2%; --y: 28.2%; --d: 0s"></i>
        <i class="glow" style="--x: 49.9%; --y: 63.6%; --d: 0.5s"></i>
        <i class="glow" style="--x: 21.8%; --y: 40.1%; --d: 1s"></i>
        <svg class="leaders-film" viewBox="0 0 100 100" preserveAspectRatio="none">
          <line x1="23.2" y1="28.2" x2="-8.5" y2="22.9"/><line x1="49.9" y1="63.6" x2="108.5" y2="64.8"/><line x1="21.8" y1="40.1" x2="-8.5" y2="52.5"/>
        </svg>
        <i class="dot" style="left: 23.2%; top: 28.2%"></i><i class="dot" style="left: 49.9%; top: 63.6%"></i><i class="dot" style="left: 21.8%; top: 40.1%"></i>
        <ul class="label">
          <li class="callout" style="top: 22.9%"><b>Right button</b> → Hold and move to scroll</li>
          <li class="callout r" style="top: 64.8%"><b>Thumb buttons</b> → Switch Spaces</li>
          <li class="callout" style="top: 52.5%"><b>Wheel click</b> → Mission Control</li>
        </ul>
      </div>
    </div>
    ${key("cmd", 292, 280)}${key("opt", 309, 297)}${key("shift", 312, 290)}${key("ctrl", 278, 261)}
    <div class="feeds-film" data-show="2">
      <div class="feeds">
        <div class="feed"><p class="fl">A plain wheel</p><div class="fwin"><div class="flist"></div></div></div>
        <div class="feed on"><p class="fl">Hyperpoint</p><div class="fwin"><div class="flist"></div></div></div>
      </div>
    </div>`;
  document.body.prepend(stage);

  // Where each object sits in each [data-scene] section, in order: the hero, the mouse's buttons, its wheel, the hyper
  // key, the end card. Each entry is [x, y] as fractions of the screen, w as a fraction of its unit (the width on a
  // phone, otherwise at most 1.6 screen heights), then rotation in degrees, opacity, blur in px, and for the mouse
  // which way it faces (0 front, 1 side). Wide screens and phones each have their own.
  const WIDE = {
    mouse: [[.36, .79, .37, 0, 1, 0, 0], [.50, .53, .36, 0, 1, 0, 0], [.33, .55, .25, 0, 1, 0, 1], [.91, .87, .13, -10, .85, 2, 0], [.17, .50, .22, 0, 1, 0, 0]],
    caps: [[.80, .72, .19, 0, 1, 0], [.90, .17, .10, 8, .75, 3], [.88, .82, .11, -6, .8, 2], [.50, .52, .25, 0, 1, 0], [.85, .30, .16, 4, 1, 0]],
    clusters: [[.50, .54, .70, 0, 0, 0], [.50, .54, .70, 0, 0, 0], [.50, .54, .76, 0, 0, 0], [.50, .53, .92, 0, 1, 0], [.50, .53, 1.05, 0, 0, 0]],
    cmd: [[.06, .62, .055, -8, 1, 0], [.09, .30, .05, 12, 1, 0], [.07, .80, .05, -14, 1, 0], [.22, .91, .045, 6, 1, 0], [.07, .10, .055, -10, 1, 0]],
    opt: [[.12, .90, .05, 10, 1, 0], [.15, .80, .045, -6, 1, 0], [.93, .86, .045, 14, 1, 0], [.93, .14, .05, -8, 1, 0], [.92, .62, .05, 10, 1, 0]],
    shift: [[.60, .64, .045, -6, 1, 0], [.83, .80, .045, 10, 1, 0], [.88, .30, .045, -12, 1, 0], [.40, .93, .04, 8, 1, 0], [.74, .08, .05, -6, 1, 0]],
    ctrl: [[.94, .88, .045, 12, 1, 0], [.95, .70, .045, -8, 1, 0], [.15, .24, .045, 6, 1, 0], [.70, .92, .045, -10, 1, 0], [.26, .72, .045, 8, 1, 0]],
    k: [[.22, .20, .07, 0, .55, 0], [.06, .55, .065, 20, .7, 0], [.93, .60, .07, -10, .75, 0], [.05, .87, .07, 14, .7, 0], [.96, .10, .07, -6, .7, 0]],
    j: [[.80, .22, .065, 0, .55, 0], [.70, .90, .06, -14, .7, 0], [.05, .45, .065, 10, .75, 0], [.06, .15, .06, -8, .7, 0], [.07, .34, .065, 12, .7, 0]],
    feeds: [[.64, .56], [.64, .56], [.64, .56], [.64, .56], [.64, .56]],
  };
  const PHONE = {
    mouse: [[.40, .80, .80, 0, 1, 0, 0], [.50, .42, .86, 0, 1, 0, 0], [.50, .38, .62, 0, 1, 0, 1], [.86, .88, .30, -10, .85, 2, 0], [-.04, .42, .40, 8, 1, 0, 0]],
    caps: [[.84, .72, .36, 0, 1, 0], [.88, .76, .22, 8, .75, 3], [1.02, .50, .26, -6, .7, 2], [.50, .48, .60, 0, 1, 0], [1.04, .30, .34, -6, 1, 0]],
    clusters: [[.50, .50, 1.4, 0, 0, 0], [.50, .50, 1.4, 0, 0, 0], [.50, .50, 1.5, 0, 0, 0], [.50, .48, 1.75, 0, 1, 0], [.50, .48, 1.9, 0, 0, 0]],
    cmd: [[.08, .95, .11, -8, 1, 0], [.10, .74, .10, 12, 1, 0], [-.02, .52, .12, -14, 1, 0], [.10, .80, .10, 6, 1, 0], [.95, .62, .09, -10, .9, 0]],
    opt: [[.90, .96, .10, 10, 1, 0], [.92, .27, .08, -6, 1, 0], [.92, .27, .09, 14, 1, 0], [.90, .74, .10, -8, 1, 0], [.05, .70, .09, 10, .9, 0]],
    shift: [[.62, .97, .09, -6, 1, 0], [.08, .27, .08, 10, 1, 0], [.08, .27, .09, -12, 1, 0], [.25, .90, .09, 8, 1, 0], [.04, .16, .08, -6, .9, 0]],
    ctrl: [[.07, .19, .09, 12, .9, 0], [.50, .78, .08, -8, 1, 0], [1.00, .72, .09, 6, 1, 0], [.55, .86, .09, -10, 1, 0], [.96, .82, .08, 8, .9, 0]],
    k: [[.92, .22, .16, 0, .55, 0], [.94, .62, .14, 20, .6, 0], [-.03, .86, .16, -10, .6, 0], [-.02, .62, .16, 14, .6, 0], [-.03, .90, .14, -6, .5, 0]],
    j: [[.10, .42, .14, 0, .5, 0], [.05, .60, .13, -14, .6, 0], [.97, .16, .14, 10, .6, 0], [1.02, .32, .14, -8, .6, 0], [1.03, .52, .13, 12, .5, 0]],
    feeds: [[.50, .67], [.50, .67], [.50, .67], [.50, .67], [.50, .67]],
  };
  // Each object drifts on its own, all the time: [px, rad/s, degrees].
  const FLOAT = { mouse: [6, .6, 1.2], caps: [8, .7, 2], clusters: [5, .4, 0], cmd: [14, .9, 7], opt: [12, .8, 6], shift: [13, 1, 8], ctrl: [12, .85, 7], k: [16, .5, 6], j: [14, .55, 6] };

  const scenes = [...document.querySelectorAll("[data-scene]")];
  const footer = document.querySelector(".footer");
  const sprites = [...stage.querySelectorAll("[data-sprite]")].map((el, i) => ({
    el, name: el.dataset.sprite, phase: i * 1.7, ratio: 1, w0: 0, inv: el.querySelector(".label") != null,
  }));
  const feedsEl = stage.querySelector(".feeds-film");
  const shows = [...stage.querySelectorAll("[data-show]")].map((el) => ({ el, at: +el.dataset.show }));
  const front = stage.querySelector(".mouse .front");
  const side = stage.querySelector(".mouse .side");
  const spin = stage.querySelector(".spin");
  let A = WIDE, unit = 1, vw = 1, vh = 1;

  function layout() {
    vw = innerWidth;
    vh = innerHeight;
    const phone = vw < 768 || vw < vh;
    A = phone ? PHONE : WIDE;
    stage.classList.toggle("portrait", phone);
    unit = phone ? vw : Math.min(vw, vh * 1.6);
    document.documentElement.style.setProperty("--foot", `${footer.offsetHeight}px`);
    // Each object is drawn at its largest size and scaled down from there, so it never blurs from scaling up
    for (const s of sprites) {
      const [w, h] = getComputedStyle(s.el).aspectRatio.split("/").map(Number);
      s.ratio = w / h;
      s.w0 = Math.max(...A[s.name].map((k) => k[2])) * unit;
      s.el.style.setProperty("--w0", `${s.w0}px`);
    }
  }
  layout();
  addEventListener("resize", layout);

  // How far down the page we are, in scenes: 2 when the third section's middle is at the middle of the screen,
  // 2.5 halfway to the fourth's. The last scene is the end card with the footer under it, one screen tall.
  function sceneAt() {
    const focus = vh / 2;
    const mid = scenes.map((el) => { const r = el.getBoundingClientRect(); return r.top + r.height / 2; });
    mid[mid.length - 1] = (scenes[scenes.length - 1].getBoundingClientRect().top + footer.getBoundingClientRect().bottom) / 2;
    if (focus <= mid[0]) return 0;
    for (let i = 0; i < mid.length - 1; i++) if (focus < mid[i + 1]) return i + (focus - mid[i]) / (mid[i + 1] - mid[i]);
    return mid.length - 1;
  }
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const smooth = (u) => u * u * (3 - 2 * u);
  const lerp = (a, b, u) => a + (b - a) * u;
  // A section holds its arrangement while its middle is near the middle of the screen, and eases to the next between.
  const hold = (f) => smooth(clamp((f - 0.18) / 0.64));
  // How much a section's labels show: fully near it, gone a third of the way to the next.
  const near = (s, k) => clamp(1 - (Math.abs(s - k) - 0.12) / 0.2);

  /* The wheel's feeds and the hyper key's count -------------------------------- */

  // The film's two feeds: the wheel is flicked twice, and every notch it passes as it glides to a stop is a step in
  // the plain feed and an eased pulse in Hyperpoint's, while the mouse's own wheel turns. They run on forever, one copy
  // of the rows after another.
  const lists = [...feedsEl.querySelectorAll(".flist")];
  for (const l of lists) l.innerHTML = html + html;
  const outCubic = (u) => 1 - Math.pow(1 - u, 3);
  const FLICK = 4.2, GLIDE = 0.45, NOTCH = (Math.PI * 2) / 24, FLICKS = [0.4, 1.4], LOOP = 3.4;
  const notches = [];
  for (const f of FLICKS) for (let k = 1; k * NOTCH < FLICK * 0.97; k++) notches.push(f - GLIDE * Math.log(1 - (k * NOTCH) / FLICK));
  let feedT = 0, loops = 0;
  function wheel(dt) {
    feedT += dt;
    if (feedT >= LOOP) { feedT -= LOOP; loops++; }
    const t = feedT;
    const row = lists[0].firstElementChild.offsetHeight;
    const step = row * 0.75, copy = rows.length * row, base = loops * notches.length;
    const stepped = step * (base + notches.filter((n) => n <= t).length);
    const eased = step * (base + notches.reduce((a, n) => a + outCubic(clamp((t - n) / 0.3)), 0));
    lists[0].style.transform = `translateY(${-(stepped % copy)}px)`;
    lists[1].style.transform = `translateY(${-(eased % copy)}px)`;
    const angle = loops * FLICKS.length * FLICK + FLICKS.reduce((a, f) => a + (t < f ? 0 : FLICK * (1 - Math.exp(-(t - f) / GLIDE))), 0);
    spin.style.backgroundPositionX = `${(Math.floor((angle / NOTCH) * 6) % 6) * 20}%`;
  }

  const counts = [...document.querySelectorAll("[data-count]")];
  const letters = "ASDFGHJKLQWERTYUIOPZXCVBNM1234567890".split("");
  let letter = 0, countT = 0;

  /* The clock ---------------------------------------------------------------- */

  let raf = 0, last = 0, clock = 0;
  function frame(now) {
    raf = 0;
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    clock += dt;
    const s = sceneAt();
    const i = Math.min(scenes.length - 2, Math.floor(s));
    const e = hold(s - i);
    for (const sp of sprites) {
      const a = A[sp.name][i], b = A[sp.name][i + 1];
      const [amp, speed, tilt] = FLOAT[sp.name];
      const t = clock * speed + sp.phase;
      const x = lerp(a[0], b[0], e) * vw + Math.sin(t) * amp;
      const y = lerp(a[1], b[1], e) * vh + Math.cos(t * 0.8) * amp;
      const scale = (lerp(a[2], b[2], e) * unit) / sp.w0;
      const rot = lerp(a[3], b[3], e) + Math.sin(t * 0.7) * tilt;
      const h0 = sp.w0 / sp.ratio;
      sp.el.style.transform = `translate3d(${(x - sp.w0 / 2).toFixed(1)}px, ${(y - h0 / 2).toFixed(1)}px, 0) rotate(${rot.toFixed(2)}deg) scale(${scale.toFixed(4)})`;
      sp.el.style.opacity = lerp(a[4], b[4], e).toFixed(3);
      const blur = lerp(a[5], b[5], e);
      sp.el.style.filter = blur > 0.05 ? `blur(${blur.toFixed(1)}px)` : "none";
      if (sp.inv) sp.el.style.setProperty("--inv", (1 / scale).toFixed(3));
      if (sp.name === "mouse") {
        const sideness = smooth(clamp((lerp(a[6], b[6], e) - 0.3) / 0.4));
        side.style.opacity = sideness.toFixed(3);
        front.style.opacity = (1 - sideness).toFixed(3);
      }
    }
    const fa = A.feeds[i], fb = A.feeds[i + 1];
    feedsEl.style.transform = `translate3d(${(lerp(fa[0], fb[0], e) * vw - feedsEl.offsetWidth / 2).toFixed(1)}px, ${(lerp(fa[1], fb[1], e) * vh - feedsEl.offsetHeight / 2).toFixed(1)}px, 0)`;
    for (const sh of shows) sh.el.style.opacity = near(s, sh.at).toFixed(3);
    if (near(s, 2) > 0) wheel(dt);
    if (near(s, 3) > 0 && (countT += dt) > 0.42) {
      countT = 0;
      letter = (letter + 1) % letters.length;
      for (const c of counts) c.textContent = letters[letter];
    }
    if (!document.hidden) raf = requestAnimationFrame(frame);
  }
  function play() { if (!raf && !document.hidden) { last = performance.now(); raf = requestAnimationFrame(frame); } }
  document.addEventListener("visibilitychange", play);
  play();
})();
