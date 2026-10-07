# ARCHITECTURE_DECISIONS.md — APILA

Журнал архітектурних рішень (ADR) для APILA — нативного macOS AI Productivity Suite.
Кожен запис: **що вирішили**, **чому**, **які альтернативи розглядали**.

> Статуси: ✅ ПРИЙНЯТО · 🟡 ЗАПРОПОНОВАНО · ⏳ ОЧІКУЄ ПІДТВЕРДЖЕННЯ · ❌ ВІДХИЛЕНО · ⛔ СКАСОВАНО

> **Поточний стан (2026-10-07).** Працює вертикальний зріз Kerlig-частини: ⌘⇧Space → плаваюча панель → Rewrite/Explain/Translate/Summarize/Custom → стрімінг → Copy/Replace/Insert. Провайдер: LM Studio (:1234) або Mock. CaptureKit/PerceptionKit — заглушки; MLX, скріншоти, inline-дописування — ще не почато. Xcode 26 встановлено: `swift test` і `xcodebuild` працюють. Дорожня карта — `PLAN.md`.

---

## Контекст продукту

Один нативний macOS-застосунок, що об'єднує ідеї Kerlig (глобальний хоткей, floating UI поверх будь-якої програми, AI-дії над виділеним текстом), Shottr (швидкі скріншоти, OCR, анотації — не MVP) та Cotypist (inline completion — не MVP, локальна модель у процесі). Не клон. Одне ядро, один UI, модульна архітектура.

Принципи: SwiftUI · сучасні Apple API · local-first · privacy-first · keyboard-first · plugin-friendly · модульність · мінімум сторонніх залежностей.

---

## ADR-0001 — Модульність через локальні SPM-пакети 🟡
**Рішення.** Кожен модуль (Core, AIKit, ContextKit, CaptureKit, OCRKit, AppUI, SettingsKit) — окремий локальний Swift Package. Тонкий таргет `App` як Composition Root.
**Чому.** Компілятор фізично забороняє доступ до неоголошених залежностей → межі модулів неможливо порушити випадково. Тестопридатність, паралельна збірка, чистий граф залежностей.
**Альтернативи.** Папки в одному таргеті (межі лише за домовленістю, легко порушити). Окремі `.framework` (важчий білд, зайва церемонія).

## ADR-0002 — Фічеві модулі не залежать один від одного 🟡
**Рішення.** Усі фічеві модулі залежать лише від `Core` (контракти). Звʼязує їх тільки шар `App`.
**Чому.** Основа plugin-friendly: нова реалізація протоколу не вимагає правок у сусідніх модулях. Низька звʼязність.
**Альтернативи.** Прямі залежності між модулями (швидше пишеться, але перетворюється на моноліт).

## ADR-0003 — Protocol-oriented + Dependency Injection 🟡
**Рішення.** Усе зовнішнє (AI, контекст, захоплення, OCR, хоткеї) — за протоколами в `Core`. Конкретні реалізації створюються лише в `AppContainer`.
**Чому.** Заміна реалізацій, мокання в тестах, єдине місце композиції.
**Альтернативи.** Синглтони/прямі виклики (швидко, але жорстко звʼязано, погано тестується).

## ADR-0004 — Swift Concurrency + Observation 🟡
**Рішення.** async/await та actors замість колбеків; стрімінг AI через `AsyncStream`. Стан UI — через `@Observable` (Observation framework).
**Чому.** Сучасні Apple API, менше бойлерплейту за Combine, безпека потоків через actors.
**Альтернативи.** Combine (важче, більше церемонії), GCD-колбеки (застаріло).
**Наслідок.** Мінімальна версія macOS 14+ (через `@Observable`). Див. ADR-0011.

## ADR-0005 — Єдиний протокол `AIProvider` + Registry + Capabilities 🟡
**Рішення.** Усі провайдери (Embedded, LM Studio, Ollama, OpenAI-compatible) реалізують `AIProvider`. `AIProviderRegistry` маршрутизує. Кожен провайдер оголошує `ProviderCapabilities` (supportsVision/Audio, maxContextTokens).
**Чому.** Незалежність від одного вендора (вимога), легке додавання провайдерів, адаптація запиту під можливості.
**Альтернативи.** Окремий API на провайдера (не масштабується).

