# Запуск Shotleaf — пости й канали

Чернетки для етапу 7.5 (`PLAN.md`). Правило: один пост на день, після нього день на відповіді.
Чесно про «Open Anyway» і про збір на підпис — це викликає більше довіри, ніж мовчання.

## Перед постами

- [ ] GIF на кожну функцію (редактор, скролінговий знімок, текст з екрана, буфер із множинною вставкою, сніпети, дописування): `scripts/guide-shots.sh` для статики, Screen recording (⌘⇧5) → `ffmpeg -i in.mov -vf "fps=12,scale=1200:-1" -loop 0 out.gif`, до 5 МБ кожен, у `site/assets/launch/`
- [ ] Увімкнути Discussions на GitHub (Settings › General › Features) — на них уже посилаються README і шаблон issue
- [ ] Ko-fi: увімкнути Goal «$99 — Apple developer licence»
- [ ] CI зелений на `main` (бейдж у README)

## Текст (EN) — Show HN / Lobsters / Reddit

**Title:** Show HN: Shotleaf – screenshots, clipboard history, snippets and local text completion for macOS, open source

Hi HN. I'm a solo developer from Ukraine and I built Shotleaf, a menu bar app for the Mac that replaces four tools I was running at once: a screenshot tool, a clipboard manager, a snippet expander and an inline text completion app.

- Screenshots of an area, window or screen, with an editor (arrows, blur, step numbers, backgrounds, watermarks), scrolling screenshots, and text recognition from any image — all on the Mac.
- Clipboard history with search, pinned items and "paste several at once".
- Snippets: type an abbreviation anywhere and it expands, with dates, questions and pictures.
- Inline text completion in any app, from a small model (Gemma 4 E2B) that runs locally through MLX. Grey ghost text, Tab accepts a word. Nothing leaves the Mac; it never runs in password fields, under secure input, or in apps you exclude.

Native Swift/SwiftUI, macOS 15+, Apple silicon. No account, no analytics, no network calls except downloading the model and checking GitHub for updates. GPL-3.0.

Two honest caveats: there's no Apple Developer ID yet ($99/year I don't have), so the first launch needs "Open Anyway" in System Settings. Donations currently go towards exactly that. And the completion model is 3.6 GB and optional; everything else works without it.

I'd love to hear which of the four parts you'd actually use, and what's missing. Site: https://shotleaf.syvyj.dev · Code: https://github.com/Syvyj/shotleaf

## Текст (UK) — DOU / Telegram / Threads

Зробив Shotleaf — безкоштовний застосунок для Mac з відкритим кодом, який замінює чотири програми в меню-барі: скріншоти, історію буфера, сніпети й дописування тексту.

- Скріншоти області, вікна чи екрана з редактором (стрілки, розмиття, номерки, фони, водяні знаки), довгі скріншоти, текст з будь-якої картинки — усе на вашому Mac.
- Історія буфера з пошуком, закріпленням і вставкою кількох записів підряд.
- Сніпети: абревіатура розгортається в будь-якій програмі, з датами, питаннями й картинками.
- Дописування тексту в будь-якій програмі від маленької локальної моделі (Gemma 4 E2B через MLX). Сіра підказка, Tab приймає слово. Нічого не йде в інтернет; у полях паролів, під час захищеного вводу й у виключених програмах не працює.

Swift/SwiftUI, macOS 15+, Apple silicon. Без акаунта, без аналітики. GPL-3.0.

Чесно: ліцензії розробника Apple ($99 на рік) у мене поки нема, тому перший запуск потребує «Усе одно відкрити» в Системних налаштуваннях. Донати зараз збираються саме на неї.

Буду вдячний за відповідь: яка з чотирьох частин вам реально потрібна і чого бракує. Сайт: https://shotleaf.syvyj.dev/uk/ · Код: https://github.com/Syvyj/shotleaf

## Куди і коли

| Де | Коли | Примітка |
|---|---|---|
| Show HN | вт–чт, 14:00–16:00 за Києвом (ранок US East) | тільки заголовок + текст вище, без картинок у пості; GIF у першому коментарі |
| r/macapps | будь-який будній день | GIF редактора як картинка поста |
| r/macOS | через день після r/macapps | flair «App» |
| Lobsters | потрібен інвайт; тег `mac` | те саме, що HN |
| Product Hunt | вівторок, 10:00 за Pacific; підготувати за тиждень | 4–6 картинок, GIF, «maker comment» = текст вище |
| DOU (Форум / «Своїм») | будь-який день | UK-текст |
| MacRumors forums › Mac Apps | будь-який | без реклами в тоні, як «зробив, покажу» |
| MacStories Discord / forum | будь-який | |
| Telegram-канали про macOS (UK) | | UK-текст |

## Після двох тижнів

Зібрати з issues, коментарів і Discussions: яку функцію згадують, яку ні; скільки людей спіткнулися на «Open Anyway»; чи згадують дописування. Рішення за `PLAN.md` 7.6.
