#!/usr/bin/env python3
"""Builds the site from src/: each page in English (at its path) and Ukrainian (under uk/),
plus 404.html and robots.txt. In a template, [[English||Українська]] picks one side per language.
Run: python3 site/build.py"""
import hashlib
import html
import os
import re

SITE = "https://shotleaf.syvyj.dev/"
# Donation links: one without a handle isn't shown.
DONATE = [
    ("Ko-fi", "https://ko-fi.com/", "syvyj", "[[Card or PayPal||Картка чи PayPal]]"),
    ("Buy Me a Coffee", "https://buymeacoffee.com/", "syvyj", "[[A coffee, any amount||Кава, будь-яка сума]]"),
    ("GitHub Sponsors", "https://github.com/sponsors/", "", "[[Monthly, for developers||Щомісяця, для розробників]]"),
    ("[[Monobank jar||Банка Monobank]]", "https://send.monobank.ua/jar/", "5juJPj142b", "[[Card, Apple Pay, Google Pay||Картка, Apple Pay, Google Pay]]"),
]

# Where "Download" points: the newest GitHub release (ADR-0069).
DOWNLOAD = "https://github.com/Syvyj/shotleaf/releases/latest/download/Shotleaf.dmg"

HERE = os.path.dirname(os.path.abspath(__file__))


def donate_block():
    cards = []
    for name, base, handle, note in DONATE:
        if handle:  # no handle yet: not shown
            cards.append(f'<a href="{html.escape(base + handle)}" target="_blank" rel="noopener"><b>{name}</b><small>{note}</small></a>')
    return '<div class="give">\n        ' + "\n        ".join(cards) + "\n      </div>"


def webp_size(path):
    """Width and height of a WebP file (VP8X, VP8L or VP8), from its header."""
    data = open(path, "rb").read(30)
    if data[12:16] == b"VP8X":
        return 1 + int.from_bytes(data[24:27], "little"), 1 + int.from_bytes(data[27:30], "little")
    if data[12:16] == b"VP8L":
        bits = int.from_bytes(data[21:25], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    return int.from_bytes(data[26:28], "little") & 0x3FFF, int.from_bytes(data[28:30], "little") & 0x3FFF


def shots(page, lang, root):
    """<img data-shot="editor"> → that guide picture in this language, with its size (no jump while it loads)."""
    def one(m):
        rel = f"assets/guide/{m.group(1)}-{lang}.webp"
        if not os.path.exists(os.path.join(HERE, rel)):  # shot by hand in one language so far
            rel = f"assets/guide/{m.group(1)}-{'uk' if lang == 'en' else 'en'}.webp"
        w, h = webp_size(os.path.join(HERE, rel))
        return f'src="{root}{rel}" width="{w}" height="{h}" loading="lazy" decoding="async"'
    return re.sub(r'data-shot="([\w-]+)"', one, page)


def render(template, lang, folder=""):
    """`folder` is where the English page lives ("" or "privacy/"); the Ukrainian one is under uk/."""
    side = 0 if lang == "en" else 1
    page = template.replace("{{donate}}", donate_block()).replace("{{icons}}", open(os.path.join(HERE, "src/icons.svg"), encoding="utf-8").read())
    page = re.sub(r"\[\[(.*?)\|\|(.*?)\]\]", lambda m: m.group(1 + side), page, flags=re.S)
    here = folder if lang == "en" else "uk/" + folder
    there = "uk/" + folder if lang == "en" else folder
    root = "../" * here.count("/")
    # A new version of the CSS/JS gets a new URL, so browsers don't keep the old one.
    ver = hashlib.sha1(b"".join(open(os.path.join(HERE, f), "rb").read() for f in ("style.css", "mocks.js", "motion.js"))).hexdigest()[:8]
    values = {"ver": ver, "download": DOWNLOAD, "lang": lang, "root": root, "home": root + ("" if lang == "en" else "uk/"),
              "other": root + there, "other_lang": "uk" if lang == "en" else "en",
              "url": SITE + here, "og": f"{SITE}assets/og-{lang}.png"}
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], page)
    page = shots(page, lang, root)
    assert "[[" not in page and "{{" not in page, f"unfilled placeholder in {lang}"
    return page


def write(out, text):
    path = os.path.join(HERE, out)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
    print("wrote", out)


for name, folder in [("page.html", ""), ("guide.html", "guide/"), ("privacy.html", "privacy/")]:
    template = open(os.path.join(HERE, "src", name), encoding="utf-8").read()
    write(folder + "index.html", render(template, "en", folder))
    write("uk/" + folder + "index.html", render(template, "uk", folder))
# Cloudflare Pages serves 404.html for any missing path, so its links are absolute.
write("404.html", render(open(os.path.join(HERE, "src/404.html"), encoding="utf-8").read(), "en").replace('href="assets', 'href="/assets').replace('href="style', 'href="/style'))
write("robots.txt", f"User-agent: *\nAllow: /\n")
