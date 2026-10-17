# Nothing Spacewar mobile UI v4

Версия 0.4.0 — дополнение к `omarchy-dev` r7031, а не другая оболочка.
Пакет не изменяет `/usr/share/omarchy`, не скрывает штатную панель, не меняет
пароль/PAM и не обращается к телефону. `spacewar.statusbar` и `spacewar.home`
удалены. Установка пакета сама по себе профиль не включает.

Дополнительный компонент `spacewar.lock` по умолчанию выключен. После
установки владелец может отдельно включить его в **разблокированной** сессии:

```sh
spacewar-mobile-setup --lock
hyprctl reload
hyprctl configerrors
omarchy-restart-shell
omarchy-shell lock status
```

`--lock` работает и поверх уже включённого v3, не меняет bar/жесты и не требует
включать остальной мобильный профиль. Убедиться, что `upstreamVerified` и
`passwordPam` равны true; сначала проверить ручной `omarchy-shell lock lock`
с доступным SSH. Пароль аккаунта и `/etc/pam.d` setup не изменяет.

PIN-пэд: 0–9, ⌫ и ↵, цели 96×64 logical px на 540 px (не менее 56×64 при
штатной телефонной ширине). Секрет отправляется непосредственно штатному
PAM `omarchy-lock-password`, без аргументов процессов/файлов/IPC для ввода.
Штатные fingerprint, физическая клавиатура, обработка PAM failure и очистка
секрета сохранены. Ошибка показывается штатным сообщением; OSK не требуется.

Короткое питание при включённой DSI-1 запрашивает lock, ждёт `secure=true`,
потом использует штатный DPMS off. При погашенной DSI-1 — штатный wake, без
разблокировки. Состояние читается из `hyprctl -j monitors all`, а не угадывается
по последнему нажатию. Автопробуждение от клавиш/мыши отключается только
подключением `phone-lock.lua`; suspend этим компонентом не включается.
Удержание 600 ms однократно вызывает `omarchy-menu toggle system`; повторные
press игнорируются, release после удержания экран не переключает.
На session lock показана просьба разблокировать: **штатное меню открывается
после успешного PIN**. Меню r7031 использует отдельный OverlayWindow и не может
отображаться внутри защищённой поверхности; разрешать обычные overlays над
lock или снимать lock ради меню было бы хуже. Аварийный SSH-выход отменяет
отложенное меню.

`--lock` снимает stay-awake/screensaver-off и задаёт `idle.lock=60`,
`idle.screensaver=0`: через минуту включается штатный lock, затем его штатный
таймер гасит дисплей через 5 секунд бездействия. Отдельная анимированная
заставка на телефоне не нужна. Оба значения — выбранная политика, не замер.
`spacewar-mobile-setup --undo` откатывает оба компонента и всегда возвращает
stay-awake; затем reload/configerrors и restart оболочки **после разблокировки**.
Журнал lock (`lock-setup.json`, 0600) отдельный, записывается до изменений;
сохраняются исходные файлы, маркеры и последующие пользовательские правки.

