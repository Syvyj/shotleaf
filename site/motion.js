// The page's motion: the hero is "captured" (words rise, the frame snaps around
// the first word), headings reveal word by word, the privacy band opens like a
// selection, and Lenis smooths the scroll. Everything is an extra: without JS,
// with reduced motion or if a library didn't load, the page is already complete.
(() => {
  const root = document.documentElement;
  const done = () => root.classList.add("ready");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches || new URLSearchParams(location.search).has("still"); // ponytail: ?still is a manual switch to see the reduced-motion page

  // The guide's contents: the section being read is marked (not motion, so always on).
  const toc = [...document.querySelectorAll(".toc a")];
  if (toc.length) {
    const seen = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) toc.forEach((a) => a.classList.toggle("on", a.hash === "#" + e.target.id));
    }, { rootMargin: "-20% 0px -70% 0px" });
    toc.forEach((a) => { const s = document.querySelector(a.hash); if (s) seen.observe(s); });
  }

  if (reduce || !window.gsap || !window.ScrollTrigger) return done();
  root.classList.add("gs");
  const has = (selector) => document.querySelector(selector) !== null;

  // Word split. Screen readers get the heading's text once; the moving words are
  // hidden from them. A nested element (the framed word) moves as one piece.
  const split = (el) => {
    const label = document.createElement("span");
    label.className = "sr-only";
    label.textContent = el.textContent.replace(/\s+/g, " ").trim();
    const shown = document.createElement("span");
    shown.setAttribute("aria-hidden", "true");
    const unit = (child, piece) => {
      const w = document.createElement("span");
      w.className = piece ? "w el" : "w";
      const wi = document.createElement("span");
      wi.className = "wi";
      wi.append(child);
      w.append(wi);
      shown.append(w);
    };
    for (const node of [...el.childNodes]) {
      if (node.nodeType === Node.TEXT_NODE) {
        node.textContent.split(/(\s+)/).forEach((part) => {
          if (!part) return;
          if (/^\s+$/.test(part)) shown.append(" ");
          else unit(document.createTextNode(part));
        });
      } else if (node.nodeType === Node.ELEMENT_NODE) unit(node, true);
    }
    el.replaceChildren(label, shown);
  };
  document.querySelectorAll("[data-split]").forEach(split);

  gsap.registerPlugin(ScrollTrigger);
  const mm = gsap.matchMedia();

  // One smooth-scroll engine, driven by GSAP's ticker so ScrollTrigger reads the same frame.
  const lenis = window.Lenis ? new Lenis({ anchors: { offset: -96 }, autoRaf: false }) : null;
  const raf = (time) => lenis.raf(time * 1000);
  if (lenis) {
    lenis.on("scroll", ScrollTrigger.update);
    gsap.ticker.add(raf);
    gsap.ticker.lagSmoothing(0);
  }

  // The frame's label shows its own size in screen pixels, like the capture picker does.
  const frame = document.querySelector(".hero .frame"), dim = frame && frame.querySelector(".dim");
  const measure = () => {
    if (!dim) return;
    const r = frame.getBoundingClientRect(), k = devicePixelRatio || 1;
    dim.textContent = `${Math.round(r.width * k)} × ${Math.round(r.height * k)}`;
  };

  // The tool tabs: a capture frame moves to the picked tab, and its window opens like a selection.
  const tabBox = document.querySelector(".tabs");
  if (tabBox) {
    const tabs = [...tabBox.querySelectorAll(".tab")], slides = [...document.querySelectorAll(".slide")];
    const sel = document.createElement("span");
    sel.className = "tab-sel fc";
    sel.setAttribute("aria-hidden", "true");
    sel.innerHTML = "<i></i>".repeat(4);
    tabBox.append(sel);
    const place = (tab, duration) => gsap.to(sel, {
      x: tab.offsetLeft - 6, y: tab.offsetTop - 6, width: tab.offsetWidth + 12, height: tab.offsetHeight + 12,
      duration, ease: "power3.inOut", overwrite: "auto",
    });
    const placeNow = () => place(tabBox.querySelector(".tab.on") || tabs[0], 0);
    placeNow();
    addEventListener("resize", placeNow);
    document.fonts?.ready.then(placeNow);
    tabBox.addEventListener("tab", (e) => {
      const { from, to } = e.detail;
      if (from === to) return;
      place(tabs[to], .55);
      gsap.fromTo(slides[from], { autoAlpha: 1, y: 0, scale: 1 }, {
        autoAlpha: 0, y: -12, scale: .985, duration: .35, ease: "power2.in", overwrite: true, clearProps: "opacity,visibility,transform,clipPath",
      });
      gsap.fromTo(slides[to], { autoAlpha: 0, y: 24, clipPath: "inset(8% 6% 8% 6% round 28px)" }, {
        autoAlpha: 1, y: 0, clipPath: "inset(0% 0% 0% 0% round 0px)", duration: .75, delay: .12, ease: "power3.out", overwrite: true,
        clearProps: "opacity,visibility,transform,clipPath",
      });
      gsap.fromTo(tabs[to].querySelectorAll(".cap"), { y: 4 }, { y: 0, duration: .45, stagger: .05, ease: "back.out(3)" });
    });
  }

  // The download count in the button rolls like an odometer (each digit spins a full turn).
  // Screen readers get the number once; hovering the button rolls it again.
  document.querySelectorAll("[data-roll]").forEach((el) => {
    const n = el.textContent.trim();
    const label = document.createElement("span");
    label.className = "sr-only";
    label.textContent = n;
    const shown = document.createElement("span");
    shown.className = "roll";
    shown.setAttribute("aria-hidden", "true");
    const digits = [...n].map(Number);
    const cols = digits.map(() => {
      const dg = document.createElement("span"), col = document.createElement("span");
      dg.className = "dg"; col.className = "col";
      col.innerHTML = "<span>" + [..."01234567890123456789"].join("</span><span>") + "</span>";
      dg.append(col); shown.append(dg);
      return col;
    });
    el.replaceChildren(label, shown);
    const to = (i) => -(10 + digits[i]) * 5; // one full turn, then the digit (20 rows: 5% each)
    gsap.fromTo(cols, { yPercent: 0 }, { yPercent: to, duration: 1.8, delay: .5, stagger: { each: .12, from: "end" }, ease: "power4.out" });
    el.closest("a")?.addEventListener("pointerenter", () => gsap.fromTo(cols, { yPercent: (i) => -digits[i] * 5 }, {
      yPercent: to, duration: 1.1, stagger: { each: .08, from: "end" }, ease: "power3.inOut", overwrite: true,
    }));
  });

  // Hero: navigation, the text under the heading and the buttons never wait for the intro.
  const out = (i) => (i % 2 ? 1 : -1) * 16, down = (i) => (i < 2 ? -1 : 1) * 16;
  if (has(".hero")) gsap.timeline({ defaults: { ease: "power3.out" } })
    .from(".hero h1 .w:not(.el) .wi", { yPercent: 105, duration: .8, stagger: .045 }, .05)
    .from(".hero h1 .w.el .wi", { yPercent: 40, autoAlpha: 0, duration: .7 }, .05)
    .from(".hero .frame > i", { x: out, y: down, autoAlpha: 0, duration: .55, stagger: .05, ease: "back.out(2.2)" }, .45)
    .from(".hero .frame .dim", { autoAlpha: 0, duration: .35, onStart: measure }, .8)
    .from(".hero .icon", { y: 30, rotation: -8, autoAlpha: 0, duration: 1 }, .1)
    .from(".slides", { y: 70, autoAlpha: 0, duration: 1.1 }, .3)
    .from(".tabs .tab", { y: 26, autoAlpha: 0, duration: .6, stagger: .06, clearProps: "transform,opacity,visibility" }, .55)
    .from(".tabs .tab-sel", { autoAlpha: 0, scale: .9, duration: .5, ease: "back.out(2)" }, .95);
  done();
  addEventListener("resize", measure);

  // Reading progress in the nav, and the nav firms up once the page has moved.
  if (has(".nav .progress")) gsap.to(".nav .progress", { scaleX: 1, ease: "none", scrollTrigger: { start: 0, end: "max", scrub: .3 } });
  ScrollTrigger.create({ start: 80, end: "+=100000", toggleClass: { targets: ".nav", className: "scrolled" } });

  // Section headings, word by word as they arrive.
  if (has(".guide-head")) gsap.from(".guide-head h1 .wi", { yPercent: 105, duration: .8, stagger: .05, ease: "power3.out" });
  document.querySelectorAll("main h2[data-split]").forEach((h) => {
    gsap.from(h.querySelectorAll(".wi"), {
      yPercent: 105, duration: .8, stagger: .04, ease: "power3.out",
      scrollTrigger: { trigger: h, start: "top 88%", once: true },
    });
  });

  // Then the copy and the windows under them.
  const rise = [...document.querySelectorAll(".head > p, .tool .about, .feats .feat, .facts li, .install li, .give a, .final-box > p, .final-box .btn, .guide-body figure")];
  if (rise.length) gsap.set(rise, { y: 34, autoAlpha: 0 });
  if (rise.length) ScrollTrigger.batch(rise, {
    start: "top 90%", once: true,
    onEnter: (els) => gsap.to(els, { y: 0, autoAlpha: 1, duration: .75, stagger: .07, ease: "power3.out", overwrite: "auto", clearProps: "transform,opacity,visibility" }),
  });

  // Each tool's window opens like a selection as you reach it, its keys drop in.
  document.querySelectorAll(".tool").forEach((tool) => {
    const mock = tool.querySelector(".stagebox > .mock");
    if (!mock) return;
    gsap.timeline({ scrollTrigger: { trigger: tool, start: "top 72%", once: true } })
      .from(tool.querySelectorAll(".about .cap"), { y: -18, autoAlpha: 0, duration: .5, stagger: .07, ease: "back.out(2.4)" }, 0)
      .fromTo(mock, { clipPath: "inset(10% 8% 10% 8% round 28px)", scale: .94, autoAlpha: 0 }, {
        clipPath: "inset(0% 0% 0% 0% round 0px)", scale: 1, autoAlpha: 1, duration: 1, ease: "power3.out",
        clearProps: "clipPath,transform,opacity,visibility",
      }, .1);
  });

  // Wide screens: the windows drift against the scroll, and the hero eases away as you leave it.
  mm.add("(min-width: 761px)", () => {
    document.querySelectorAll(".tool").forEach((tool) => {
      const box = tool.querySelector(".stagebox");
      if (box) gsap.fromTo(box, { y: 40 }, { y: -40, ease: "none", scrollTrigger: { trigger: tool, start: "top bottom", end: "bottom top", scrub: true } });
    });
    if (has(".hero-top")) gsap.to(".hero-top", { y: -60, opacity: .2, ease: "none", scrollTrigger: { trigger: ".hero-top", start: "top 10%", end: "bottom top", scrub: true } });
  });

  // The screenshot picker can be tried: drag on it for a selection with its size, the flash, Escape cancels.
  const tryPicker = (mock) => {
    const desk = mock.querySelector(".desk"), sel = mock.querySelector(".sel"), loupe = mock.querySelector(".loupe"), flash = mock.querySelector(".flash");
    const loupeStyle = loupe.getAttribute("style");
    let start = null, shot = null;
    const at = (e) => {
      const r = desk.getBoundingClientRect();
      return { x: gsap.utils.clamp(0, 100, (e.clientX - r.left) / r.width * 100), y: gsap.utils.clamp(0, 100, (e.clientY - r.top) / r.height * 100), r };
    };
    const reset = () => {
      start = null; shot?.kill(); shot = null;
      mock.classList.remove("live");
      sel.removeAttribute("style"); flash.removeAttribute("style"); loupe.setAttribute("style", loupeStyle);
    };
    desk.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      reset();
      desk.setPointerCapture(e.pointerId);
      start = at(e);
      Object.assign(sel.style, { left: start.x + "%", top: start.y + "%", width: "0%", height: "0%" });
      mock.classList.add("live");
    });
    desk.addEventListener("pointermove", (e) => {
      if (!start) return;
      const p = at(e), k = devicePixelRatio || 1;
      const w = Math.abs(p.x - start.x), h = Math.abs(p.y - start.y);
      Object.assign(sel.style, { left: Math.min(p.x, start.x) + "%", top: Math.min(p.y, start.y) + "%", width: w + "%", height: h + "%" });
      sel.style.setProperty("--pw", Math.round(w / 100 * p.r.width * k));
      sel.style.setProperty("--ph", Math.round(h / 100 * p.r.height * k));
      Object.assign(loupe.style, { left: p.x + "%", top: p.y + "%" });
    });
    desk.addEventListener("pointerup", (e) => {
      if (!start) return;
      const p = at(e), small = Math.abs(p.x - start.x) / 100 * p.r.width < 6 || Math.abs(p.y - start.y) / 100 * p.r.height < 6;
      start = null;
      if (small) return reset();
      shot = gsap.timeline({ onComplete: reset })
        .fromTo(flash, { opacity: .6 }, { opacity: 0, duration: .45, ease: "power2.out" })
        .fromTo(sel, { scale: 1.03 }, { scale: 1, duration: .4, ease: "back.out(3)" }, 0)
        .to(sel, { autoAlpha: 0, duration: .4 }, 1.4);
    });
    desk.addEventListener("pointercancel", reset);
    document.addEventListener("keydown", (e) => { if (e.key === "Escape" && mock.classList.contains("live")) reset(); });
  };
  if (matchMedia("(pointer: fine)").matches) document.querySelectorAll(".m-pick").forEach(tryPicker);

  // The numbers count up, the privacy icons pop in, install steps fill as you read them, the support spark turns in.
  document.querySelectorAll("[data-count]").forEach((el) => gsap.fromTo(el, { textContent: 0 }, {
    textContent: +el.dataset.count, snap: { textContent: 1 }, duration: 1.4, ease: "power2.out", immediateRender: false,
    scrollTrigger: { trigger: el, start: "top 90%", once: true },
  }));
  const icons = document.querySelectorAll(".facts svg");
  if (icons.length) {
    gsap.set(icons, { scale: 0, rotation: -45 });
    ScrollTrigger.batch(icons, {
      start: "top 90%", once: true,
      onEnter: (els) => gsap.to(els, { scale: 1, rotation: 0, duration: .6, stagger: .07, ease: "back.out(2.5)", overwrite: true }),
    });
  }
  if (has(".install li")) gsap.to(".install li", { "--fill": 1, stagger: .5, ease: "none", scrollTrigger: { trigger: ".install", start: "top 80%", end: "bottom 55%", scrub: true } });
  if (has(".band .spark")) gsap.fromTo(".band .spark", { "--spin": -90, "--grow": .6 }, {
    "--spin": 0, "--grow": 1, ease: "none", scrollTrigger: { trigger: ".band", start: "top bottom", end: "top 35%", scrub: true },
  });

  // The big download buttons lean toward a mouse pointer.
  mm.add("(pointer: fine) and (min-width: 761px)", () => {
    const off = [...document.querySelectorAll(".hero .btn.primary, .final-box .btn.primary")].map((btn) => {
      const mx = gsap.quickTo(btn, "--mx", { duration: .5, ease: "power3.out" }), my = gsap.quickTo(btn, "--my", { duration: .5, ease: "power3.out" });
      const move = (e) => {
        if (e.pointerType !== "mouse") return;
        const r = btn.getBoundingClientRect();
        mx((e.clientX - r.left - r.width / 2) * .3);
        my((e.clientY - r.top - r.height / 2) * .3);
      };
      const leave = () => { mx(0); my(0); };
      btn.addEventListener("pointermove", move);
      btn.addEventListener("pointerleave", leave);
      return () => { btn.removeEventListener("pointermove", move); btn.removeEventListener("pointerleave", leave); gsap.set(btn, { "--mx": 0, "--my": 0 }); };
    });
    return () => off.forEach((f) => f());
  });

  // The closing frame snaps around the last call to action.
  if (has(".final-box")) gsap.from(".final-box > i", {
    x: (i) => -out(i) * 2.5, y: (i) => -down(i) * 2.5, autoAlpha: 0, duration: .7, stagger: .05, ease: "back.out(1.8)",
    scrollTrigger: { trigger: ".final-box", start: "top 80%", once: true },
  });

  // The privacy band opens from a rounded selection to the full width while it scrolls in.
  if (has(".band")) gsap.fromTo(".band", { clipPath: "inset(0% 3% round 40px)" }, {
    clipPath: "inset(0% 0% round 0px)", ease: "none",
    scrollTrigger: { trigger: ".band", start: "top bottom", end: "top 30%", scrub: true },
  });

  // The hero window leans toward a mouse pointer. Touch, a lost focus or a hidden tab put it back.
  const slides = document.querySelector(".slides");
  if (slides && matchMedia("(pointer: fine)").matches) {
    gsap.set(slides, { transformPerspective: 1600 });
    const rx = gsap.quickTo(slides, "rotationX", { duration: .8, ease: "power3.out" });
    const ry = gsap.quickTo(slides, "rotationY", { duration: .8, ease: "power3.out" });
    const rest = () => { rx(0); ry(0); };
    const hero = document.querySelector(".hero");
    hero.addEventListener("pointermove", (e) => {
      if (e.pointerType !== "mouse") return;
      const r = slides.getBoundingClientRect();
      ry(((e.clientX - r.left) / r.width - .5) * 5);
      rx(-((e.clientY - r.top) / r.height - .5) * 4);
    });
    hero.addEventListener("pointerleave", rest);
    addEventListener("blur", rest);
    document.addEventListener("visibilitychange", rest);
  }

  // Fonts, images and the "show more" lists change the page's height.
  document.fonts?.ready.then(() => { measure(); ScrollTrigger.refresh(); });
  addEventListener("load", () => ScrollTrigger.refresh());
  document.querySelectorAll(".more-feats").forEach((b) => b.addEventListener("click", () => requestAnimationFrame(() => ScrollTrigger.refresh())));

  addEventListener("pagehide", (e) => {
    if (e.persisted) return; // kept for "back": it comes back as it was
    ScrollTrigger.killAll();
    if (lenis) { gsap.ticker.remove(raf); lenis.destroy(); }
  });
})();
