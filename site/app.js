// Wolf — hero nocturne + scroll reveals. Refined, not spooky. Respects reduced-motion.
(() => {
  "use strict";
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- nav border on scroll ----
  const hdr = document.getElementById("hdr");
  const onScroll = () => hdr.classList.toggle("scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // ---- reveal on view ----
  const revs = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    revs.forEach((el) => el.classList.add("in"));
  } else {
    const io = new IntersectionObserver(
      (entries) => entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      }),
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    revs.forEach((el, i) => { el.style.transitionDelay = `${Math.min(i % 5, 4) * 70}ms`; io.observe(el); });
  }

  // ---- hero nocturne ----
  const canvas = document.getElementById("nocturne");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  let W = 0, H = 0, dpr = Math.min(window.devicePixelRatio || 1, 2);
  let motes = [];

  const AMBER = [232, 152, 58];   // approx --ember in rgb
  const BONE = [232, 226, 210];

  function resize() {
    W = canvas.clientWidth; H = canvas.clientHeight;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const count = Math.round(Math.min(70, (W * H) / 22000));
    motes = Array.from({ length: count }, () => newMote(true));
  }
  function newMote(seed) {
    const warm = Math.random() < 0.55;
    return {
      x: Math.random() * W,
      y: seed ? Math.random() * H : H + 10,
      r: 0.4 + Math.random() * 1.6,
      vy: -(0.05 + Math.random() * 0.28),
      vx: (Math.random() - 0.5) * 0.16,
      a: 0.05 + Math.random() * 0.4,
      tw: Math.random() * Math.PI * 2,
      c: warm ? AMBER : BONE,
    };
  }

  // eyes: two soft amber glows, right of center, slow breathe + rare blink
  const eyes = { cx: 0, cy: 0, gap: 0, r: 0, phase: 0, blink: 1, nextBlink: 3 };
  function placeEyes() {
    eyes.cx = W * 0.72; eyes.cy = H * 0.42;
    eyes.gap = Math.max(46, W * 0.055);
    eyes.r = Math.max(9, W * 0.011);
  }

  function drawEye(x, y, r, alpha) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r * 7);
    g.addColorStop(0, `rgba(245,225,180,${0.9 * alpha})`);
    g.addColorStop(0.18, `rgba(${AMBER[0]},${AMBER[1]},${AMBER[2]},${0.85 * alpha})`);
    g.addColorStop(0.5, `rgba(200,110,40,${0.22 * alpha})`);
    g.addColorStop(1, "rgba(120,60,20,0)");
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, r * 7, 0, Math.PI * 2); ctx.fill();
    // hot core
    ctx.fillStyle = `rgba(255,240,210,${0.95 * alpha})`;
    ctx.beginPath(); ctx.arc(x, y, r * 0.5, 0, Math.PI * 2); ctx.fill();
  }

  let t = 0, raf = 0;
  function frame() {
    t += 0.016;
    ctx.clearRect(0, 0, W, H);

    // motes
    for (const m of motes) {
      m.y += m.vy; m.x += m.vx; m.tw += 0.03;
      if (m.y < -10 || m.x < -10 || m.x > W + 10) Object.assign(m, newMote(false));
      const a = m.a * (0.6 + 0.4 * Math.sin(m.tw));
      ctx.fillStyle = `rgba(${m.c[0]},${m.c[1]},${m.c[2]},${a})`;
      ctx.beginPath(); ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2); ctx.fill();
    }

    // eyes: breathe + occasional slow blink
    eyes.phase += 0.014;
    eyes.nextBlink -= 0.016;
    if (eyes.nextBlink <= 0) { eyes.blink = 0; if (eyes.nextBlink < -0.22) { eyes.blink = 1; eyes.nextBlink = 4 + Math.random() * 5; } }
    const breathe = 0.55 + 0.18 * Math.sin(eyes.phase);
    const alpha = breathe * eyes.blink;
    if (alpha > 0.02) {
      drawEye(eyes.cx - eyes.gap / 2, eyes.cy, eyes.r, alpha);
      drawEye(eyes.cx + eyes.gap / 2, eyes.cy, eyes.r, alpha);
    }

    raf = requestAnimationFrame(frame);
  }

  function start() {
    resize(); placeEyes();
    if (reduce) {
      // single static, calm frame
      for (const m of motes) { ctx.fillStyle = `rgba(${m.c[0]},${m.c[1]},${m.c[2]},${m.a})`; ctx.beginPath(); ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2); ctx.fill(); }
      drawEye(eyes.cx - eyes.gap / 2, eyes.cy, eyes.r, 0.6);
      drawEye(eyes.cx + eyes.gap / 2, eyes.cy, eyes.r, 0.6);
      return;
    }
    cancelAnimationFrame(raf); frame();
  }

  window.addEventListener("resize", () => { resize(); placeEyes(); }, { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) cancelAnimationFrame(raf);
    else if (!reduce) frame();
  });
  start();
})();
