// Plays the mockups while they're on screen. CSS draws the screenshot ones;
// the clipboard and snippet ones are scripted here. With reduced motion,
// every mockup just shows its finished state.
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const visible = async (m) => { while (!m.dataset.vis) await sleep(300); };
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    e.target.dataset.vis = e.isIntersecting ? "1" : "";
    if (!reduce) e.target.classList.toggle("play", e.isIntersecting);
  }
}, { threshold: 0.25 });
document.querySelectorAll(".mock").forEach((m) => io.observe(m));

async function clipboard(m) {
  const q = m.dataset.q, query = m.querySelector(".q"), ph = m.querySelector(".ph");
  const rows = [...m.querySelectorAll(".row")], prev = m.querySelector(".prev .p"), meta = m.querySelector(".pm");
  const paste = m.querySelector(".b.go"), win = m.querySelector(".win"), dest = m.querySelector(".dest .d");
  const pick = (row) => {
    rows.forEach((r) => r.classList.toggle("sel", r === row));
    prev.textContent = row.dataset.text;
    meta.textContent = `${row.querySelector(".w").textContent} · ${row.dataset.text.length} ${m.dataset.chars}`;
  };
  const filter = (s) => {
    let first, n = 0;
    rows.forEach((r) => {
      const text = r.dataset.text, at = text.toLowerCase().indexOf(s);
      r.classList.toggle("gone", at < 0);
      if (at >= 0 && !r.querySelector(".t span")) {
        r.querySelector(".t").innerHTML = s ? esc(text.slice(0, at)) + "<mark>" + esc(text.slice(at, at + s.length)) + "</mark>" + esc(text.slice(at + s.length)) : esc(text);
      }
      if (at >= 0 && !first) first = r;
      if (at >= 0) r.querySelector(".k").textContent = ++n;
    });
    if (first) pick(first);
  };
  const reset = () => {
    query.textContent = ""; ph.hidden = false; filter(""); win.classList.remove("hide"); dest.textContent = "";
  };
  if (reduce) { ph.hidden = true; query.textContent = q; filter(q); dest.textContent = rows[0].dataset.text; return; }
  for (;;) {
    reset();
    await visible(m); await sleep(1400);
    ph.hidden = true;
    for (const ch of q) { query.textContent += ch; filter(query.textContent); await sleep(280); }
    await sleep(1100);
    paste.classList.add("hit"); await sleep(170); paste.classList.remove("hit");
    win.classList.add("hide"); await sleep(380);
    dest.textContent = m.querySelector(".row.sel").dataset.text;
    await sleep(3400);
  }
}

async function snippet(m) {
  const body = m.querySelector(".body"), ask = m.querySelector(".ask"), answer = m.querySelector(".ans");
  const date = new Date(Date.now() + 2 * 864e5).toLocaleDateString(document.documentElement.lang, { day: "2-digit", month: "2-digit", year: "numeric" });
  const filled = m.dataset.tpl.replaceAll("\\n", "\n").replace("{name}", m.dataset.answer).replace("{date}", date);
  const [before, after] = filled.split("{cursor}");
  const show = (html) => { body.innerHTML = html + '<span class="caret"></span>'; };
  const done = () => { body.innerHTML = esc(before) + '<span class="caret"></span>' + esc(after); };
  if (reduce) { done(); return; }
  for (;;) {
    show(""); answer.textContent = ""; ask.classList.add("hide");
    await visible(m); await sleep(1200);
    let typed = "";
    for (const ch of m.dataset.abbr) { typed += ch; show('<span class="abbr">' + esc(typed) + "</span>"); await sleep(200); }
    await sleep(450);
    ask.classList.remove("hide"); await sleep(650);
    for (const ch of m.dataset.answer) { answer.textContent += ch; await sleep(130); }
    await sleep(700);
    ask.classList.add("hide"); await sleep(250);
    done();
    await sleep(4200);
  }
}

document.querySelectorAll(".m-clip").forEach(clipboard);
document.querySelectorAll(".m-snip").forEach(snippet);

// Keycaps press themselves, one shortcut after another.
(async () => {
  const keys = [...document.querySelectorAll(".key")];
  if (!keys.length || reduce) return;
  const box = keys[0].parentElement;
  io.observe(box);
  for (let i = 0; ; i = (i + 1) % keys.length) {
    await visible(box);
    const caps = [...keys[i].querySelectorAll(".cap")];
    for (const c of caps) { c.classList.add("down"); await sleep(140); }
    await sleep(650);
    caps.forEach((c) => c.classList.remove("down"));
    await sleep(900);
  }
})();

