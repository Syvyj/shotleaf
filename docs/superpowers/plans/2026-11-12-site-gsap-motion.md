# Site Motion (GSAP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Shotleaf site (shotleaf.syvyj.dev) feel smooth and alive: blocks hand over to each other with motion, the tool switcher and the screenshot picker react to the visitor, and small details (progress, numbers, steps, buttons) respond to scroll and pointer — all with GSAP, without changing the design.

**Architecture:** Everything goes into the existing `site/motion.js` (scroll and pointer motion) plus small hooks in `site/mocks.js` (the tab switcher lives there) and `site/style.css`. The motif is the app's own capture frame: lime corner brackets (`.fc`) that snap around whatever is selected. Every effect is additive: without JS, with reduced motion, or when a library failed to load, the page stays complete and static.

**Tech Stack:** GSAP 3.13.0 + ScrollTrigger + Lenis 1.3, already vendored in `site/vendor/` and served from the site. Plain JS, no build step for JS; HTML from `site/src/*.html` via `python3 site/build.py`.

**Spec:** The owner's request (2026-11-12): "animate the site we made: pleasant and beautiful, all blocks transition nicely, some interactivity for the visitor; use GSAP." Current motion to build on: `site/motion.js` (hero intro, word-by-word headings, rise-in batches, privacy band clip, hero window tilt, Lenis).

## Global Constraints

