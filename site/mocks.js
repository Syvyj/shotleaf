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
  if (m.dataset.static) return;
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

// The tool switcher: the tabs under the stage pick the window shown above.
// It moves on by itself (the bar on the tab shows when) until you pick one.
(() => {
  const tabs = [...document.querySelectorAll(".tab")], slides = [...document.querySelectorAll(".slide")];
  if (!tabs.length) return;
  const box = tabs[0].parentElement, every = 9000;
  let current = 0, started = performance.now(), held = false;
  const show = (i) => {
    current = i; started = performance.now();
    tabs.forEach((t, n) => { t.classList.toggle("on", n === i); t.setAttribute("aria-selected", n === i); });
    slides.forEach((s, n) => s.classList.toggle("on", n === i));
  };
  tabs.forEach((t, i) => t.addEventListener("click", () => { held = true; tabs[current].style.setProperty("--p", 0); show(i); }));
  if (reduce) return;
  io.observe(box);
  const tick = (now) => {
    if (!held && box.dataset.vis) {
      const p = (now - started) / every;
      tabs[current].style.setProperty("--p", Math.min(1, p));
      if (p >= 1) { tabs[current].style.setProperty("--p", 0); show((current + 1) % tabs.length); }
    } else if (!box.dataset.vis) started = now - ((parseFloat(tabs[current].style.getPropertyValue("--p")) || 0) * every);
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
})();

// Text completion: a sentence is typed, a grey suggestion appears, Tab takes a word, ⌥Tab the rest.
document.querySelectorAll(".m-type").forEach(async (m) => {
  const typed = m.querySelector(".typed"), ghost = m.querySelector(".ghost"), tab = m.querySelector(".k-tab"), all = m.querySelector(".k-all");
  const text = m.dataset.text, rest = m.dataset.ghost;
  if (reduce) { typed.textContent = text; ghost.textContent = rest; return; }
  const press = async (key) => { key.classList.add("hit"); await sleep(160); key.classList.remove("hit"); };
  for (;;) {
    typed.textContent = ""; ghost.textContent = "";
    await visible(m); await sleep(700);
    for (const ch of text) { typed.textContent += ch; await sleep(ch === " " ? 70 : 45 + Math.random() * 40); }
    await sleep(450);
    ghost.textContent = rest; await sleep(1300);
    const first = rest.match(/^\S+\s?/)[0];
    await press(tab); typed.textContent += first; ghost.textContent = rest.slice(first.length); await sleep(1100);
    await press(all); typed.textContent += ghost.textContent; ghost.textContent = ""; await sleep(3200);
  }
});
