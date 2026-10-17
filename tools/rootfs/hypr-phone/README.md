# hypr-phone — черновик мобильной настройки Hyprland (Nothing Phone (1))

**Статус: черновик, на телефоне не запускался, в образ не подключён**
(`tools/build-rootfs.sh` эти файлы не копирует).

Цель: Omarchy 4.0.4 (edge aarch64, Hyprland 0.56.2) на экране DSI 1080x2400
(~6.55", ~402 ppi), сенсор `fts_ts`, без клавиатуры.

## Файлы

| Файл | Куда ставить | Что делает |
|---|---|---|
| `phone.lua` | `~/.config/hypr/phone.lua` | масштаб, привязка тача, курсор, окна на весь экран, автозапуск OSK, жесты |
| `environment.d/20-phone-osk.conf` | `~/.config/environment.d/` | переводит приложения с fcitx на text-input-v3 (для squeekboard) |
| `systemd-user/omarchy-fcitx5.service.d/10-phone-osk.conf` | `~/.config/systemd/user/omarchy-fcitx5.service.d/` | не даёт fcitx5 занять единственный слот input-method |

Подключение — одна строка в `~/.config/hypr/hyprland.lua` после
`require("hypr.autostart")`:

```lua
require("hypr.phone")
```

Почему так: в Omarchy 4.0.4 пользователь правит только `~/.config/hypr/*.lua`;
`hyprland.lua` грузит `default.hypr.omarchy`, затем свои
`hypr.monitors/input/bindings/looknfeel/autostart`
(omarchy-settings `etc/skel/.config/hypr/hyprland.lua:4,14,19-23`), а
`~/.config/?.lua` уже в `package.path` (`usr/share/omarchy/default/hypr/bootstrap.lua:33-38`),
и модули с префиксом `hypr` перечитываются при reload (`bootstrap.lua:4-8`).
Один отдельный файл не трогает skel-файлы пользователя («старый путь» остаётся).

## Решения и источники

Источники скачаны 2026-10-17: `omarchy-settings-4.0.4-6-aarch64` и
`omarchy-4.0.4-2-aarch64` с pkgs.omarchy.org/edge/aarch64 (Lua-конфиги лежат в
omarchy-settings); Hyprland `v0.56.2` (= `efb5099`); hyprgrass `main@a897915`;
derekross/omarchy-mobile `main@1155a7c` (MIT); omarchy-on-screen-keyboard
`research/src-stage2b/omarchy-on-screen-keyboard@f18f098` (v0.3.4, MIT).

### Масштаб 2.5

- Плотность: √(1080²+2400²) = 2632 px / 6.55" ≈ **402 ppi**. Android на этом
  телефоне рисует при 420 dpi (`device-info/getprop.txt:838`), т.е. 2.625 px на dp.
- Hyprland требует целый логический размер и шаг 1/120 (fractional-scale-v1).
  2.625 даёт 411.4 px — не целое. Ближайшие годные: **2.5 → 432x960**, 3 → 360x800.
- 402 / 2.5 = **161 ppi на логический пиксель** — это базовая линия Android
  (160 dpi = 1 dp), т.е. элементы Omarchy будут физически того же размера, что
  в Android на 160-dpi-эталоне. При 3 — 134 ppi (на ~17 % крупнее, места
  меньше: 360 px ширины).
- Для сравнения omarchy-mobile на Pixel 7 Pro (1440x3120, ~512 ppi) ставит 3 →
  480x1040 (`packages/omamobile-shell/bin/omamobile-setup-user:82-84`), т.е.
  ~171 ppi на лог. пиксель — близко к нашим 161.
- Синтаксис: `hl.monitor({ output, mode, position, scale, transform })` —
  поля в `src/config/lua/bindings/LuaBindingsConfigRules.cpp:82-103`
  (scale — строка по умолчанию `"auto"`, :86; transform 0..7, :103); числовой
  scale используется в skel (`etc/skel/.config/hypr/monitors.lua:11`).
  transform = 0: панель портретная нативно (rm692e5, DTS
  `sm7325-nothing-spacewar.dts:992-994`).
- `GDK_SCALE=2` из skel (`monitors.lua:4,7`) не трогаю.
- Правило skel `output = ""` (`monitors.lua:8`) остаётся; правило с именем
  `DSI-1` конкретнее. **Не проверено:** имя коннектора `DSI-1` (msm DRM обычно
  так называет) — проверить `hyprctl monitors all`.

### Привязка тача

`hl.config({ input = { touchdevice = { output = "DSI-1" } } })` — опция
`input:touchdevice:output` (`src/config/values/ConfigValues.cpp:346`, по
умолчанию `[[Auto]]`). Вложенная таблица = ключ через `:` — так же, как
`input.touchpad` в Omarchy (`usr/share/omarchy/default/hypr/input.lua:64-68`).
Есть и пер-устройство `hl.device({ name = "fts_ts", output = ... })` (поле
`output`, `LuaBindingsConfigRules.cpp:259`) — не использую: экран один,
глобальной опции достаточно. Имя `fts_ts` из `logs/hw-check-stage1.txt:32`.

Курсор: `cursor.invisible` / `hide_on_touch` (`ConfigValues.cpp:588,608`),
как в omarchy-mobile (`omamobile-setup-user:91-94`).

### Жесты

- **Встроенные `hl.gesture` — только тачпад.** Реализация идёт через
  `g_pTrackpadGestures`, пальцев 2..9 (`LuaBindingsConfigRules.cpp:737-755`);
  для тачскрина Hyprland 0.56.2 даёт лишь свайп рабочих столов от края:
  `gestures.workspace_swipe_touch` (`ConfigValues.cpp:401,403,405`). Он включён
  как вариант «без плагина».
- **hyprgrass** (horriblename/hyprgrass, BSD-3-Clause) — тач-жесты.
  Релизов с v0.8.2 (2024-10-09) нет, работа идёт в `main` (последний push
  2026-10-16). Совместимость с 0.56: в `hyprpm.toml:66` есть пин
  `efb5099 (v0.56.2) → 8e60546`. Lua-конфиг поддерживается:
  `hl.plugin.hyprgrass.bind/gesture` регистрируются в `src/main.cpp:614-615`,
  документация `docs/configuration.md:11-30,51-112`, `docs/lua_migration.md:7-11`.
  Разбор паттерна `src/main.cpp:244-300`, направления — Hyprland
  `TrackpadGestures.cpp:13-38` (`left/right/up/down`, для `bind` только одно
  направление).
- **Пакета нет:** ни в ALARM extra, ни в omarchy edge aarch64 (проверены
  `.db` 2026-10-17); в AUR только `hyprgrass-git` (PKGBUILD от 2025-08-04).
  Установка — `hyprpm add https://github.com/horriblename/hyprgrass && hyprpm enable hyprgrass`
  (README hyprgrass :41-42); `hyprpm` есть в репо (0.56.2-4 ALARM / -7 omarchy),
  но собирает плагин на телефоне (нужны meson/ninja/glm и заголовки Hyprland).
  Автозагрузка — `hyprpm reload -n` (README :45), добавлено в `phone.lua`.
  Предупреждение автора: плагин alpha, может «съесть» тач (README :5-10) —
  первый запуск только с USB-клавиатурой или SSH.

Минимальный набор (только если `hl.plugin.hyprgrass` существует):

| Жест | Действие | Источник действия |
|---|---|---|
| от нижнего края вверх | меню приложений `omarchy-menu toggle apps` | `default/hypr/bindings/utilities.lua:2` |
| от верхнего края вниз | меню Omarchy `omarchy-menu toggle` | `utilities.lua:1` |
| 3 пальца влево/вправо | следующее окно (cycle_next + bring_to_top) | `bindings/tiling.lua:44-47` |
| 3 пальца вниз | закрыть окно `hl.dsp.window.close()` | `tiling.lua:1` |
| от правого края влево | показать squeekboard | DBus, см. ниже |
| горизонтальный свайп от края (без плагина) | соседний рабочий стол | `ConfigValues.cpp:401` |

`sensitivity = 4.0` — совет автора для планшетов (`docs/configuration.md:14-16`),
для телефона подбирать. **Не проверено:** `edge_margin` в физических или
логических пикселях; появится ли `hl.plugin.hyprgrass` уже при первом разборе
конфига, если плагин грузит `hyprpm reload` позже (README hyprgrass показывает
тот же guard `if hl.plugin.hyprgrass`, `docs/configuration.md:249`).

Все окна развёрнуты (`maximize`, снят тег `floating-window`) — из
omarchy-mobile `packages/omamobile-shell/hypr/phone.lua:9-10` (MIT): при 432 px
ширины плитка из двух окон даёт по 216 px. Поэтому «переключить окно» =
`cycle_next` + `bring_to_top`.

### Кнопки питания и громкости

Ничего не меняю — Omarchy уже делает нужное:

- Громкость: `XF86AudioRaiseVolume/LowerVolume` → `omarchy-audio-output-volume`
  (`default/hypr/bindings/media.lua:2-3`). На телефоне `gpio-keys` даёт
  `KEY_VOLUMEUP` (DTS :74), `pmic_resin` — `KEY_VOLUMEDOWN` (DTS :1215-1216).
- Питание: `XF86PowerOff` → системное меню (`utilities.lua:9`, `locked`);
  logind игнорирует кнопку (`etc/systemd/logind.conf.d/10-ignore-power-button.conf:2`
  в omarchy-settings), `pmic_pwrkey` — DTS :1211. Нажатие клавиши будит экран
  (`misc.key_press_enables_dpms = true`, `default/hypr/input.lua:72`).
- Android-подобное поведение (короткое — блокировка, долгое — меню,
  питание+громкость вниз — скриншот) в omarchy-mobile сделано скриптом
  `omamobile-keys` (`packages/omamobile-shell/bin/omamobile-keys:3-18`,
  привязки `hypr/phone.lua:34-45`, MIT). Не перенесено: скрипт завязан на их
  пакеты (omacam, lock IPC); можно портировать отдельно.

### Экранная клавиатура (OSK)

| Вариант | Пакет | Плюсы | Минусы |
|---|---|---|---|
| **squeekboard** (выбран) | ALARM extra 1.43.1-6, GPL-3.0 | в репо; сам показывается на текстовом поле (text-input-v3); проверен на Omarchy 4.0.4 в omarchy-mobile (`PKGBUILD:9-10`, `omamobile-setup-user:98-106`) | нужен слот input-method → fcitx5 выключить |
| omarchy-on-screen-keyboard | плагин Omarchy (MIT, v0.3.4), нужен `python-pywayland` (ALARM extra 0.4.19) | рисуется omarchy-shell в теме, свайп-набор, диктовка | для «Quattro shell, Hyprland 0.56+» (README :193); авто-показ только в режиме планшета по `SW_TABLET_MODE` (README :165-170) — у телефона его нет, нужно `"autoShow": "always"` (README :98-99); тоже требует убрать fcitx5 (README :49-63); ставится `omarchy plugin add` из сети (README :38-41) |
| wvkbd | только AUR 0.20 | простой | нет в ALARM, нет авто-показа без адаптера |

squeekboard: запуск через `o.launch_on_start` (`default/hypr/helpers.lua:112-120`)
плюс `gsettings ... screen-keyboard-enabled true` — ключ, который
squeekboard читает (строки есть в бинарнике пакета; omarchy-mobile делает то же,
`hypr/phone.lua:55`). Ручной показ жестом —
`busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true`:
имя шины/путь/метод подтверждены строками в `/usr/bin/squeekboard` и
`BusName=sm.puri.OSK0` в `mobi.phosh.OSK.service`; **сигнатура `b` — не проверена**.

fcitx5: Omarchy запускает `omarchy-fcitx5.service` и ставит
`INPUT_METHOD/QT_IM_MODULE/XMODIFIERS/SDL_IM_MODULE=fcitx`
(`usr/lib/environment.d/10-omarchy-fcitx.conf`). Два файла из omarchy-mobile
(MIT, с атрибуцией в шапке) это переопределяют: drop-in с `ConditionPathExists`
вместо `mask`, потому что first-run Omarchy делает `enable --now` и на
замаскированном юните падает и повторяется при каждом входе.
Цена: перестают работать compose-последовательности CapsLock (README OSK :61-63).

### Известная проблема: меню перехватывает фокус у OSK

omacom/omarchy#9029 — **OPEN** (обновлено 2026-10-11). `OverlayWindow`
по-прежнему берёт `WlrKeyboardFocus.Exclusive`, поэтому пока открыто меню
Omarchy, касания до OSK не доходят: поиск в меню набрать нельзя, выбор пунктов
касанием работает. PR #9135 закрыт 2026-10-15; PR #13193 (OPEN) включается
только опцией `overlays.cooperativeFocus` в `shell.json` и выключен по
умолчанию.

## Проверка

- `luac -p phone.lua` (Lua 5.5.1, та же `lua`, от которой зависит пакет
  `hyprland`) — синтаксис OK.
- Прогон `phone.lua` с заглушкой `hl` и настоящим `default/hypr/helpers.lua`
  из omarchy-settings 4.0.4-6: без hyprgrass — 1 правило монитора, 2 правила
  окон, 3 задачи автозапуска, 0 жестов; с hyprgrass — 6 привязок, у всех
  `kind`/`origin`/`direction` из допустимых значений. Это проверка вызовов,
  **не** проверка в Hyprland.
- На телефоне не запускалось ничего. Перед включением в образ:
  `hyprctl monitors all` (имя `DSI-1`), `hyprctl devices` (имя `fts_ts`),
  `hyprctl configerrors` после `require("hypr.phone")`.
