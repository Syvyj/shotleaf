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
    ("Ko-fi", "https://ko-fi.com/", "", "[[Card or PayPal, no fees||Картка чи PayPal, без комісій]]"),
    ("Buy Me a Coffee", "https://buymeacoffee.com/", "syvyj", "[[A coffee, any amount||Кава, будь-яка сума]]"),
    ("GitHub Sponsors", "https://github.com/sponsors/", "", "[[Monthly, for developers||Щомісяця, для розробників]]"),
    ("[[Monobank jar||Банка Monobank]]", "https://send.monobank.ua/jar/", "5juJPj142b", "[[Card, Apple Pay, Google Pay||Картка, Apple Pay, Google Pay]]"),
]

# Where "Download" points: the newest GitHub release (ADR-0069).
DOWNLOAD = "https://github.com/Syvyj/shotleaf/releases/latest/download/Shotleaf.zip"

HERE = os.path.dirname(os.path.abspath(__file__))


def donate_block():
    cards = []
    for name, base, handle, note in DONATE:
        if handle:  # no handle yet: not shown
            cards.append(f'<a href="{html.escape(base + handle)}" target="_blank" rel="noopener"><b>{name}</b><small>{note}</small></a>')
    return '<div class="give">\n        ' + "\n        ".join(cards) + "\n      </div>"


def render(template, lang, folder=""):
    """`folder` is where the English page lives ("" or "privacy/"); the Ukrainian one is under uk/."""
    side = 0 if lang == "en" else 1
    page = template.replace("{{donate}}", donate_block())
    page = re.sub(r"\[\[(.*?)\|\|(.*?)\]\]", lambda m: m.group(1 + side), page, flags=re.S)
    here = folder if lang == "en" else "uk/" + folder
    there = "uk/" + folder if lang == "en" else folder
    root = "../" * here.count("/")
    # A new version of the CSS/JS gets a new URL, so browsers don't keep the old one.
    ver = hashlib.sha1(b"".join(open(os.path.join(HERE, f), "rb").read() for f in ("style.css", "mocks.js"))).hexdigest()[:8]
    values = {"ver": ver, "download": DOWNLOAD, "lang": lang, "root": root, "home": root + ("" if lang == "en" else "uk/"),
              "other": root + there, "other_lang": "uk" if lang == "en" else "en",
              "url": SITE + here, "og": f"{SITE}assets/og-{lang}.png"}
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], page)
    assert "[[" not in page and "{{" not in page, f"unfilled placeholder in {lang}"
    return page


def write(out, text):
    path = os.path.join(HERE, out)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
    print("wrote", out)


for name, folder in [("page.html", ""), ("privacy.html", "privacy/")]:
    template = open(os.path.join(HERE, "src", name), encoding="utf-8").read()
    write(folder + "index.html", render(template, "en", folder))
    write("uk/" + folder + "index.html", render(template, "uk", folder))
# Cloudflare Pages serves 404.html for any missing path, so its links are absolute.
write("404.html", render(open(os.path.join(HERE, "src/404.html"), encoding="utf-8").read(), "en").replace('href="assets', 'href="/assets').replace('href="style', 'href="/style'))
write("robots.txt", f"User-agent: *\nAllow: /\n")
