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

  // ---- copy buttons on terminals ----
  document.querySelectorAll(".terminal").forEach((term) => {
    const bar = term.querySelector(".bar");
    const pre = term.querySelector("pre");
    if (!bar || !pre || term.hasAttribute("data-nocopy")) return;

    // Copy only the runnable commands — strip the `$` prompt, comments, output.
    const cmds = [...pre.querySelectorAll(".c")].map((el) => el.textContent.trim()).filter(Boolean);
    if (!cmds.length) return;
    const text = cmds.join("\n");

    // Keep the button reachable by assistive tech: the "img" role (with its
    // aria-label) belongs on the visual transcript, not the whole block + button.
    if (term.getAttribute("role") === "img") {
      const label = term.getAttribute("aria-label");
      term.removeAttribute("role");
      term.removeAttribute("aria-label");
      pre.setAttribute("role", "img");
      if (label) pre.setAttribute("aria-label", label);
    }

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "copy";
    btn.setAttribute("aria-label", `Copy command${cmds.length > 1 ? "s" : ""} to clipboard`);
    btn.innerHTML =
      '<svg viewBox="0 0 24 24" width="13" height="13" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg><span>Copy</span>';
    bar.appendChild(btn);

    const setLabel = (s) => { const l = btn.querySelector("span"); if (l) l.textContent = s; };
    let resetT = 0;
    btn.addEventListener("click", async () => {
      let ok = false;
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(text);
          ok = true;
        }
      } catch (_) { /* fall through to legacy copy */ }
      if (!ok) {
        const ta = document.createElement("textarea");
        ta.value = text; ta.setAttribute("readonly", "");
        ta.style.position = "fixed"; ta.style.left = "-9999px";
        document.body.appendChild(ta); ta.select();
        try { ok = document.execCommand("copy"); } catch (_) { ok = false; }
        document.body.removeChild(ta);
      }
      btn.classList.toggle("copied", ok);
      setLabel(ok ? "Copied" : "⌘C to copy");
      clearTimeout(resetT);
      resetT = setTimeout(() => { btn.classList.remove("copied"); setLabel("Copy"); }, 1600);
    });
  });

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
