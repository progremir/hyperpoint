// Motion for the landing page. Everything here is progressive: without this file every section is
// visible and still. Reveals and intros use IntersectionObserver; the card stories share one
// requestAnimationFrame clock that stops whenever the cards are off screen.
(() => {
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const root = document.documentElement;
  window.hpReady = true;

  /* Island nav and its sheet ------------------------------------------------ */

  const burger = document.querySelector(".burger");
  const sheet = document.getElementById("sheet");
  sheet.inert = true;

  function setSheet(open) {
    sheet.classList.toggle("open", open);
    sheet.inert = !open;
    sheet.setAttribute("aria-hidden", String(!open));
    burger.setAttribute("aria-expanded", String(open));
    burger.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    document.body.classList.toggle("menu-open", open);
    if (open) sheet.querySelector("a").focus({ preventScroll: true });
  }
  burger.addEventListener("click", () => setSheet(!sheet.classList.contains("open")));
  sheet.addEventListener("click", (e) => { if (e.target.closest("a")) setSheet(false); });
  addEventListener("keydown", (e) => {
    if (e.key === "Escape" && sheet.classList.contains("open")) { setSheet(false); burger.focus(); }
  });

  // The section in view is the current one in both menus.
  const navLinks = [...document.querySelectorAll('.nav-links a, .sheet a[href^="#"]')];
  const current = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      const id = "#" + entry.target.id;
      for (const a of navLinks) a.setAttribute("aria-current", String(a.getAttribute("href") === id));
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  for (const id of ["top", "why", "features", "how", "proof", "faq"]) {
    const el = document.getElementById(id);
    if (el) current.observe(el);
  }

  if (reduced) return;

  /* Scroll reveal ------------------------------------------------------------ */

  const reveal = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      reveal.unobserve(entry.target);
    }
  }, { threshold: 0.15 });
  document.querySelectorAll(".reveal").forEach((el) => reveal.observe(el));

  /* Intros: the hero menu loads its rows, the cards rise in -------------------- */

  const desk = document.querySelector(".desk");
  desk.querySelectorAll(".mi").forEach((el, i) => {
    const inMenu = el.closest(".menu");
    el.style.setProperty("--d", (inMenu ? 260 + i * 45 : i * 60) + "ms");
  });

  const bento = document.querySelector(".bento");
  const cards = [...bento.querySelectorAll(".card")];
  cards.forEach((card, i) => card.style.setProperty("--d", i * 85 + "ms"));

  const intro = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("in");
      intro.unobserve(entry.target);
      if (entry.target === bento) startStories();
    }
  }, { threshold: 0.3 });
  intro.observe(desk);
  intro.observe(bento);

  /* Story clock ---------------------------------------------------------------- */

  const stories = [];
  let bentoVisible = false;
  let running = false;
  let last = 0;

  // A story is a loop of cues, [time, fn], plus an optional frame(t) for continuous motion.
  // Every loop starts and ends on the design as it sits in the HTML.
  function story(el, duration, cues, frame) {
    return { el, duration, cues: cues.sort((a, b) => a[0] - b[0]), frame, t: 0, i: 0, start: 0 };
  }

  function tick(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    for (const s of stories) {
      s.start -= dt;
      if (s.start > 0) continue;
      s.t += dt;
      while (s.i < s.cues.length && s.t >= s.cues[s.i][0]) s.cues[s.i++][1]();
      if (s.frame) s.frame(s.t);
      if (s.t >= s.duration) { s.t -= s.duration; s.i = 0; }
    }
    if (running) requestAnimationFrame(tick);
  }

  function setRunning(on) {
    if (on === running) return;
    running = on;
    if (on) { last = performance.now(); requestAnimationFrame(tick); }
  }

  new IntersectionObserver(([entry]) => {
    bentoVisible = entry.isIntersecting;
    setRunning(bentoVisible && stories.length > 0 && !document.hidden);
  }).observe(bento);
  document.addEventListener("visibilitychange", () => setRunning(bentoVisible && stories.length > 0 && !document.hidden));

  function startStories() {
    // Offset so attention travels around the grid in reading order.
    const offsets = { reconnect: 1.4, hyper: 2.3, curve: 3.2, rules: 4.1 };
    for (const card of cards) {
      const s = makers[card.dataset.story](card);
      s.start = offsets[card.dataset.story];
      stories.push(s);
    }
    setRunning(bentoVisible && !document.hidden);
  }

  // Fades text out, swaps it, fades it back in, as two cues.
  function swap(cues, t, el, text) {
    cues.push([t, () => el.classList.add("swap")], [t + 0.2, () => { el.textContent = text; el.classList.remove("swap"); }]);
  }

  const makers = {
    // The mouse sleeps, loses its setup, reconnects, and every setting is written back.
    reconnect(card) {
      const state = card.querySelector(".state");
      const text = card.querySelector(".state-text");
      const checks = [...card.querySelectorAll(".chk")];
      const time = card.querySelector(".foot time");
      const times = ["11:07", "13:26", "16:52", "9:41"];
      let n = 0;
      const cues = [];
      cues.push([1.0, () => { state.dataset.s = "off"; state.classList.remove("ring"); }]);
      swap(cues, 0.9, text, "Not connected");
      checks.forEach((c, i) => cues.push([1.3 + i * 0.06, () => c.classList.add("off")]));
      cues.push([2.5, () => { state.dataset.s = "busy"; }]);
      swap(cues, 2.4, text, "Applying…");
      checks.forEach((c, i) => cues.push([3.0 + i * 0.16, () => c.classList.remove("off")]));
      cues.push([4.0, () => { state.dataset.s = "on"; state.classList.add("ring"); }]);
      swap(cues, 3.9, text, "Connected");
      cues.push([4.1, () => time.classList.add("swap")]);
      cues.push([4.3, () => { time.textContent = times[n++ % times.length]; time.classList.remove("swap"); }]);
      return story(card, 8, cues);
    },

    // Caps Lock goes down, the four modifiers light, T sends the full chord, everything lets go.
    hyper(card) {
      const caps = card.querySelector(".caps");
      const mods = [...card.querySelectorAll(".mod")];
      const t = card.querySelector(".keycap.t");
      const chip = card.querySelector(".chip");
      const cues = [
        [0.5, () => caps.classList.add("down", "lit")],
        [1.6, () => t.classList.add("down")],
        [1.7, () => chip.classList.add("on")],
        [2.5, () => t.classList.remove("down")],
        [3.3, () => caps.classList.remove("down", "lit")],
        [3.6, () => chip.classList.remove("on")],
      ];
      mods.forEach((m, i) => {
        cues.push([0.7 + i * 0.07, () => m.classList.add("on")]);
        cues.push([3.35 + i * 0.05, () => m.classList.remove("on")]);
      });
      return story(card, 5, cues);
    },

    // A dot rides the speed curve from a slow turn to a flick and back while the readout counts.
    curve(card) {
      const rider = card.querySelector(".rider");
      const scrub = rider.querySelector(".scrub");
      const knob = rider.querySelector(".knob");
      const halo = rider.querySelector(".halo");
      const out = card.querySelector("output");
      const rest = out.textContent;
      const pts = [[1, 40], [5, 250], [15, 900], [40, 2800], [120, 9000]];
      const X = (r) => 36 + (Math.log(r) / Math.log(150)) * 312;
      const Y = (v) => 168 - (Math.log(v / 10) / Math.log(3000)) * 144;
      const speed = (r) => {
        for (let i = 1; i < pts.length; i++) {
          const [r0, v0] = pts[i - 1], [r1, v1] = pts[i];
          if (r <= r1) return v0 * Math.pow(v1 / v0, Math.log(r / r0) / Math.log(r1 / r0));
        }
        return pts[pts.length - 1][1];
      };
      const sig = (v) => { const u = Math.pow(10, Math.floor(Math.log10(v)) - 2); return Math.round(v / u) * u; };
      const rate = (r) => (r < 10 ? r.toFixed(1).replace(/\.0$/, "") : Math.round(r).toString());
      const L = Math.log;
      const keys = [[0, L(15)], [0.6, L(15)], [2.4, L(120)], [2.9, L(120)], [4.9, L(1)], [5.2, L(1)], [6.3, L(15)]];
      const io = (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
      const track = (t) => {
        if (t <= keys[0][0]) return keys[0][1];
        for (let i = 1; i < keys.length; i++) {
          const [t1, v1] = keys[i], [t0, v0] = keys[i - 1];
          if (t <= t1) return v0 + (v1 - v0) * io((t - t0) / (t1 - t0));
        }
        return keys[keys.length - 1][1];
      };
      const draw = (r) => {
        const x = X(r), y = Y(speed(r));
        scrub.setAttribute("x1", x); scrub.setAttribute("x2", x);
        knob.setAttribute("cx", x); knob.setAttribute("cy", y);
        halo.setAttribute("cx", x); halo.setAttribute("cy", y);
      };
      draw(15);
      const cues = [
        [0.1, () => rider.classList.add("on")],
        [6.5, () => { rider.classList.remove("on"); out.textContent = rest; }],
      ];
      return story(card, 7.4, cues, (t) => {
        if (t > 6.5) return;
        const r = Math.exp(track(t));
        draw(r);
        out.textContent = `${rate(r)} steps/s: ${sig(speed(r)).toLocaleString("en-US")} pt/s`;
      });
    },

    // Add Rule listens, a press lands as a new rule on top, the others step down, the last leaves.
    rules(card) {
      const btn = card.querySelector(".fake-btn");
      const slot = card.querySelector(".rp-slot");
      const list = card.querySelector(".rp-list");
      const queue = [
        ["Gesture button", "Hold, move left", "Space to the left"],
        ["Right button", "Hold and move", "Scroll"],
        ["Gesture button", "Hold, move down", "App Exposé"],
        ["Gesture button", "Hold, move right", "Space to the right"],
      ];
      const row = (cells) => {
        const li = document.createElement("li");
        for (const c of cells) li.append(Object.assign(document.createElement("span"), { textContent: c }));
        return li;
      };
      let fresh = null, leaving = null;
      const cues = [
        [0.4, () => btn.classList.add("down")],
        [0.6, () => { btn.classList.remove("down"); btn.classList.add("listening"); slot.classList.add("listen"); }],
        [2.0, () => {
          slot.classList.remove("listen");
          btn.classList.remove("listening");
          const rows = [...list.children];
          leaving = rows[rows.length - 1];
          queue.push([...leaving.children].map((s) => s.textContent));
          rows.forEach((li, i) => li.style.setProperty("--slot", i + 1));
          leaving.classList.add("leave");
          fresh = row(queue.shift());
          fresh.style.setProperty("--slot", 0);
          fresh.classList.add("enter");
          list.prepend(fresh);
        }],
        [2.06, () => { fresh.classList.remove("enter"); fresh.classList.add("fresh"); }],
        [2.8, () => leaving.remove()],
        [4.4, () => fresh.classList.remove("fresh")],
      ];
      return story(card, 6, cues);
    },
  };

  /* Tagline: each word lights up in reading order as the section scrolls past ------- */

  const tagline = document.querySelector("[data-words]");
  const words = [];
  for (const node of [...tagline.childNodes]) {
    const green = node.nodeType === 1 && node.classList.contains("g");
    if (node.nodeType === 1 && !green) continue; // <br>
    const parts = node.textContent.split(/(\s+)/);
    const frag = document.createDocumentFragment();
    for (const part of parts) {
      if (!part) continue;
      if (/^\s+$/.test(part)) { frag.append(part); continue; }
      const w = document.createElement("span");
      w.className = green ? "w g" : "w";
      w.textContent = part;
      words.push(w);
      frag.append(w);
    }
    node.replaceWith(frag);
  }
  const section = tagline.closest(".tagline");
  section.classList.add("armed");

  let queued = false;
  function light() {
    queued = false;
    const r = tagline.getBoundingClientRect();
    const vh = innerHeight;
    const progress = (vh * 0.85 - r.top) / (vh * 0.35 + r.height);
    const lit = Math.round(Math.min(1, Math.max(0, progress)) * words.length);
    words.forEach((w, i) => w.classList.toggle("lit", i < lit));
  }
  const onScroll = () => { if (!queued) { queued = true; requestAnimationFrame(light); } };
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) { addEventListener("scroll", onScroll, { passive: true }); light(); }
    else removeEventListener("scroll", onScroll);
  }).observe(section);
})();