Для аварийного выхода по SSH **под тем же пользователем**, без ввода PIN:

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export OMARCHY_PATH=/usr/share/omarchy
omarchy-shell lock unlock
spacewar-mobile-setup --undo
```

`omarchy-shell` r7031 сам находит Wayland socket при отсутствии
WAYLAND_DISPLAY; именно этот сценарий проверен на изолированном стенде.
`unlock` — добавленный same-user IPC нашего клона; штатный r7031 его не имеет.
Пользователь с доступом к этому IPC уже может менять код оболочки.
`loginctl unlock-session` здесь не обещается: Service.qml не слушает сигнал
logind Unlock. Если shell не отвечает после crash, сначала восстановить его
через `omarchy-restart-shell`, затем повторить IPC; upstream stranded-lock
recovery сохранён, но восстановление после crash на телефоне не проверялось.

Почему клон: проверены весь stock `LockView.qml`, entryPoint `Service.qml`,
manifest и API плагинов r7031 — нет slot/Loader/настройки для внешнего keypad,
а обычный overlay не является WlSessionLockSurface. Клон имеет
`omarchy.clonedFrom: omarchy.lock`, наследует authentication capability и
сохраняет IPC target `lock`; stock service отключается только флагом setup.
Исходники MIT Omarchy атрибутированы в LICENSE.omarchy. Хеши **всех шести**
исходных lock-файлов — в `lock-upstream.json`; setup (включая повторный запуск)
и запуск service проверяют их. При дрейфе новый lock не включается, status
показывает `upstreamVerified=false`: до review/rebase нужно `--undo`, а не
считать телефон защищённым. Уже взятый session lock не снимается проверкой.

Цепочка кнопки подтверждена локальными исходниками ядра b90de19:
`sm7325-nothing-spacewar.dts:24` включает pmk8350; `pmk8350.dtsi:41` задаёт
KEY_POWER; `drivers/input/misc/pm8941-pwrkey.c:447` именует pmic_pwrkey.
[utilities.lua:9 r7031](https://github.com/basecamp/omarchy/blob/cce8b1c971df64a7610b818ff8819e4bea04584a/default/hypr/bindings/utilities.lua#L9)
сразу открывает system menu с locked=true; наш Lua обратимо заменяет этот bind
на press/release. По [сохранённому исследованию](../../research/power-plan.md#32-почему-сейчас-stay-awake)
logind настроен HandlePowerKey=ignore; живые события и текущий logind на телефоне
не перепроверялись. Компонент не меняет системный logind. Перед телефонной
приёмкой владельцу проверить отсутствие второго обработчика и все сценарии
питания при работающем SSH. См. [проверки v4](VALIDATION.md).

Шторка v3: две колонки плиток 88 px, отдельная цель 48 px для входа
в штатные Wi-Fi/Bluetooth панели (также удержание), ползунки 48 px,
«Закрыть окно» и питание. При 540×1200 высота шторки 644 px без фонарика;
в альбомной ориентации содержимое прокручивается. Свайп вверх по заголовку
или нижней ручке закрывает шторку; касание ручки и Escape тоже закрывают.
Назад/Домой/Недавние остаются жестами.

Wi-Fi/SSID — `Quickshell.Networking`; Bluetooth — `Quickshell.Bluetooth`;
громкость и mute — `Quickshell.Services.Pipewire` с `PwObjectTracker`.
Оформление ползунков — штатный `qs.Ui.PanelSlider`; цвета и шрифт — Commons.
Сетевые имена выводятся только как PlainText. Ни nmcli, ни pactl не опрашиваются.

Штатный monitor panel r7031 не экспортирует живой brightness service для
сторонней шторки: его IPC state хранит последнее обновление закрытой панели.
Поэтому яркость читается и устанавливается штатным `omarchy-brightness-display`
для DSI-1, запись — при отпускании ползунка, 1–100%, без OSD поверх пальца.
Раз в 5 секунд только при открытой шторке и после действия обновляются
яркость, DND (`notifications.dndState`/`toggleDnd`), ориентация DSI-1,
источники squeekboard и `sm.puri.OSK0.Visible`. Неизвестное состояние показано
как недоступное, а не как выключенное. US отображается как EN.

Штатной команды Omarchy для фонарика в r7031 нет. Плитка существует только
при наличии `/sys/class/leds/white:flash/brightness` и праве записи текущего
пользователя; переключает 0/1, без повышения прав и новых udev-правил.
Наличие устройства и права на телефоне не проверялись: доступ к нему запрещён.

После установки владельцем в сессии телефона:

```sh
spacewar-mobile-setup
hyprctl reload
hyprctl configerrors
omarchy-shell shell rescanPlugins
```

Откат: `spacewar-mobile-setup --undo`, затем те же reload/configerrors/rescan.
Если активен профиль v1, сначала выполнить его `--undo`, затем обновить пакет.
Setup отказывается работать с заменяющей штатную панель `bar.id`.

Setup меняет только `bar.position`, секции `bar.layout` и записи двух своих
плагинов в `plugins`/`disabledPlugins`; прочие настройки сохраняет. Сверху:
spacer 44, часы HH:mm, пустой центр, network/bluetooth/audio/power справа.
Высота берётся из штатной темы (26 logical px в проверенном окружении), а не
переписывается. Резерв 44 — заданный отступ камеры слева; проверить на стекле.

Журнал исходных JSON/Lua записывается атомарно с режимом 0600 в
`$XDG_STATE_HOME/spacewar-mobile/setup.json` до первой правки. Повторный запуск
ничего не дублирует. Undo возвращает исходные байты при отсутствии последующих
правок; иначе восстанавливает неизменённые секции и сохраняет пользовательские
изменения. Добавленный dofile удаляется, мигрированные вызовы возвращаются
на свои места, только созданные setup ссылки плагинов удаляются.

| Решение пользователя | Что выбрано | Почему удобнее / как сохранено |
|---|---|---|
| Минимальная строка сверху | Штатный `omarchy.bar`, без command-кнопок | Штатные индикаторы и popup остаются рабочими; нет переключения bar implementation |
| Свайп сверху и касание строки → шторка | Верхний edge-bind; область `⌄` шириной 140 по центру строки | Касание не перехватывает часы и штатные индикаторы; шторка оставляет строку видимой |
| Шторка настроек | `spacewar.shade`: крупные входы в штатные network/bluetooth/audio/power | Общего control center в r7031 нет; Wi-Fi, pairing, mixer и питание реализованы Omarchy |
| Домой = все приложения | `omarchy-shell omarchy.dock apps` | Уже есть иконки 56 px и ячейки около 123 px, три колонки при 540 px; отдельный launcher не нужен |
| Недавние карточками | `spacewar.switcher` | Dock показывает приложения и окна, но не обзор карточек с live-превью; capture выключается при закрытии |
| Android-жесты снизу | Единственная полоса `Navigation.qml`: вверх → домой, ←/→ → соседнее окно, удержание 450 ms → карточки | Edge-bind закреплённого hyprgrass не сообщает длительность; полоса различает свайп, отмену и удержание без дублирующего bind |
| Назад внутри приложений | Адресные Alt+Left или Escape по allowlist | Не отправляет произвольные клавиши терминалам и неизвестным приложениям |
| PIN = пароль аккаунта | Опциональный `spacewar.lock` | Штатный PAM, пароль не меняется; включение только `--lock` |

`phone-mobile.lua` задаёт us,ru, привязку touch к DSI-1 и три hyprgrass edge-bind:
верх↓ → шторка, левый/правый край внутрь → назад; sensitivity 2.0, edge_margin 24.
Нижние жесты обслуживает полоса высотой 16 px: горизонтальный порог 48 px,
вертикальный 12 px, дрожание для отмены hold 12 px. Это стартовые touch-пороги,
а не аппаратные измерения. Setup переносит edge-вызовы `hg`/`hyprgrass`/
`hl.plugin.hyprgrass` из `phone.lua` в пакетный профиль, оставляя обратимые
маркеры; остальные конфиги и загрузку hyprgrass не трогает.

Back: Chrome/Chromium/Brave/Firefox, `chrome-*` webapps, Nautilus/Thunar/
Dolphin/Nemo/PCManFM получают Alt+Left. Только известные окна настроек
(nm-connection-editor, blueman-manager, GNOME Settings, KDE System Settings,
pavucontrol) получают Escape: это закрытие меню/диалога, а не универсальная
навигация; оно может отменить ещё не применённый ввод. Foot/footclient,
Ghostty, Alacritty, Kitty, WezTerm и неизвестные классы не получают клавиш.
Открытая собственная шторка/карточки сначала закрываются. Перед действием
проверяется lock; key-up отправляется в finally тому же адресу окна.

Основание решений: распакованный r7031, SHA256
`7dab7af6f564255271e98b1970e952c1be61d9b71f765c5eb667d7cc5c394148`.
В [исходниках r7031](https://github.com/basecamp/omarchy/tree/cce8b1c971df64a7610b818ff8819e4bea04584a/shell)
проверены manifests `plugins/panels/{network,bluetooth,audio,power}` (bar-widget),
`plugins/osd` (panel для кратких OSD, не control center), все остальные panel/
overlay/service manifests, `shell.qml:summon()` и `plugins/dock/{Dock,AppGrid}.qml`.
Панели открываются через публичный IPC: scoped API третьего плагина не даёт
управлять чужими ID. Не копируются их QML или сервисы, нет nmcli/pactl/MM polling.

Модель карточек адаптирована из derekross/omarchy-mobile @1155a7c;
атрибуция MIT — в LICENSE.omarchy-mobile. Совместимость с будущими изменениями
API проверяется повторным QA, обновления исходников Omarchy не патчатся.

Владельцу проверить на телефоне: вырез и касания в обеих ориентациях; все шесть
направлений и hold/cancel снизу без старых binds; Wi-Fi password, Bluetooth
pairing, mixer, RU/EN и OSK; переходы Back в webapps/файлах/настройках;
активацию/закрытие трёх окон и Adreno screencopy; отсутствие интерактивных
поверхностей над lock. После enable, restart и undo проверить журнал оболочки.
Результаты стенда и команды повторения — в [VALIDATION.md](VALIDATION.md).

## Образ stage3 (0.4.0-4)

Setup без `--lock` выполняется в chroot от user: для JSON, ссылок плагинов
и пользовательской маски systemd работающая сессия не нужна. Маска создаётся
как ссылка `~/.config/systemd/user/omarchy-fcitx5.service -> /dev/null`;
штатные файлы Omarchy не меняются. На первом входе маска уже действует.
OSK берётся из пакета `omarchy-osk-spacewar`, включается в `shell.json` и
получает `autoShow: always`, `extraRow: true`; остальные параметры сохраняются.
Undo возвращает прежний JSON и маску, сохраняя последующие правки пользователя.

Для нового HOME setup создаёт `hypr/phone.lua`, подключающий пакетный
`phone-device.lua`: DSI-1 scale 2, scrolling column_width 1.0, hide_on_touch,
загрузка `/usr/lib/hyprgrass/libhyprgrass.so`. Его require стоит перед
`phone-mobile.lua`; только последний задаёт kb_layout и touch output.
Так параметры устройства обновляются пакетом, а пользовательский файл остаётся
минимальным. Существующий phone.lua сохраняется с миграцией edge-жестов.
Для ранее применённого профиля 0.4.0-3 сначала выполните `--undo`, затем setup.

Прерванное применение нового профиля продолжается из журнала; завершённый
повторный запуск сохраняет пользовательские изменения. Squeekboard больше
не является зависимостью; шторка использует IPC OSK `toggle`/`switchLanguage`.
Прежнее описание опроса squeekboard выше относится к версии v3.
