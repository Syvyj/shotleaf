// The page's motion: the hero is "captured" (words rise, the frame snaps around
// the first word), headings reveal word by word, the privacy band opens like a
// selection, and Lenis smooths the scroll. Everything is an extra: without JS,
// with reduced motion or if a library didn't load, the page is already complete.
(() => {
  const root = document.documentElement;
  const done = () => root.classList.add("ready");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce || !window.gsap || !window.ScrollTrigger) return done();

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

  // Hero: navigation, the text under the heading and the buttons never wait for the intro.
  const out = (i) => (i % 2 ? 1 : -1) * 16, down = (i) => (i < 2 ? -1 : 1) * 16;
  gsap.timeline({ defaults: { ease: "power3.out" } })
    .from(".hero h1 .w:not(.el) .wi", { yPercent: 105, duration: .8, stagger: .045 }, .05)
    .from(".hero h1 .w.el .wi", { yPercent: 40, autoAlpha: 0, duration: .7 }, .05)
    .from(".hero .frame > i", { x: out, y: down, autoAlpha: 0, duration: .55, stagger: .05, ease: "back.out(2.2)" }, .45)
    .from(".hero .frame .dim", { autoAlpha: 0, duration: .35, onStart: measure }, .8)
    .from(".hero .icon", { y: 30, rotation: -8, autoAlpha: 0, duration: 1 }, .1)
    .from(".slides", { y: 70, autoAlpha: 0, duration: 1.1 }, .3)
    .from(".tabs .tab", { y: 26, autoAlpha: 0, duration: .6, stagger: .06, clearProps: "transform,opacity,visibility" }, .55);
  done();
  addEventListener("resize", measure);

  // Section headings, word by word as they arrive.
  document.querySelectorAll("main h2[data-split]").forEach((h) => {
    gsap.from(h.querySelectorAll(".wi"), {
      yPercent: 105, duration: .8, stagger: .04, ease: "power3.out",
      scrollTrigger: { trigger: h, start: "top 88%", once: true },
    });
  });

  // Then the copy and the windows under them.
  const rise = ".head > p, .tool .about, .tool .stagebox, .feats .feat, .facts li, .install li, .give a, .final-box > p, .final-box .btn";
  gsap.set(rise, { y: 34, autoAlpha: 0 });
  ScrollTrigger.batch(rise, {
    start: "top 90%", once: true,
    onEnter: (els) => gsap.to(els, { y: 0, autoAlpha: 1, duration: .75, stagger: .07, ease: "power3.out", overwrite: true, clearProps: "transform,opacity,visibility" }),
  });

  // The closing frame snaps around the last call to action.
  gsap.from(".final-box > i", {
    x: (i) => -out(i) * 2.5, y: (i) => -down(i) * 2.5, autoAlpha: 0, duration: .7, stagger: .05, ease: "back.out(1.8)",
    scrollTrigger: { trigger: ".final-box", start: "top 80%", once: true },
  });

  // The privacy band opens from a rounded selection to the full width while it scrolls in.
  gsap.fromTo(".band", { clipPath: "inset(0% 3% round 40px)" }, {
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
