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