## ADR-0006 — Embedded-движок: MLX Swift, модель Gemma 4 E2B 🟡
**Рішення.** Локальна модель у процесі застосунку через MLX Swift; дефолт — Gemma 4 E2B (мультимодальна, ~2.3B effective, <1.5GB, 128K контекст). Конкретний движок схований за абстракцією `EmbeddedEngine`.
**Чому.** Виконує вимогу «без LM Studio/Ollama/llama.cpp». Нативний для Apple Silicon, ~10-30% швидший за GGUF, multimodal (text+vision+audio).
**Ризик.** Відомі пробіли в лоадерах Gemma 4 у `mlx-swift-lm` (issue #282) → потрібна абстракція, щоб тимчасово підмінити реалізацію.
**Альтернативи.** llama.cpp/GGUF (підтримка Intel, але C++-міст і трохи повільніше). Рішення залежить від цільового заліза — див. ADR-0012.

## ADR-0007 — Мультимодальний `AIRequest` (`[ContentPart]`) з першого дня 🟡
**Рішення.** Запит складається з частин (`.text`, `.image`, `.audio`), а не з рядка. `PromptBuilder` адаптує під capabilities: vision-провайдеру — зображення напряму; текстовому — спершу OCR → текст.
**Чому.** Gemma 4 E2B бачить зображення; подавати скріншот напряму краще за OCR. OCR лишається доповненням (текстові провайдери, функція «copy text from image»).
**Альтернативи.** Текст-онлі запит (втрата ключової переваги моделі, переробка пізніше).

## ADR-0008 — Floating UI через non-activating NSPanel 🟡
**Рішення.** Плаваюча панель — `NSPanel` (non-activating) з SwiftUI-вмістом через хостинг-міст.
**Чому.** Має зʼявлятися поверх будь-якого застосунку, не крадучи фокус (інакше губиться виділення в активній програмі).
**Альтернативи.** Звичайне SwiftUI Window (краде фокус — не годиться).

## ADR-0009 — Меню-бар через MenuBarExtra 🟡
**Рішення.** `MenuBarExtra` (SwiftUI, macOS 13+).
**Чому.** Сучасний нативний API, мінімум коду.
**Альтернативи.** `NSStatusItem` вручну (більше коду, потрібно лише за нестандартного UX).

## ADR-0010 — Виділений текст: Accessibility з fallback на ⌘C 🟡
**Рішення.** Спершу читаємо виділення через AXUIElement; якщо застосунок не віддає — fallback на симуляцію ⌘C з відновленням буфера.
**Чому.** AX чистіший і не псує буфер; fallback покриває застосунки без AX.
**Альтернативи.** Лише clipboard (псує буфер, менше контексту), лише AX (не всюди працює).

## ADR-0011 — Захоплення екрана: ScreenCaptureKit; OCR: Vision 🟡
**Рішення.** Скріншоти через ScreenCaptureKit; розпізнавання тексту on-device через Vision.
**Чому.** Сучасні API, privacy-first (нічого не йде в мережу), якісний OCR з коробки.
**Альтернативи.** `CGWindowListCreateImage` (застаріло), сторонні OCR (зайва залежність, гірша приватність).

---

## ADR-0012 — Цільове залізо: лише Apple Silicon ✅
**Рішення.** Підтримуємо лише Apple Silicon (M1+). Intel не підтримуємо.
**Чому.** Дозволяє MLX Swift як основний embedded-движок без компромісів (нативно, швидко, мультимодально); узгоджується з local-first і простотою кодової бази.
**Альтернативи.** +Intel (ширша аудиторія, але embedded довелося б робити на llama.cpp/GGUF — C++-міст, повільніше, без переваг MLX).
**Наслідок.** Підтверджує MLX у ADR-0006.

## ADR-0013 — Розповсюдження: Developer ID, поза App Store ✅
**Рішення.** Developer ID + нотаризація + hardened runtime; App Sandbox вимкнено.
**Чому.** Accessibility + глобальні хоткеї + screen recording несумісні з повним App Sandbox Mac App Store. Цей шлях дає повний доступ без обрізання ключових функцій.
**Альтернативи.** Mac App Store (ширша дистрибуція, але конфлікт із ключовими функціями), обидва шляхи (дві конфігурації прав — зайве на старті).

## ADR-0014 — Мінімальна версія macOS: 15 (Sequoia) ✅
**Рішення.** Мінімум macOS 15 (Sequoia).
**Чому.** Найновіші API, найменше обхідних шляхів, `@Observable`/ScreenCaptureKit/Vision «з коробки», найчистіший код для нового комерційного продукту.
**Альтернативи.** macOS 14 (трохи ширша аудиторія), macOS 13 (найширша, але без `@Observable`, довелося б Combine/ObservableObject).

---

# Уточнення після рев'ю (Architecture Review Final) ✅

## ADR-0015 — Один Package.swift з багатьма таргетами (уточнює ADR-0001) ✅
**Рішення.** Замість N окремих SPM-пакетів — один `Package.swift` із багатьма таргетами (Core + 7 модулів + executable + тести).
**Чому.** Компілятор однаково забороняє таргету доступ до неоголошених залежностей — гарантія меж та сама, що й у ADR-0001, але без церемонії N пакетів. Окремі пакети потрібні лише для незалежного версіонування/релізу, чого в нас нема.
**Альтернативи.** N окремих пакетів із local path-залежностями (більше ceremony, без додаткової ізоляції). Залишаємо можливість виділити пакет згодом.

## ADR-0016 — ActionKit як окремий модуль ✅
**Рішення.** Усі користувацькі дії (Rewrite, Explain, Translate, Summarize, Reply, Extract, майбутні) — у модулі ActionKit. InferenceKit не знає, що таке «Rewrite»; він отримує готовий `AIRequest`.
**Чому.** Дії розширюються незалежно від AI; додавання дії = новий тип, без змін деінде. Чистий поділ policy (дія) і механізму (виконання).
**Альтернативи.** Логіка дій усередині AI-шару (змішує відповідальності, заважає масштабуванню).

## ADR-0017 — Action-керований PromptBuilder (не God Object) ✅
**Рішення.** Потік `ContextSnapshot → Action → PromptBuilder → AIRequest → Provider`. Action декларує `ContextRequirements` і володіє `PromptTemplate`; PromptBuilder лише підставляє дані й вирішує image-vs-OCR за `ProviderCapabilities`. OCR/збір контексту/стрімінг робить `ActionRunner`.
**Чому.** PromptBuilder лишається маленьким асемблером; знання про сенс дії — в Action. Тестопридатно, без God Object.
**Альтернативи.** PromptBuilder, що знає всі дії (перетворюється на God Object).

## ADR-0018 — OCRKit → PerceptionKit (уточнює ADR-0011) ✅
**Рішення.** Модуль називається **PerceptionKit**, а не VisionKit.
**Чому.** Користувач слушно зауважив, що Vision-фреймворк ширший за OCR (OCR, object detection, barcode, image analysis). Але **`VisionKit` — це наявний фреймворк Apple** (DataScanner, document camera) → колізія імен, як колись `UIKit`. `PerceptionKit` (машинне сприйняття) вільний і семантично точний.
**Альтернативи.** VisionKit (колізія), VisualKit/SightKit (вільні, але менш точні семантично).

## ADR-0019 — AIKit → InferenceKit (уточнює ADR-0005) ✅
**Рішення.** Модуль називається **InferenceKit**.
**Чому.** Відповідатиме не лише за LLM: embeddings, reranking, vision-моделі, Whisper, TTS, local runtime — усе це inference. Назва точніша для довгострокової підтримки.
**Альтернативи.** AIKit (зрозуміло, але вужче за реальний обсяг модуля).

## ADR-0020 — ContextSnapshot: immutable + Sendable ✅
**Рішення.** `struct ContextSnapshot: Sendable` без mutable state; збагачення (напр. OCR) повертає копію (`withRecognizedScreenText`).
**Чому.** Знімок контексту має бути незмінним фактом; безпечно передається між акторами/тасками.
**Альтернативи.** Mutable-модель (гонки, складніша логіка).

## ADR-0021 — Core лишається Foundation-only (governance) ✅
**Рішення.** Core імпортує лише Foundation: жодного AppKit/SwiftUI/MLX/Vision/ScreenCaptureKit. Зображення/аудіо в домені — як байти + метадані (`ImagePayload`/`AudioPayload`), а не платформні типи.
**Принцип.** Нова можливість = новий модуль. Якщо для фічі треба міняти Core або переписувати наявні модулі — спершу пропонуємо рефакторинг архітектури з обґрунтуванням.
**Альтернативи.** Дозволити платформні типи в Core (зручніше зараз, але протікання залежностей і втрата чистоти контрактів).

## ADR-0022 — Тести на Swift Testing ✅
**Оновлення (2026-10-07).** Повний Xcode тепер є — `swift test --package-path APILAKit` виконується локально; примітка про CLT нижче застаріла.
**Рішення.** Юніт-тести на Swift Testing (`import Testing`), не XCTest.
**Чому.** Сучасний фреймворк, кращий синтаксис. Примітка: у headless CLI-toolchain (без повного Xcode) ні XCTest, ні Testing недоступні — `swift test` виконується в Xcode/CI; критерій етапу 1 — зелений `swift build`.
**Альтернативи.** XCTest (старіший; теж недоступний у цьому середовищі).

---

# Етап B — InferenceKit ✅

## ADR-0023 — Один OpenAICompatibleProvider для всіх вендорів ✅
**Рішення.** Єдина реалізація `OpenAICompatibleProvider` обслуговує OpenAI, OpenRouter, LM Studio, Ollama та будь-який OpenAI-сумісний API. Відмінності — лише в `OpenAIConfiguration` (baseURL / apiKey / headers / capabilities), не в логіці.
**Чому.** Нуль дублювання запиту/стрімінгу/обробки помилок. LM Studio Adapter і пресети (OpenAI/OpenRouter/Ollama) — тонкі фабрики поверх одного провайдера.
**Альтернативи.** Окремий клас на вендора (дублювання, розходження поведінки).

## ADR-0024 — Модель у конфізі провайдера, змінна через Mutex ✅
**Рішення.** Обрана модель живе в `OpenAIConfiguration.model`; провайдер тримає конфіг у `Mutex` (Swift `Synchronization`) і дозволяє `selectModel`/`reconfigure` у рантаймі без перестворення. `availableModels()` тягне список з `/models`.
**Чому.** «Вибір моделі» без зміни AIRequest; AIRequest лишається провайдер-агностичним. Потокобезпечно без актора (щоб `stream` лишався синхронним для виклику).
**Альтернативи.** Модель в AIRequest (протікання провайдер-специфіки в домен); провайдер-актор (зробив би `stream` async-викликом).

## ADR-0025 — Стрімінг через AsyncThrowingStream + кооперативне скасування ✅
**Рішення.** `stream(_:) -> AsyncThrowingStream<TokenChunk, Error>` поверх `URLSession.bytes` з парсингом SSE; `onTermination` скасовує `Task`, який скасовує мережевий запит. Скасування → `InferenceError.cancelled`.
**Чому.** Нативний backpressure, природне завершення (`finish`), скасування «з коробки» при виході зі споживчого циклу.
**Альтернативи.** Колбеки/Combine (більше церемонії, гірше скасування).

## ADR-0026 — Типізовані помилки `InferenceError` ✅
**Рішення.** Усі network/HTTP/API/decoding/timeout/cancel мапляться в `InferenceError`. Тіло помилки OpenAI (`{error:{message,type,code}}`) парситься; інакше — `.http(status, body)`. Timeout через `URLRequest.timeoutInterval`/конфіг сесії.
**Чому.** Стабільний типізований контракт для UI та ретраїв замість сирих `URLError`.

## ADR-0027 — Health check як неблокуючий статус ✅
**Рішення.** `healthCheck() async -> ProviderHealth` (не кидає; `.healthy`/`.unhealthy(reason)`), реалізований через легкий `availableModels()`.
**Чому.** UI може опитувати провайдери (особливо локальні LM Studio/Ollama) без обробки винятків.

## ADR-0028 — Кілька активних провайдерів на рівні Registry ✅
**Рішення.** `InferenceProviderRegistry` (actor) тримає N провайдерів одночасно (Embedded/LM Studio/OpenAI/OpenRouter), зберігає порядок, перемикання — `setCurrent(id:)`; інтроспекція — `registeredIDs`/`allProviders`/`current`.
**Чому.** Перемикання моделей/бекендів — операція реєстру, а не перестворення графа. ActionRunner бере `currentProvider()` через `InferenceProviderResolving`.

## ADR-0029 — MockStreamingProvider + inference-demo для перевірки без мережі ✅
**Рішення.** `MockStreamingProvider` стрімить канонічну відповідь по токенах (з підтримкою cancel); executable `inference-demo` проганяє повний шлях Action → PromptBuilder → AIRequest → Provider → streaming → completion + cancel + switch.
**Чому.** Перевірка архітектури в headless-середовищі без сервера/мережі; та сама заглушка слугує тестам.
**Перевірено:** `swift build` ✓, `swift run inference-demo` ✓ (стрімінг, finish_reason, скасування, перемикання).

---

# Уточнення перед закриттям InferenceKit ✅

## ADR-0030 — Action → Executor (AI — лише один із виконавців) ✅
**Рішення.** `Action` більше не будує `AIRequest`. Він повертає `ActionPlan` (`ExecutorID` + `any ActionCommand`). `ActionExecutor` (Core) виконує команду й повертає `AsyncThrowingStream<ActionOutput, Error>`. Інференс — це `InferenceExecutor` (InferenceKit), поряд з `ClipboardExecutor` тощо. `ExecutorID` і `ActionCommand` — відкриті для розширення (нові виконавці/команди без зміни Core).
**Чому.** Rewrite/Translate і Screenshot/Copy/OCR/Open URL уніфіковані під одним потоком Action→Executor; нові дії не торкаються архітектури. `ActionRunner` диспетчеризує по `ExecutorID`, виконавці інжектяться Composition Root.
**Альтернативи.** Action, прив'язаний до інференсу (поточний стан — не масштабується на не-AI дії); закритий enum команд (заважав би плагінам).
**Перевірено.** Demo: `Rewrite`→inference, `Copy`→clipboard через той самий runner.

## ADR-0031 — Provider → Runtime → Model ✅
**Рішення.** Розділено три поняття: `InferenceProvider` (бекенд), `RuntimeInfo` (рушій: MLX / llama.cpp / anthropic), `ModelInfo`/`ModelRef` (модель). `ModelRef { providerID, runtimeID?, modelID }`. Конфіг провайдера отримав `runtimeID`; OpenRouter витягує runtime з префікса моделі.
**Чому.** LM Studio = один провайдер з кількома runtime; OpenRouter маршрутизує до upstream-рушія; Embedded=MLX. Спрощує майбутню підтримку багатьох моделей/рушіїв.
**Альтернативи.** Плаский `model: String` (змішує поняття, ускладнює UI вибору моделі/рушія).

## ADR-0032 — Внутрішній Event Bus ✅
**Рішення.** `EventBus` (Core, fan-out, кілька підписників через `Mutex` + `AsyncStream`) + `AppEvent` (HotkeyPressed, ActionStarted/Finished, InferenceStarted/Finished, ScreenshotTaken, OCRFinished, ProviderChanged, PermissionGranted, `.custom`). Підключено до `ActionRunner`, `InferenceExecutor`, `InferenceProviderRegistry`.
**Чому.** Фундамент для Debug / Plugins / Automation / Macros / Statistics — закладено зараз, поки база мала. НЕ для аналітики/логування.
**Альтернативи.** NotificationCenter (нетипізовано, не Sendable-first), Combine (важче). `.custom` лишає простір плагінам без зміни enum.

---

## СТАТУС: InferenceKit ЗАКРИТО ✅
Не полірується далі. Наступна ітерація — **App Shell** (Menu Bar, Global Hotkey, NSPanel non-activating, Permission Manager, Settings). Далі: ContextKit → CaptureKit → PerceptionKit → реальні Actions. Без функціональності «про запас».

---

# Етап App Shell ✅

## ADR-0033 — .xcodeproj + локальний SPM-пакет у підтеці (не workspace) ✅
**Рішення.** Один `APILA.xcodeproj` (app-таргет у корені, App/) лінкує локальний SPM-пакет із підтеки `APILAKit/` через `XCLocalSwiftPackageReference` (relativePath "APILAKit"). Без `.xcworkspace`.
**Уточнення (first-run).** Спочатку пакет був у корені (relativePath ".") поряд із .xcodeproj — це відомий проблемний кейс для Xcode (пакет у теці проєкту). Перенесено у `APILAKit/` — стандартний надійний layout «app + local package». Білд пакета: `swift build --package-path APILAKit` (через `DEVELOPER_DIR=/Library/Developer/CommandLineTools`).
**Чому.** Потрібен підписаний `.app`-бандл зі стабільним bundle ID для TCC-дозволів (Accessibility/Screen Recording/Input Monitoring); SPM-executable цього не дає. Модулі лишаються SPM-таргетами → межі (ADR-0015) збережено, `swift build` працює.
**Альтернативи.** SPM + скрипт .app + ad-hoc підпис (дев-дружньо, але не те, що обрав користувач); повністю нативний .xcodeproj з framework-таргетами (втрата `swift build`/CLI-demo).
**Застереження.** Повного Xcode в дев-середовищі немає (`xcodebuild` блокується ліцензією) → pbxproj згенеровано вручну за стандартною схемою і провалідовано `plutil -lint`; фінальна збірка/підпис — у Xcode користувача (прийняти ліцензію: `sudo xcodebuild -license accept`, виставити Team).

## ADR-0034 — Логіка App Shell у бібліотеці AppFeature ✅
**Рішення.** Уся логіка (AppContainer, AppCoordinator, PermissionManager, hotkey, NSPanel, menu/settings views) — у SPM-бібліотеці `AppFeature`. У `.xcodeproj` лишається тільки `@main App` (App/APILAApp.swift).
**Чому.** `swift build` верифікує App Shell headless; xcodeproj додає лише signable shell. App-таргет залежить лише від продукту `AppFeature` (мінімальний pbxproj).
**Альтернативи.** Уся логіка в app-таргеті xcodeproj (не компілюється headless, не тестується через SPM).

## ADR-0035 — Глобальний хоткей через Carbon RegisterEventHotKey ✅
**Оновлення.** Дефолт — ⌘⇧Space (див. ADR-0040). `start()` повертає `Bool`: якщо хоткей зайнятий іншою програмою, це видно в меню.
**Рішення.** `GlobalHotkeyService` на Carbon (`RegisterEventHotKey` + `InstallEventHandler`), дефолт ⌥-Space, події в `HotkeyService.events` (AsyncStream). C-callback без захоплень + userData→self.
**Чому.** Стандартний, без сторонніх залежностей спосіб системного хоткея на macOS. Сучасних чисто-Swift API для глобальних хоткеїв немає.
**Альтернативи.** CGEventTap (важче, потребує Input Monitoring завжди), сторонні бібліотеки (проти принципу мінімум залежностей).

## ADR-0036 — Floating UI: non-activating NSPanel ✅
**Рішення.** `FloatingPanelController` (@MainActor) керує `NSPanel` зі стилем `.nonactivatingPanel`, `level=.floating`, `collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]`, показ через `orderFrontRegardless()`.
**Чому.** Панель поверх будь-якого застосунку без крадіжки фокуса → виділення в активній програмі зберігається (Kerlig-стиль). Реалізує ADR-0008.

## ADR-0037 — PermissionManager (TCC) ✅
**Рішення.** `PermissionService` (Core) + `PermissionManager` (AppFeature): Accessibility (`AXIsProcessTrusted`/`...WithOptions`), Screen Recording (`CGPreflight/RequestScreenCaptureAccess`), Input Monitoring (`IOHIDCheckAccess/RequestAccess`); deep-link у System Settings. Видача `permissionGranted` у Event Bus.
**Чому.** Keyboard-first + capture потребують явного, прозорого керування дозволами. Працює лише з підписаного бандла (TCC).
**Технічне.** `kAXTrustedCheckOptionPrompt` — небезпечний глобальний `var` під Swift 6 → використано літерал ключа. Білд через `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build` (активний Xcode не має прийнятої ліцензії).

## ADR-0040 — Etap C: перший повний вертикальний зріз ✅
**Рішення.** Замкнуто сценарій: виділення → ⌥Space → Floating Panel (keyboard-first) → дія → стрімінг → Copy/Replace/Insert.
- **Захоплення контексту — раз, на хоткеї** (доки джерело у фокусі). Додано `ActionRunner.run(action, snapshot:)` — виконання з готовим знімком без повторного збору (панель потім стає key і повторний AX/⌘C дав би порожнечу).
- **Floating Panel**: `FloatingPanel: NSPanel` (override `canBecomeKey=true`) + `.nonactivatingPanel` → отримує клавіатуру, не активуючи APILA; translucent (`.ultraThinMaterial`), позиція біля курсора. UI-стейт-машина — `PanelViewModel` (actions→customPrompt→generating→result), keyboard-first (↑↓/⏎/esc, ⌘C/⌘R/⌘I через `keyboardShortcut`).
- **Streaming** реальний: `ActionOutput.token` додається в `output` наживо.
- **Replace/Insert (простий шлях, без AX-вставки)**: `ResultInserter` — запам'ятати `frontmostApplication` на хоткеї → write clipboard → re-activate джерело → `⌘V` (Insert: →, Return, ⌘V).
- **Mock Mode**: `bootstrap` реєструє local (LM Studio) + Mock; якщо health local не healthy → `setCurrent(mock)`. UI працює без локальної моделі.
- **Custom Prompt**: `CustomPromptAction(prompt:)` (ActionKit) будується з введеного тексту.
- **App**: agent-only (LSUIElement=YES); `MenuBarExtra` (Open APILA / Permissions / Provider / Quit) + `Settings`; старт через `NSApplicationDelegateAdaptor`. Debug-вікно прибрано.
**Архітектура збережена.** Core чистий; AppFeature → лише ContextKit/ActionKit/InferenceKit/AppUI; Kit-модулі не залежать один від одного; зв'язок через Core-протоколи. `Coordinator` — лише оркестрація.
**Перевірено.** `swift build --package-path APILAKit` ✓, pbxproj `plutil` OK. Запуск .app — у Xcode користувача.
**Відомий ризик (перевірити на запуску).** Чи отримує non-activating key-панель клавіатуру в accessory-режимі (LSUIElement) без `NSApp.activate`. Якщо ні — фолбек: активувати APILA при show (контекст уже захоплено, тож focus-steal не шкодить; Replace і так реактивує джерело).
**Правки після першого запуску (підтверджено користувачем: панель + клавіатура працюють).**
- Хоткей за замовчуванням ⌥Space → **⌘⇧Space** (⌥Space/⌃Space часто зайняті перемиканням розкладок). Carbon RegisterEventHotKey не потребує TCC.
- Панель: `.titled` → **`.borderless`** (+ `.nonactivatingPanel`, `canBecomeKey` override). Прибрано «світлофор» (close/minimize), що висів у прозорому titlebar поза заокругленим контентом. Закриття — Esc / кнопка Close.
- Підтверджено: реальний конект — LM Studio на :1234 (модель — завантажена в LM Studio; ми шлемо id "local-model"). Mock — лише коли health-check :1234 падає.

## СТАТУС: App Shell — каркас готовий ✅
`swift build` ✓ (AppFeature). `.xcodeproj` згенеровано (plutil OK), збірка .app — у Xcode користувача. App Shell: menu bar, ⌥-Space hotkey, non-activating panel, permission manager, settings — реальний код, фічі-заглушки. Далі: **ContextKit** (selected text/clipboard) → CaptureKit → PerceptionKit → реальні Actions.

---

# Етап ContextKit (мінімальний зріз) ✅

## ADR-0038 — ContextKit: selected text (AX + ⌘C) + clipboard ✅
**Рішення.** `ContextAggregator` наповнює `selectedText` і `clipboardText`. Selected text: спершу Accessibility (`AXFocusedUIElement`→`AXSelectedText`, без зачіпання буфера), fallback — симуляція ⌘C через CGEvent із **збереженням і відновленням** буфера. Clipboard читається через канонічний `SystemClipboard: ClipboardService` (переїхав у ContextKit; одна інстанція ділиться між контекстом і ClipboardExecutor). Джерела за протоколами `ClipboardService`/`SelectedTextReading` → аггрегатор юніт-тестується з моками.
**Чому.** AX чистіший; ⌘C-fallback покриває застосунки без AX, не псуючи буфер. Privacy-first: береться лише те, що в `ContextRequirements`. Мінімальний зріз — рівно для робочого Rewrite/Copy, без «про запас».
**Свідомо відкладено.** active app / browser URL / screen image — додамо, коли дія цього потребуватиме.
**Технічне.** AX-константи (`kAXFocusedUIElementAttribute` тощо) — небезпечні глобальні `var` під Swift 6 → літерали. Білд: `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build` ✓. `swift test` у цьому середовищі не йде (CLT без `Testing`) — тести Swift Testing підуть у Xcode/CI.

## ADR-0039 — Перший запуск: Debug-вікно + лише Accessibility ⛔
**Скасовано ADR-0040:** Debug-вікно прибрано, `LSUIElement = YES`.
**Рішення.** Для верифікації ContextKit app тимчасово РЕГУЛЯРНИЙ (LSUIElement = NO → Dock + видиме вікно), головна сцена — `DebugView`: live passive AX-виділення + clipboard (таймер 0.5с) і захоплення по ⌥Space (AX→⌘C). Запитуємо лише **Accessibility** (потрібен для AX-читання та ⌘C; Screen Recording для ContextKit НЕ треба). Carbon-хоткей працює без TCC.
**Чому.** Користувач має власноруч запустити й перевірити SelectedTextReader обома шляхами. Видиме вікно + Dock-іконка роблять «запустилось?» очевидним.
**Тимчасово.** LSUIElement повернемо в YES (agent-only), коли panel-UX буде готовий.
**Перевірено.** `swift build --package-path APILAKit` ✓; pbxproj `plutil -lint` OK. Збірку .app робить користувач у Xcode (немає повного Xcode/ліцензії тут).

---

# Етап 1 — стабілізація ✅

## ADR-0041 — Буфер обміну позичаємо, а не перезаписуємо ✅
**Рішення.** `PasteboardSnapshot` (ContextKit) зберігає ВСІ елементи й типи pasteboard. ⌘C-fallback відновлює їх лише якщо копіювання справді змінило буфер; Replace/Insert після ⌘V через ~0.5с повертають попередній вміст, якщо користувач нічого не скопіював у проміжку.
**Чому.** Раніше відновлювався лише текст: картинки/файли/rich text у буфері зникали від одного натискання хоткея.
**Альтернативи.** Вставка через AX `kAXSelectedTextAttribute` без буфера (чистіше, але працює не всюди — лишаємо на потім).

## ADR-0042 — Провайдер перевіряється на кожному показі панелі ✅
**Рішення.** `AppContainer.refreshProvider()` після показу панелі (окремою задачею, щоб повільний endpoint не гальмував UI). Mock явно позначений у панелі.
**Чому.** LM Studio, запущений після APILA, раніше не підхоплювався до перезапуску, а Mock тихо віддавав фейкову відповідь.

## ADR-0043 — Прибрано модуль AppUI ✅
**Рішення.** Видалено `AppUI` (лише заглушки; справжні view — `AppFeature/Views`). `CaptureKit` лишається таргетом, але не підключений до `AppFeature`, доки порожній.
**Чому.** Мертвий код вводив в оману щодо того, де живе UI.