// The pointer lights the card it's over.
document.querySelectorAll(".cell").forEach((cell) => cell.addEventListener("pointermove", (e) => {
  const r = cell.getBoundingClientRect();
  cell.style.setProperty("--mx", `${e.clientX - r.left}px`); cell.style.setProperty("--my", `${e.clientY - r.top}px`);
}));

// A link counting down to its end.
document.querySelectorAll(".c-link").forEach((card) => {
  const t = card.querySelector(".t"), bar = card.querySelector(".bar2 i"), total = +t.dataset.left;
  let left = total;
  const tick = () => {
    const h = Math.floor(left / 3600), m = Math.floor(left / 60) % 60, s = left % 60;
    t.textContent = `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
    bar.style.transform = `scaleX(${left / total})`;
    left = left > 0 ? left - 1 : total;
  };
  tick(); if (!reduce) setInterval(tick, 1000);
});

// "Try it": drag across the card to take a shot, as in the app. If nobody
// tries for a while, a pointer shows how once.
document.querySelectorAll(".c-pick .field").forEach((field) => {
  const flash = field.querySelector(".flash"), count = field.querySelector(".count");
  let sel = null, start = null, shots = 0, tried = false;
  const at = (e) => { const r = field.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const draw = (a, b) => {
    const box = { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(a.x - b.x), h: Math.abs(a.y - b.y) };
    Object.assign(sel.style, { left: box.x + "px", top: box.y + "px", width: box.w + "px", height: box.h + "px" });
    sel.firstChild.textContent = `${Math.round(box.w * devicePixelRatio)} × ${Math.round(box.h * devicePixelRatio)}`;
    return box;
  };
  const begin = (p) => { sel = document.createElement("div"); sel.className = "sel"; sel.append(document.createElement("span")); field.append(sel); start = p; draw(p, p); };
  const finish = (p) => {
    const box = draw(start, p); sel.remove(); sel = null;
    if (box.w < 16 || box.h < 16) return;
    flash.classList.remove("go"); void flash.offsetWidth; flash.classList.add("go");
    count.innerHTML = `<b>${++shots}</b> ${field.dataset.done}`;
  };
  field.addEventListener("pointerdown", (e) => {
    if (e.pointerType === "touch" || e.button !== 0) return;
    tried = true; field.setPointerCapture(e.pointerId); begin(at(e));
  });
  field.addEventListener("pointermove", (e) => { if (sel && start) draw(start, at(e)); });
  field.addEventListener("pointerup", (e) => { if (sel) finish(at(e)); else if (e.pointerType === "touch") demo(); });

  let demoing = false;
  async function demo() {
    if (demoing || sel) return;
    demoing = true;
    const w = field.offsetWidth, h = field.offsetHeight;
    const a = { x: w * 0.2, y: h * 0.2 }, b = { x: w * 0.78, y: h * 0.62 }, rest = { x: w * 0.9, y: h * 0.9 };
    const pointer = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    pointer.setAttribute("class", "fake"); pointer.setAttribute("viewBox", "0 0 20 28"); pointer.innerHTML = '<use href="#cur"/>';
    field.append(pointer);
    const put = (p) => Object.assign(pointer.style, { left: p.x + "px", top: p.y + "px" });
    const glide = (from, to, ms, each) => new Promise((done) => {
      const t0 = performance.now();
      const step = (now) => {
        const t = Math.min(1, (now - t0) / ms), k = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
        const p = { x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k };
        put(p); each?.(p); t < 1 ? requestAnimationFrame(step) : done();
      };
      requestAnimationFrame(step);
    });
    put(rest); await glide(rest, a, 600);
    begin(a); await glide(a, b, 1100, (p) => draw(start, p));
    await sleep(200); finish(b);
    await glide(b, rest, 500); pointer.remove(); demoing = false;
  }
  if (!reduce) new IntersectionObserver((entries, o) => {
    if (!entries[0].isIntersecting) return;
    o.disconnect(); setTimeout(() => { if (!tried) demo(); }, 1800);
  }, { threshold: 0.7 }).observe(field);
});
