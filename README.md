<a name="en"></a>

![Shotleaf — Capture. Create. Keep. Screenshots and clipboard for Mac.](docs/assets/readme-hero.png)

**English** · [Українська ↓](#uk)

# Shotleaf

Capture and annotate screenshots, record the screen, find what you copied, and bring frequently used text back in a few keystrokes. Shotleaf lives in your Mac menu bar. Free and open source, with no account or tracking.

**[Download for Mac](https://github.com/Syvyj/shotleaf/releases/latest/download/Shotleaf.dmg)** · [Website](https://shotleaf.syvyj.dev) · [Guide](https://shotleaf.syvyj.dev/guide/) · [Releases](https://github.com/Syvyj/shotleaf/releases)

macOS 15+ · Apple silicon (M1 or newer) · [GPL-3.0-or-later](LICENSE) · [![CI](https://github.com/Syvyj/shotleaf/actions/workflows/ci.yml/badge.svg)](https://github.com/Syvyj/shotleaf/actions/workflows/ci.yml)

## 01 · Capture and annotate

Capture an area, a window, the screen or a scrolling page. Add arrows, text, shapes, backgrounds and watermarks; blur private information and copy text from images on your Mac. Record an area of the screen as a video or GIF, and trim it. **Copy Smaller** makes a screenshot or a recording fit a chat's size limit (200 KB to 25 MB).

![Shotleaf screenshot editor with annotations](site/assets/guide/editor-en.webp)

## 02 · Find what you copied

Search and pin items in clipboard history, find screenshots and paste several items at once.

![Shotleaf clipboard history](site/assets/guide/clipboard-en.webp)

## 03 · Let snippets do the typing

Expand abbreviations into reusable text with dates, questions and pictures.

![Shotleaf snippets](site/assets/guide/snippets-en.webp)

## Requirements

macOS 15 or later on Apple silicon (M1 or newer).

## Install

1. Download `Shotleaf.dmg` from [Releases](https://github.com/Syvyj/shotleaf/releases/latest), open it and drag **Shotleaf** onto **Applications**.
2. Open it. Shotleaf isn't notarised by Apple, so the first time macOS says it can't check the app. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
3. The setup guide asks for two permissions:
   - **Screen Recording**: screenshots and text from the screen.
   - **Accessibility**: snippets and pasting from the clipboard history.

   Shotleaf restarts by itself after each one is turned on. Until both are on, the setup guide opens at every launch.

### Updates

When a new version is out, **Update to Shotleaf…** appears at the top of the menu. Shotleaf downloads it, checks that the release is signed with Shotleaf's update key, that the download matches it and that the app inside is signed like the one you have, and restarts into it, with your settings and permissions. It looks for a new version at launch and once a day (turn that off in **Settings › General**). Versions before 0.1.3 can't do this yet: update those once by hand from [Releases](https://github.com/Syvyj/shotleaf/releases/latest), quitting Shotleaf first.

### After an update

macOS may stop trusting the new copy with its permissions even though the switches still look on. If screenshots or pasting stop working, open **System Settings › Privacy & Security**, remove Shotleaf with **–** from **Screen Recording** and **Accessibility**, and allow it again.

## Shortcuts

| | |
|---|---|
| Screenshot | ⌘⇧2 |
| Scrolling screenshot | ⌘⇧3 |
| Text from the screen | ⌘⇧1 |
| Record screen | ⌘⇧6 |
| Clipboard history | ⇧⌘V |
| Snippets | ⇧⌘B |
| Edit the last screenshot | ⌃⌥⌘E |
| Edit an image from the clipboard | ⌃⌥⌘V |

⌘⇧3 is also the macOS full-screen screenshot and ⌘⇧6 is the Touch Bar screenshot, and some apps use ⇧⌘V or ⇧⌘B. Change any of them in **Settings › Shortcuts**.

A shortcut doesn't fire? Another app may be using it. If your keyboard goes through a keyboard-sharing app (Deskflow, Synergy, Barrier), it sends symbols rather than keys, so shortcuts with digits can depend on the keyboard layout on each computer; a shortcut with a letter works in any layout.

## Privacy

Shotleaf has no account and no analytics. Text recognition, blurring private info and screen recording (with trimming and compression) run on your Mac. It goes online for two things only:

- **The check for a new version**: at launch and once a day Shotleaf asks GitHub which release is the newest. Nothing about you is sent. Turn it off in **Settings › General**.
- **Screenshot links**, when you press the link button: the picture goes to Shotleaf's link service on Cloudflare (`s.syvyj.dev`, code in `server/links`) and is deleted when the link expires (within 15 minutes of it), 12 hours at most. A picture over 5 MB goes as a JPEG that fits. You can use your own server instead (`server/shots`). **Check** in Settings › Screenshot Links sends a 1-pixel picture the same way.

Passwords copied from password managers aren't kept in the history. Card numbers and access tokens stay in memory for a minute and never reach the disk, unless you pin them.

## Where your data lives

| | |
|---|---|
| Clipboard history, snippets, recent screenshots | `~/Library/Application Support/Shotleaf` |
| Settings | `~/Library/Preferences/dev.syvyj.shotleaf.plist` |
| Saved screenshots | the folder chosen in Settings (Desktop by default) |

### Uninstall

Quit Shotleaf, then delete the app and the folders above:

```bash
rm -rf /Applications/Shotleaf.app ~/Library/Application\ Support/Shotleaf
defaults delete dev.syvyj.shotleaf
```

## Reporting a problem

Open an [issue](https://github.com/Syvyj/shotleaf/issues) or write to shotleaf@syvyj.dev. If Shotleaf crashed, attach the newest `Shotleaf-*.ips` file from `~/Library/Logs/DiagnosticReports`.

## Building from source

Needs Xcode 26 or later.

```bash
scripts/make-signing-cert.sh   # once: a local certificate, so permissions survive rebuilds
scripts/run.sh                 # build, install to ~/Applications and start
```

Tests: `cd ShotleafKit && swift test`.

The code is in the `ShotleafKit` Swift package (`Core`, `CaptureKit`, `PerceptionKit`, `SettingsKit`, `AppFeature`); `App/` is the thin app target. Design decisions are in `ARCHITECTURE_DECISIONS.md`.

## Questions, bugs, ideas

Bugs and ideas go to [Issues](https://github.com/Syvyj/shotleaf/issues/new/choose) (**Report a Problem…** in the menu fills in the versions); questions to [Discussions](https://github.com/Syvyj/shotleaf/discussions).

## More from the author

[![Likhtar Home](https://raw.githubusercontent.com/Syvyj/Syvyj/main/assets/likhtar-home-card.png)](https://likhtar.syvyj.dev)

**Likhtar Home.** A calm home screen for Android TV and Google TV: films first, no ads. [Website](https://likhtar.syvyj.dev) · [GitHub](https://github.com/Syvyj/likhtar-home)

[![Dropyk](https://raw.githubusercontent.com/Syvyj/Syvyj/main/assets/dropyk-card.png)](https://dropyk.syvyj.dev)

**Dropyk.** Files and links from your phone to the TV in one scan. And [Quick Share on a Mac](https://github.com/Syvyj/dropyk-mac). [Website](https://dropyk.syvyj.dev) · [GitHub](https://github.com/Syvyj/dropyk-android)

## Support

Donations support my time on Shotleaf and my other apps: [support the author](https://shotleaf.syvyj.dev/#support).

## Licence

[GPL-3.0-or-later](LICENSE). © 2026 Oleksii Ziuzin (Syvyj). Shotleaf uses no third-party libraries, only Apple's frameworks.

---

<a name="uk"></a>

![Shotleaf — скріншоти та історія буфера для Mac.](docs/assets/readme-hero.png)

[↑ English](#en) · **Українська**

# Shotleaf

Робіть і редагуйте скріншоти, записуйте екран, знаходьте скопійоване й повертайте потрібний текст кількома натисканнями. Shotleaf живе в рядку меню Mac. Безкоштовний і з відкритим кодом, без акаунта й стеження.

**[Завантажити для Mac](https://github.com/Syvyj/shotleaf/releases/latest/download/Shotleaf.dmg)** · [Сайт](https://shotleaf.syvyj.dev/uk/) · [Посібник](https://shotleaf.syvyj.dev/uk/guide/) · [Релізи](https://github.com/Syvyj/shotleaf/releases)

macOS 15+ · Apple silicon (M1 або новіший) · [GPL-3.0-or-later](LICENSE)

## 01 · Знімайте й редагуйте

Знімайте область, вікно, екран або довгу сторінку. Додавайте стрілки, текст, фігури, фони й водяні знаки; розмивайте приватні дані та копіюйте текст із зображень на Mac. Записуйте область екрана як відео чи GIF і обрізайте її. **Копіювати меншим** робить скріншот чи запис таким, що вміщується в ліміт чату (від 200 КБ до 25 МБ).

![Редактор скріншотів Shotleaf із позначками](site/assets/guide/editor-uk.webp)

## 02 · Знаходьте скопійоване

Шукайте й закріплюйте записи в історії буфера, знаходьте скріншоти та вставляйте кілька записів разом.

![Історія буфера обміну Shotleaf](site/assets/guide/clipboard-uk.webp)

## 03 · Доручіть повторення сніпетам

Розгортайте скорочення в готовий текст із датами, запитаннями й картинками.

![Сніпети Shotleaf](site/assets/guide/snippets-uk.webp)

## Вимоги

macOS 15 або новіша на Apple silicon (M1 чи новіший).

## Встановлення

1. Завантажте `Shotleaf.dmg` з [Releases](https://github.com/Syvyj/shotleaf/releases/latest), відкрийте його й перетягніть **Shotleaf** на **Програми**.
2. Відкрийте Shotleaf. Він поки не нотаризований Apple, тож першого разу macOS скаже, що не може перевірити програму. Відкрийте **Системні параметри › Приватність і безпека**, прогорніть униз і натисніть **Усе одно відкрити**.
3. Посібник із налаштування попросить два дозволи:
   - **Запис екрана**: скріншоти й розпізнавання тексту.
   - **Універсальний доступ**: сніпети й вставка з історії буфера.

   Після кожного дозволу Shotleaf перезапускається сам. Поки обидва не ввімкнені, посібник відкривається при кожному запуску.

### Оновлення

Коли виходить нова версія, угорі меню з’являється **Оновити до Shotleaf…**. Shotleaf завантажує її, перевіряє, що реліз підписаний ключем оновлень Shotleaf, що завантаження йому відповідає і що застосунок усередині підписаний так само, як ваш, і перезапускається вже в ній, з усіма налаштуваннями й дозволами. Нову версію він шукає під час запуску й раз на день (вимкнути можна в **Налаштуваннях › Загальні**). Версії до 0.1.3 так ще не вміють: їх один раз оновіть вручну з [Releases](https://github.com/Syvyj/shotleaf/releases/latest), спершу закривши Shotleaf.

### Після оновлення

macOS може перестати довіряти новій версії дозволи, хоча перемикачі виглядають увімкненими. Якщо скріншоти чи вставка перестали працювати, відкрийте **Системні параметри › Приватність і безпека**, приберіть Shotleaf кнопкою **–** із **Запису екрана** й **Універсального доступу** та дозвольте знову.

## Гарячі клавіші

| | |
|---|---|
| Скріншот | ⌘⇧2 |
| Довгий скріншот | ⌘⇧3 |
| Текст зі скріншоту | ⌘⇧1 |
| Запис екрана | ⌘⇧6 |
| Історія буфера | ⇧⌘V |
| Сніпети | ⇧⌘B |
| Редагувати останній знімок | ⌃⌥⌘E |
| Редагувати картинку з буфера | ⌃⌥⌘V |

⌘⇧3 у macOS ще й знімок усього екрана а ⌘⇧6 — знімок Touch Bar, а деякі програми використовують ⇧⌘V чи ⇧⌘B. Будь-яку клавішу можна змінити в **Налаштуваннях › Гарячі клавіші**.

Клавіша не спрацьовує? Можливо, її зайняла інша програма. Якщо клавіатура працює через програму для спільної клавіатури (Deskflow, Synergy, Barrier), вона передає символи, а не клавіші, тож комбінації з цифрами можуть залежати від розкладки на кожному комп'ютері; комбінація з літерою працює в будь-якій розкладці.

## Приватність

У Shotleaf немає облікового запису й аналітики. Розпізнавання тексту, розмиття приватного і запис екрана (з обрізанням і стисканням) працюють на вашому Mac. У мережу він ходить лише по дві речі:

- **Перевірка нової версії**: під час запуску й раз на день Shotleaf питає в GitHub, який реліз найновіший. Нічого про вас не надсилається. Вимкнути можна в **Налаштуваннях › Загальні**.
- **Посилання на скріншоти**, коли ви натискаєте кнопку посилання: картинка йде в сервіс посилань Shotleaf на Cloudflare (`s.syvyj.dev`, код у `server/links`) і видаляється, коли посилання спливає (протягом 15 хвилин після цього), щонайбільше за 12 годин. Картинка понад 5 МБ іде як JPEG, що вміщується в ліміт. Замість нього можна підключити власний сервер (`server/shots`). Кнопка **Перевірити** в Налаштуваннях › Посилання на скріншоти так само надсилає картинку в 1 піксель.

Паролі, скопійовані з менеджерів паролів, в історії не зберігаються. Номери карток і токени доступу живуть у пам'яті хвилину й не потрапляють на диск, якщо ви їх не закріпите.

## Де лежать ваші дані

| | |
|---|---|
| Історія буфера, сніпети, останні скріншоти | `~/Library/Application Support/Shotleaf` |
| Налаштування | `~/Library/Preferences/dev.syvyj.shotleaf.plist` |
| Збережені скріншоти | тека з Налаштувань (спершу Робочий стіл) |

### Видалення

Закрийте Shotleaf, потім видаліть програму й теки вище:

```bash
rm -rf /Applications/Shotleaf.app ~/Library/Application\ Support/Shotleaf
defaults delete dev.syvyj.shotleaf
```

## Якщо щось не так

Створіть [issue](https://github.com/Syvyj/shotleaf/issues) або напишіть на shotleaf@syvyj.dev. Якщо Shotleaf упав, додайте найновіший файл `Shotleaf-*.ips` з `~/Library/Logs/DiagnosticReports`.

## Збірка з коду

Потрібен Xcode 26 або новіший.

```bash
scripts/make-signing-cert.sh   # один раз: локальний сертифікат, щоб дозволи переживали перезбірку
scripts/run.sh                 # зібрати, встановити в ~/Applications і запустити
```

Тести: `cd ShotleafKit && swift test`.

Код у Swift-пакеті `ShotleafKit` (`Core`, `CaptureKit`, `PerceptionKit`, `SettingsKit`, `AppFeature`); `App/` лише тонка обгортка застосунку. Рішення щодо архітектури в `ARCHITECTURE_DECISIONS.md`.

## Питання, помилки, ідеї

Помилки та ідеї — в [Issues](https://github.com/Syvyj/shotleaf/issues/new/choose) («Повідомити про проблему…» в меню сам підставить версії), питання — у [Discussions](https://github.com/Syvyj/shotleaf/discussions).

## Від того ж автора

[![Likhtar Home](https://raw.githubusercontent.com/Syvyj/Syvyj/main/assets/likhtar-home-card.png)](https://likhtar.syvyj.dev/uk/)

**Likhtar Home.** Спокійний домашній екран для Android TV і Google TV: спершу фільми, без реклами. [Сайт](https://likhtar.syvyj.dev/uk/) · [GitHub](https://github.com/Syvyj/likhtar-home)

[![Dropyk](https://raw.githubusercontent.com/Syvyj/Syvyj/main/assets/dropyk-card.png)](https://dropyk.syvyj.dev/uk/)

**Dropyk.** Файли й посилання з телефона на телевізор одним скануванням. І [Quick Share на Mac](https://github.com/Syvyj/dropyk-mac). [Сайт](https://dropyk.syvyj.dev/uk/) · [GitHub](https://github.com/Syvyj/dropyk-android)

## Підтримка

Донати підтримують мою роботу над Shotleaf та іншими застосунками: [підтримати автора](https://shotleaf.syvyj.dev/uk/#support).

## Ліцензія

[GPL-3.0-or-later](LICENSE). © 2026 Oleksii Ziuzin (Syvyj). Shotleaf не використовує сторонніх бібліотек, лише фреймворки Apple.
