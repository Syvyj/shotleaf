#!/usr/bin/env python3
"""Builds the site from src/page.html: index.html (English) and uk/index.html.
In the template, [[English||Українська]] picks one side per language.
Run: python3 site/build.py"""
import html
import os
import re

# Donation links: fill in when the accounts exist; an empty one shows as "soon".
DONATE = [
    ("Ko-fi", "https://ko-fi.com/", "", "[[Card or PayPal, no fees||Картка чи PayPal, без комісій]]"),
    ("Buy Me a Coffee", "https://buymeacoffee.com/", "", "[[A coffee, any amount||Кава, будь-яка сума]]"),
    ("GitHub Sponsors", "https://github.com/sponsors/", "", "[[Monthly, for developers||Щомісяця, для розробників]]"),
    ("[[Monobank jar||Банка Monobank]]", "https://send.monobank.ua/jar/", "", "[[Ukrainian cards, Apple Pay||Українські картки, Apple Pay]]"),
]

# Where "Download" points. ponytail: a relative zip for now; the 96 MB app is over Cloudflare
# Pages' 25 MB file limit, so it will live wherever we host releases (R2 or the home server).
DOWNLOAD = "https://shotleaf.syvyj.dev/download/Shotleaf.zip"

HERE = os.path.dirname(os.path.abspath(__file__))


def donate_block():
    cards = []
    for name, base, handle, note in DONATE:
        if handle:
            cards.append(f'<a href="{html.escape(base + handle)}" target="_blank" rel="noopener"><b>{name}</b><small>{note}</small></a>')
        else:
            cards.append(f'<span><b>{name}</b><small data-soon="[[soon||скоро]]">{note}</small></span>')
    return '<div class="give">\n        ' + "\n        ".join(cards) + "\n      </div>"


def render(template, lang):
    side = 0 if lang == "en" else 1
    page = template.replace("{{donate}}", donate_block())
    page = re.sub(r"\[\[(.*?)\|\|(.*?)\]\]", lambda m: m.group(1 + side), page, flags=re.S)
    values = {"download": DOWNLOAD, "lang": lang, "root": "" if lang == "en" else "../",
              "other": "uk/" if lang == "en" else "../", "other_lang": "uk" if lang == "en" else "en"}
    page = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], page)
    assert "[[" not in page and "{{" not in page, f"unfilled placeholder in {lang}"
    return page


template = open(os.path.join(HERE, "src/page.html"), encoding="utf-8").read()
for lang, out in [("en", "index.html"), ("uk", "uk/index.html")]:
    path = os.path.join(HERE, out)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(render(template, lang))
    print("wrote", out)