- No new dependencies and no CDN: only the vendored `gsap.min.js`, `ScrollTrigger.min.js`, `lenis.min.js`. No GSAP plugin is needed (no SplitText/Flip: the existing word split and plain tweens cover it).
- Never edit generated pages (`site/index.html`, `site/uk/**`, `site/guide/index.html`, `site/privacy/index.html`, `site/404.html`). Edit `site/src/*.html`, then run `python3 site/build.py`.
- Every visible string goes in both languages as `[[English||Українська]]`.
- Hidden-before-animation states are set only from JS after the GSAP path is taken (the `html.gs` class from Task 1). CSS must not hide anything on its own.
- `motion.js` also runs on the guide page: every block is guarded with the existing `has(selector)` helper or an element check.
- Animate `transform`, `opacity`, `clip-path` and CSS custom properties only. The one exception is the picker mock's own `.sel` box in Task 4.
- Pointer effects (picker drag, magnetic buttons, existing tilt) only under `(pointer: fine)`. Scroll parallax and magnet only at `(min-width: 761px)` (the site's phone breakpoint is `max-width: 760px`).
- House motion values: entrances `power3.out`, 0.6–1 s; corner snaps `back.out(2)`–`back.out(3)`; scrubs `ease: "none"`.
- Commit messages follow the repo: one plain sentence starting with `Site: `, ending with the `Co-Authored-By` line. Work on a branch `site/motion`, not `main`.

## Review Focus

1. **Reduced motion / `?still`:** the page is fully visible and static, mocks show their finished state, no `.gs` class, no tab frame. → Task 1 check, re-run in Task 7.
2. **Rapid tab clicks while a transition runs:** exactly one slide ends up visible, the corner frame sits on the last tab clicked. → Task 2 check.
3. **Window resize after load:** the tab frame realigns to the current tab. → Task 2 check.
4. **Phone width (375 px):** no horizontal page scroll from parallax or clip-paths; parallax and magnet are off. → Task 3 check, re-run in Task 7.
5. **Picker drag edge cases:** a click without a drag, Escape mid-drag, or a release outside the mock leaves no stuck `.live` state and the demo loop resumes. → Task 4 checks.

---

## How to verify (all tasks)

The dev server is `.claude/launch.json` → `site` (`python3 -m http.server 8766 --directory site`). Open it with `preview_start {name: "site"}`, reload after each build, run the JS checks with the browser `javascript_tool`, and finish each task with a screenshot. To jump without smooth scroll: `scrollTo({ top: <y>, behavior: "instant" })`, then wait ~1.5 s.

---

### Task 1: Motion switch, scroll progress, condensed nav

**Files:**
- Modify: `site/motion.js:7` (the `reduce` line) and after the early return at `:19`
- Modify: `site/mocks.js:4` (the `reduce` line)
- Modify: `site/src/page.html` and `site/src/guide.html` (inside `.nav .bar-in`, last child)
- Modify: `site/style.css` (nav block near `:88`)

**Interfaces:**
- Produces: `html.gs` class = "GSAP drives motion" (later tasks scope CSS with `.gs`); URL `?still` forces the reduced-motion path; `.nav.scrolled` class.

- [ ] **Step 1: Write the checks** (they fail now)

On `http://localhost:8766/?still`:
```js
[document.documentElement.classList.contains("gs"),
 document.querySelector(".nav .progress") && getComputedStyle(document.querySelector(".nav .progress")).display,
 getComputedStyle(document.querySelector(".hero h1")).visibility,
 document.querySelector(".m-type .typed").textContent.length > 20]
// expect [false, "none", "visible", true]
```
On `http://localhost:8766/`, after `scrollTo({top: 1e6, behavior: "instant"})` and 1.5 s:
```js
[new DOMMatrix(getComputedStyle(document.querySelector(".nav .progress")).transform).a > .99,
 document.querySelector(".nav").classList.contains("scrolled")]
// expect [true, true]
```

- [ ] **Step 2: Run them** — expect the first to fail (`null` progress, and `?still` not honoured: typed text animating).

- [ ] **Step 3: Implement**
  - In both `motion.js` and `mocks.js`: `reduce = matchMedia("(prefers-reduced-motion: reduce)").matches || new URLSearchParams(location.search).has("still")` with `// ponytail: ?still is a manual switch to see the reduced-motion page`.
  - `motion.js`: right after the `if (reduce || !window.gsap ...) return done();` line, `root.classList.add("gs")`.
  - Both templates: `<i class="progress" aria-hidden="true"></i>` as the last child of `.bar-in`.
  - CSS: `.nav .bar-in` gets `position: relative` and `transition: background .3s, box-shadow .3s`. `.nav .progress { display: none }`; `.gs .nav .progress { display: block; position: absolute; left: 14px; right: 14px; bottom: -1px; height: 2px; border-radius: 2px; background: linear-gradient(90deg, var(--leaf), var(--lime)); transform: scaleX(0); transform-origin: 0 50%; }`. `.nav.scrolled .bar-in { background: rgba(250, 251, 246, .92); box-shadow: 0 14px 34px -18px rgba(30, 50, 20, .5); }`.
  - `motion.js`: progress tween `scaleX: 1`, `ease: "none"`, ScrollTrigger `{ start: 0, end: "max", scrub: .3 }`; `ScrollTrigger.create({ start: 80, end: "max", toggleClass: { targets: ".nav", className: "scrolled" } })`.

- [ ] **Step 4: Build and re-run the checks** — `python3 site/build.py` (prints `wrote …` lines, no assertion), reload, both checks match.

- [ ] **Step 5: Commit**
```bash
git add site/motion.js site/mocks.js site/style.css site/src/page.html site/src/guide.html site/index.html site/uk site/guide site/privacy site/404.html
git commit -m "Site: a reading-progress line in the nav, the nav firms up once you scroll, ?still shows the page without motion"
```

---

### Task 2: Tab switcher — a capture frame that moves between tabs, slides that open like a selection

**Files:**
- Modify: `site/mocks.js:91-98` (`show`)
- Modify: `site/motion.js` (new block **before** the hero timeline at `:69`, plus one line in that timeline)
- Modify: `site/style.css` (tabs block near `:122-138`)

**Interfaces:**
- Consumes: `html.gs` (Task 1).
- Produces: `.tabs` dispatches `CustomEvent("tab", { detail: { from: number, to: number } })` on every `show()`; `.tab-sel` element (motion.js-created) inside `.tabs`.

- [ ] **Step 1: Write the checks**

Rapid clicks, then 1.5 s:
```js
const t = [...document.querySelectorAll(".tab")];
t[1].click(); setTimeout(() => t[2].click(), 80); setTimeout(() => t[3].click(), 160);
```
```js
const t = [...document.querySelectorAll(".tab")], s = document.querySelector(".tab-sel").getBoundingClientRect(), r = t[3].getBoundingClientRect();
[Math.round(s.left - r.left), Math.round(s.width - r.width),
 [...document.querySelectorAll(".slide")].map((x) => +getComputedStyle(x).opacity)]
// expect [-6, 12, [0, 0, 0, 1, 0]]
```
Then `resize_window {width: 1100, height: 800}`, wait 0.5 s, the second snippet again → same first two numbers. Reset with `resize_window {preset: "desktop"}`.

- [ ] **Step 2: Run them** — expect `TypeError` (no `.tab-sel`).

- [ ] **Step 3: Implement**
  - `mocks.js` `show(i)`: remember `from = current` before updating; at the end `box.dispatchEvent(new CustomEvent("tab", { detail: { from, to: i } }))`.
  - CSS: `.tabs { position: relative }`. `.tab-sel { position: absolute; left: 0; top: 0; z-index: 2; pointer-events: none; --c: 14px; --t: 2.5px; }` (corners come from `.fc`). `.gs .slide, .gs .slide.on { transition: none }`.
  - `motion.js`, guarded by `.tabs`: create `<span class="tab-sel fc" aria-hidden="true">` with four `<i>`; append to `.tabs`. `place(tab, duration)` tweens the frame to `x: offsetLeft - 6, y: offsetTop - 6, width: offsetWidth + 12, height: offsetHeight + 12`, `ease: "power3.inOut"`, `overwrite: true`; initial `place(.tab.on, 0)`; `place(…, 0)` again on `resize` and after `document.fonts.ready`.
  - Hero timeline: add `.from(".tabs .tab-sel", { autoAlpha: 0, scale: .9, duration: .5, ease: "back.out(2)" }, .95)`.
  - On `tab` event (ignore `from === to`): `place(tabs[to], .55)`; outgoing slide `autoAlpha 1→0, y: -12, scale: .985, duration: .35, ease: "power2.in"`; incoming slide `fromTo { autoAlpha: 0, y: 24, clipPath: "inset(8% 6% 8% 6% round 28px)" } → { autoAlpha: 1, y: 0, clipPath: "inset(0% 0% 0% 0% round 0px)", duration: .75, delay: .12, ease: "power3.out" }`; both `overwrite: true` and `clearProps: "opacity,visibility,transform,clipPath"` so the `.on` class rules take over at the end; the new tab's `.cap`s press `fromTo { y: 4 } → { y: 0, duration: .45, stagger: .05, ease: "back.out(3)" }`.

- [ ] **Step 4: Build, reload, re-run the checks** — both match; screenshot mid-switch shows the frame travelling.

- [ ] **Step 5: Commit** — `Site: the tool tabs get a moving capture frame, and each window opens like a selection`

---

### Task 3: Block hand-overs — hero eases away, tool windows open as selections, gentle parallax

**Files:**
- Modify: `site/motion.js:94` (`rise` list) and new blocks after it

**Interfaces:**
- Produces: `const mm = gsap.matchMedia()` declared once near the top of the GSAP part of `motion.js` (Task 6 uses it).

- [ ] **Step 1: Write the checks**

After `scrollTo({top: document.querySelector("#clipboard").offsetTop - 200, behavior: "instant"})` and 1.5 s:
```js
const m = document.querySelector("#clipboard .stagebox > .mock");
[getComputedStyle(m).opacity, m.style.clipPath, document.querySelector("#clipboard .stagebox").style.transform.includes("translate")]
// expect ["1", "", true]
```
At `resize_window {preset: "mobile"}`, reload, scroll to the bottom and back to the top:
```js
[document.documentElement.scrollWidth <= innerWidth, document.querySelector("#clipboard .stagebox").style.transform]
// expect [true, ""]
```

- [ ] **Step 2: Run them** — expect the desktop check's last value `false`.

- [ ] **Step 3: Implement**
  - Remove `.tool .stagebox` from the `rise` selector list (it gets its own entrance).
  - Per `.tool`, a timeline with ScrollTrigger `{ trigger: tool, start: "top 72%", once: true }`: the `.about .cap`s `from { y: -18, autoAlpha: 0, duration: .5, stagger: .07, ease: "back.out(2.4)" }` at 0; the `.stagebox > .mock` `fromTo { clipPath: "inset(10% 8% 10% 8% round 28px)", scale: .94, autoAlpha: 0 } → { clipPath: "inset(0% 0% 0% 0% round 0px)", scale: 1, autoAlpha: 1, duration: 1, ease: "power3.out", clearProps: "clipPath,transform,opacity,visibility" }` at .1.
  - `mm.add("(min-width: 761px)", …)`: each `.tool .stagebox` `fromTo { y: 40 } → { y: -40 }`, `ease: "none"`, ScrollTrigger `{ trigger: tool, start: "top bottom", end: "bottom top", scrub: true }`; `.hero-top` `to { y: -60, opacity: .2 }`, `ease: "none"`, ScrollTrigger `{ trigger: ".hero-top", start: "top 10%", end: "bottom top", scrub: true }`.

- [ ] **Step 4: Build not needed (JS only); reload and re-run both checks** — both match; reset with `resize_window {preset: "desktop"}`.

- [ ] **Step 5: Commit** — `Site: tool windows open like a selection as you reach them, drift a little with the scroll, and the hero eases away`

---

### Task 4: Try the picker — drag a real selection on the screenshot mock

**Files:**
- Modify: `site/src/page.html:192` (inside `.m-pick .desk`: one new element)
- Modify: `site/style.css` (picker block near `:329-353`)
- Modify: `site/motion.js` (new function and its call)

**Interfaces:**
- Consumes: `html.gs` (Task 1).
- Produces: `tryPicker(mock: HTMLElement): void` in `motion.js`; `.m-pick.live` class while the visitor's selection is shown.

- [ ] **Step 1: Write the checks**

Scroll to `#screenshots`. Drag and Escape (synthetic; pointerId 1 is Chrome's mouse, so pointer capture accepts it):
```js
const m = document.querySelector(".m-pick"), d = m.querySelector(".desk"), r = d.getBoundingClientRect();
const ev = (type, x, y) => d.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 1, pointerType: "mouse", button: 0, buttons: 1, clientX: r.left + r.width * x, clientY: r.top + r.height * y }));
ev("pointerdown", .2, .2); ev("pointermove", .6, .55);
const s = m.querySelector(".sel"), during = [m.classList.contains("live"), s.style.left, s.style.width, +s.style.getPropertyValue("--pw") > 0];
document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
[during, m.classList.contains("live"), s.getAttribute("style")]
// expect [[true, "20%", "40%", true], false, null]
```
Real drag: `computer left_click_drag` across the desk, screenshot at once (label like `1234 × 567`, white flash); after 3 s:
```js
[document.querySelector(".m-pick").classList.contains("live"), document.querySelector(".m-pick .sel").getAttribute("style")]
// expect [false, null]
```
Plain click on the desk (no drag), then the same snippet → `[false, null]`.

- [ ] **Step 2: Run them** — expect `during` to be `[false, "", "", false]`.

- [ ] **Step 3: Implement**
  - Template: in `.m-pick .desk`, before `.flash`: `<div class="try" aria-hidden="true">[[Drag here to try it||Потягніть тут, щоб спробувати]]</div>`.
  - CSS: `.m-pick .try { display: none }`; under `@media (pointer: fine)`: `.gs .m-pick .try { display: block; position: absolute; right: 3%; top: 4%; font: 600 1.5cqw/1 -apple-system, sans-serif; padding: .9cqw 1.4cqw; border-radius: 99px; background: #1d231b; color: #fff; }` and `.gs .m-pick .desk { cursor: crosshair; user-select: none; }`. `.m-pick.live .sel, .m-pick.live .loupe, .m-pick.live .flash { animation: none }`, `.m-pick.live .sel { opacity: 1 }`, `.m-pick.live .cursor, .m-pick.live .try { display: none }`.
  - `tryPicker(mock)`, called for `.m-pick` under `matchMedia("(pointer: fine)")`: remembers the loupe's original `style` attribute. `pointerdown` (button 0) on `.desk`: `setPointerCapture`, start point in % of the desk, add `.live`, kill a pending fade. `pointermove` while dragging: `.sel` inline `left/top/width/height` in % of the desk (clamped 0–100), `--pw`/`--ph` = the box's CSS-pixel size × `devicePixelRatio`, rounded (the label then reads real screen pixels, like the hero frame); loupe `left/top` follow the pointer. `pointerup`: if the box is under 6 px either way, `reset()`; else a timeline — flash `opacity .6 → 0` (.45 s, `power2.out`), `.sel` `scale 1.03 → 1` (.4 s, `back.out(3)`), `.sel` fades out after 1.4 s, then `reset()`. `pointercancel` and `keydown` Escape (on `document`, only while `.live`) → `reset()`. `reset()`: kill the timeline, remove `.live`, `removeAttribute("style")` on `.sel` and `.flash`, restore the loupe's original `style`.

- [ ] **Step 4: Build, reload, re-run the checks** — all match.

- [ ] **Step 5: Commit** — `Site: drag on the screenshot picker to make your own selection, with its size, the flash, and Escape to cancel`

---

### Task 5: The lower page — counting numbers, popping icons, install steps that light up, the spark turns in

**Files:**
- Modify: `site/src/page.html:351,353` (wrap numbers)
- Modify: `site/style.css` (`.facts`, `.install li::before` near `:244`, `.band .spark` near `:212`)
- Modify: `site/motion.js`

**Interfaces:**
- Consumes: the `rise` batch pattern in `motion.js` (`gsap.set` hidden, `ScrollTrigger.batch` with `once`).
- Produces: `[data-count]` spans; CSS vars `--fill` on `.install li`, `--spin`/`--grow` on `.band .spark`.

- [ ] **Step 1: Write the checks**

After scrolling `#private` into view and 2.5 s:
```js
[...document.querySelectorAll("[data-count]")].map((e) => e.textContent)
// expect ["50", "14", "12"]
```
After `scrollTo({top: 1e6, behavior: "instant"})` and 1.5 s:
```js
[[...document.querySelectorAll(".install li")].map((li) => getComputedStyle(li).getPropertyValue("--fill").trim()),
 getComputedStyle(document.querySelector(".band .spark")).getPropertyValue("--spin").trim()]
// expect [["1", "1", "1"], "0"]
```

- [ ] **Step 2: Run them** — expect `[]` for the first.

- [ ] **Step 3: Implement**
  - Template, both languages: wrap `50`, `14` (line 351) and `12` (line 353) as `<span data-count="N">N</span>`.
  - CSS: `[data-count] { font-variant-numeric: tabular-nums }`. `.install li::before` color becomes `color-mix(in srgb, var(--leaf) calc(var(--fill, 0) * 100%), transparent)` (stroke stays). `.band .spark { rotate: calc(var(--spin, 0) * 1deg); scale: var(--grow, 1); }` — individual properties, so the existing hover `transform` still works.
  - `motion.js`: each `[data-count]` `from { textContent: 0, snap: { textContent: 1 }, duration: 1.4, ease: "power2.out" }`, ScrollTrigger `{ trigger: el, start: "top 90%", once: true }`. `.facts svg`: same set/batch pattern as `rise`, `scale: 0, rotation: -45 → 1, 0`, `duration: .6, stagger: .07, ease: "back.out(2.5)"`. `.install li`: `to { "--fill": 1, stagger: .5, ease: "none" }`, ScrollTrigger `{ trigger: ".install", start: "top 80%", end: "bottom 55%", scrub: true }`. Spark: `fromTo { "--spin": -90, "--grow": .6 } → { "--spin": 0, "--grow": 1, ease: "none" }`, ScrollTrigger `{ trigger: ".band", start: "top bottom", end: "top 35%", scrub: true }`.

- [ ] **Step 4: Build, reload, re-run the checks** — both match; hover a donation card: the spark still grows and turns.

- [ ] **Step 5: Commit** — `Site: the numbers count up, the privacy icons pop in, install steps fill as you read them, the support spark turns in`

---

### Task 6: Magnetic download buttons

**Files:**
- Modify: `site/style.css` (`.btn.primary` near `:96`)
- Modify: `site/motion.js`

**Interfaces:**
- Consumes: `mm` (Task 3).
- Produces: CSS vars `--mx`/`--my` on the two big download buttons.

- [ ] **Step 1: Write the check**

```js
const b = document.querySelector(".hero .btn.primary"), r = b.getBoundingClientRect();
b.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, pointerType: "mouse", clientX: r.right - 2, clientY: r.top + r.height / 2 }));
await new Promise((ok) => setTimeout(ok, 700));
const pulled = parseFloat(getComputedStyle(b).getPropertyValue("--mx"));
b.dispatchEvent(new PointerEvent("pointerleave", { pointerType: "mouse" }));
await new Promise((ok) => setTimeout(ok, 900));
[pulled > 5, Math.abs(parseFloat(getComputedStyle(b).getPropertyValue("--mx")) || 0) < .5]
// expect [true, true]
```

- [ ] **Step 2: Run it** — expect `[false, true]`.

- [ ] **Step 3: Implement**
  - CSS: `.btn.primary { translate: calc(var(--mx, 0) * 1px) calc(var(--my, 0) * 1px); }` (`translate` composes with the existing hover/active `transform`).
  - `motion.js`: `mm.add("(pointer: fine) and (min-width: 761px)", …)` for `.hero .btn.primary, .final-box .btn.primary`: `gsap.quickTo(btn, "--mx" | "--my", { duration: .5, ease: "power3.out" })`; `pointermove` pulls by 0.3 × the pointer's offset from the button centre; `pointerleave` sends both to 0. The `mm.add` callback returns a cleanup that removes both listeners and zeroes the vars.

- [ ] **Step 4: Reload, re-run the check** — matches.

- [ ] **Step 5: Commit** — `Site: the download buttons lean toward the pointer`

---

### Task 7: Whole-site pass

**Files:** none unless a check fails (fix in the owning task's files).

- [ ] **Step 1:** `python3 site/build.py` — only `wrote …` lines.
- [ ] **Step 2:** For `/`, `/uk/`, `/guide/`, `/uk/guide/`, `/privacy/`: load, scroll to the bottom and back, `read_console_messages {onlyErrors: true}` → empty.
- [ ] **Step 3:** Re-run the Task 1 `?still` check on `/` and on `/uk/guide/?still` (`gs` false, headings visible).
- [ ] **Step 4:** `resize_window {preset: "mobile"}`, reload `/` and `/guide/`: `document.documentElement.scrollWidth <= innerWidth` → `true` on both; tap through two tabs: the frame follows inside the sideways strip. Reset with `preset: "desktop"`.
- [ ] **Step 5:** Open `/guide/`, then navigate back: the tabs still switch and the frame still aligns (the page came back from the back/forward cache).
- [ ] **Step 6:** Screenshots of the hero, a tool block mid-reveal, the picker with a drawn selection, and the install steps as proof for the owner.
- [ ] **Step 7: Commit** any fixes — `Site: motion pass checked on every page, phone width and without motion`.
