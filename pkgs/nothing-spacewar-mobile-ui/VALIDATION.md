# Проверки v4 lock/power, 17.10.2026

Проверяется `nothing-spacewar-mobile-ui-0.4.0-1-any.pkg.tar.zst`.
Телефон, текущий desktop, пароль, PAM и системные конфиги не менялись.

`tests/check.sh`: makepkg --nodeps --force --noconfirm, **23 tests**, ShellCheck,
luac обоих профилей и qmllint Qt 6.12 — PASS. Setup/actions читаются из
собранного staging. Новые проверки: независимое включение lock поверх v3,
повтор, возврат маркеров и исходных байтов, сохранение последующих правок,
отказ при дрейфе исходника до любых изменений. `--nodeps` не доказывает
разрешение runtime-зависимостей на aarch64.

Qmllint оставляет предупреждения: необязательный upstream `Owe.LockFeed`
не установлен на стенде; inherited unqualified/stale-property-read в stock
Service/LockView и существующий BluetoothAdapter warning. Ошибок, мешающих
загрузке, нет. LockFeedSurface штатно загружается Loader только для видео;
проверенный фон статический. Предупреждения не скрыты.

`tests/headless_lock.py`: настоящий shell r7031, отдельные D-Bus/HOME/XDG,
labwc/pixman **540×1200**, настоящий ext-session-lock и WlSessionLockSurface.
PIN-кнопки получают QtTest mouseClick по центру с проверкой целей ≥56 px:
все цифры, erase, submit. Это синтетические клики, не физический сенсор.
В копии собранного плагина только для QA заменён password PamContext на
асинхронный mock (тестовый PIN 2468); сохранены штатные submit, pending secret,
success/failure handlers и реальная блокировка compositor. Дополнительно
вставлены закрытый тестовый IPC/QtTest и путь compatibility helper к staging.
Никаких mock/debug методов в установленном плагине нет.

Проверено: неправильный PIN оставляет secure=true и сообщение ошибки;
правильный снимает lock; три повторных lock/unlock; short off ждёт secure;
short wake сохраняет lock; long (ожидание 700 ms для таймера 600 ms) вызывает
ровно одно меню, повтор press/release не переключает DPMS; long при lock
откладывает stock menu до успешного mock PAM. Питание читает fixture DSI-1
on/off, внешние wake/brightness/menu команды только пишут временный журнал.
Настоящие DPMS/logind, касания и Lua binds в Hyprland на телефоне не проверялись.

Аварийный выход вызван **настоящим bin/omarchy-shell lock unlock r7031**, с
удалённым WAYLAND_DISPLAY: wrapper нашёл сокет и session lock был снят.
Проверены live --undo/rescan, точный возврат shell.json; журнал host.log:
**0 TypeError / 0 ReferenceError**. `loginctl unlock-session` не заявляется:
обработчика Unlock в r7031 lock нет. Проверка crash/restart на Spacewar остаётся
владельцу; retained service требует restart только после разблокировки.
Снимок: [research/lock-v1.png](../../research/lock-v1.png), просмотрен визуально.
Для снимка использован оригинальный английский shell.json-каталог из того же
commit cce8b1c, переданный QA_ENGLISH_CATALOG (в package extract defaults нет).

Воспроизведение после tests/check.sh:

```sh
env LD_LIBRARY_PATH=/tmp/spacewar-mobile.YfwsWd/qa-tools/usr/lib \
  OMARCHY_QA_ROOT=/tmp/spacewar-mobile.YfwsWd/base/usr/share/omarchy \
  MOBILE_QA_ROOT="$PWD/pkg/nothing-spacewar-mobile-ui/usr/share/nothing-spacewar/mobile" \
  LABWC=/tmp/spacewar-mobile.YfwsWd/qa-tools/usr/bin/labwc \
  WLR_RANDR=/tmp/spacewar-mobile.YfwsWd/qa-tools/usr/bin/wlr-randr \
  QA_OUTPUT=/tmp/spacewar-lock-v1-qa \
  QA_ENGLISH_CATALOG=/tmp/spacewar-lock-en-shell.json \
  dbus-run-session python3 tests/headless_lock.py
```

QA_ENGLISH_CATALOG необязателен; без него upstream показывает ключи перевода.
Логи текущего прогона: `/tmp/spacewar-lock-check.log`,
`/tmp/spacewar-lock-v1-qa/{host,labwc,commands}.log`.

Принципы: prove-it-works — clicks и secure-state на собранном QML;
sequence-verifiable-units — проверка компонента, затем усиление guard и QA;
laziness-protocol — клон только lock, остальные панели остаются штатными;
fix-root-causes — работа внутри session-lock surface вместо попытки поднять OSK
над lock; guard проверяет исходники, а не строку версии.

---

# Проверки v3, 17.10.2026

Проверялся `nothing-spacewar-mobile-ui-0.3.0-1-any.pkg.tar.zst` из makepkg.
Телефон, активный desktop и `/usr/share/omarchy` не менялись.

`tests/check.sh`: makepkg --nodeps --force --noconfirm, **20 behavioral tests**,
luac, ShellCheck и qmllint Qt 6.12 — PASS. QML проверяется из собранного
staging с реальными Commons/Ui r7031. Один warning `unresolved-type` относится
к `Bluetooth.defaultAdapter` в установленном quickshell-bluetooth.qmltypes;
этот же API использует штатная Bluetooth Panel.qml:25. Warning не подавлен;
реальная загрузка шторки и Bluetooth panel проверены отдельно. Других новых
QML warnings и `Unable to assign ... QColor` в финальном прогоне нет.

Добавлены проверки диапазона яркости до внешней команды, штатного DND IPC,
чтения RU и недоступных сервисов, переключения OSK по Visible, отсутствующего
фонарика и повторяемого 0→1→0 на временном файле без внешних команд.
API Visible проверен по upstream [sm.puri.OSK0.xml](https://gitlab.gnome.org/World/Phosh/squeekboard/-/blob/main/data/dbus/sm.puri.OSK0.xml).

Headless r7031, labwc/pixman, **540×1200**: открытие шторки, три дополнительных
цикла hide/summon, анимация offset до 0, компактная высота 644 px,
restart, штатные панели, dock, switcher, live undo/rescan с точным возвратом
shell.json — PASS. Два журнала: **0 TypeError / 0 ReferenceError**.
Снимок финального собранного QML: [research/shade-v3.png](../../research/shade-v3.png),
проверен визуально. Логи: `/tmp/spacewar-mobile-v3-qa/host{,-restart}.log`.

Стенд запрещает изменять аппаратное состояние: helper возвращает фиксированные
RU, OSK скрыта, портрет, DND off, яркость 65%, фонарика нет. Это fixture для
вида шторки, не измерение телефона. Wi-Fi/SSID и Bluetooth читаются настоящими
сервисами хоста; PipeWire sink отсутствует, и ползунок показывает «Недоступна».
Аппаратные действия helper проверены с mock-командами; реальные касания,
свайп, удержание, аудиовыход, подсветку, фонарик и синхронизацию OSK на телефоне
проверяет владелец. В labwc не проверяется Hyprland/hyprgrass или Adreno capture.

Повторение: команды ниже из v2 с `QA_OUTPUT=/tmp/spacewar-mobile-v3-qa`.
Принципы: prove-it-works — собранный QML и реальный shell r7031;
sequence-verifiable-units — отдельные проверенные коммиты actions/UI/QA;
laziness-protocol — штатные сервисы и PanelSlider вместо копий;
fix-root-causes — неверный Color.menu.selected заменён существующим
selectedBackground, а не подавлением ошибки QColor.

---

# Проверки v2, 17.10.2026

Проверялся пакет `nothing-spacewar-mobile-ui-0.2.0-1-any.pkg.tar.zst`.
Ничего не устанавливалось на хост или телефон. Исходники Omarchy не менялись.

`tests/check.sh`: makepkg --nodeps --force --noconfirm, 15 behavioral tests,
luac -p (Lua 5.5.1), ShellCheck 0.11.0, qmllint Qt 6.12 — PASS.
--nodeps исключает установку runtime-зависимостей телефона на ноутбук;
это не доказательство разрешения зависимостей ARM rootfs. В собранном архиве
только два plugin manifest: shade и switcher; statusbar/home/Probe отсутствуют.

Setup и actions загружаются из собранного staging-артефакта. Во временном HOME
проверены setup/undo, повторный запуск, исходные байты после отката, права
журнала 0600, восстановление phone.lua с сохранением последующих правок,
частичная установка, отсутствие конфигов, конфликт каталога, невалидный JSON,
сохранность dock/idle/bar custom options и пользовательских изменений секций.
Штатный bar.id остаётся omarchy.bar, файлы bar-off не создаются.
Actions проверяют публичные IPC dock/apps и штатных панелей, Back по классу,
отсутствующие плагины, адрес окна и key-up, lock gate; внешние команды замоканы.

Qmllint проверяет упакованные QML с настоящими Commons r7031. Отключены только
uncreatable-type (платформенный PanelWindow) и missing-property (динамические
QObject theme tokens). Прочие категории включены; runtime проверен отдельно.

`tests/headless.py` запускает настоящий неизменённый `shell/shell.qml` r7031
из распакованного пакета. Compositor — отдельный labwc/wlroots 0.20.2, pixman,
540×1200; приватные HOME/XDG и D-Bus. Monitor-only UNIX IPC fixture сообщает
Quickshell Hyprland-монитор HEADLESS-1/scale 1: штатный OverlayWindow требует
эти метаданные и без них намеренно не показывает app grid. Это не настоящий
Hyprland и не проверка распознавания hyprgrass. Shell services/overlays отключены, кроме dock. Штатные bar-widget читают
доступные на хосте NetworkManager/Bluetooth/питание; переключения не выполнялись.
Helper в стенде запрещает внешние действия.

Исходный профиль повторяет телефон: штатная верхняя строка и временные
command-кнопки ✕/⌨/RU. Проверены enable через настоящий setup и явный
rescanPlugins при работающей оболочке, видимая
штатная панель 26 px сверху, шторка с 56 px кнопками, штатная сетка приложений,
перезапуск с включённым профилем, три Wayland окна, activate, close одного с
двумя оставшимися, summon/hide штатных четырёх панелей, живой --undo с rescan и точным возвратом исходного shell.json.
В обоих журналах host/host-restart — **0 TypeError и 0 ReferenceError**.
PNG statusbar/home/shade/switcher/stock-* просмотрены. В labwc нет window
screencopy: проверен fallback; Adreno capture требует телефона.

В ходе проверки воспроизведён TypeError в штатном Bar.qml:2410:
`Cannot read property 'pluginBarApiFor' of undefined (exception occurred during delayed function evaluation)`.
`WidgetHost.injectProps()` планируется через Qt.callLater и после уничтожения
bar обращается к `root` для custom command entry. В v2 command-кнопок в bar нет:
касание шторки — отдельная прозрачная поверхность над свободным центром.
Это устраняет триггер, не изменяя пакетный Bar.qml. Подтвердить, что единственная
ошибка после рестарта на телефоне была именно этой, без его журнала нельзя.

Допустимые предупреждения стенда: отсутствующие defaults/i18n в распакованном
пакете, PipeWire, portal, D-Bus и события Hyprland. Поэтому названия в штатной
сетке/панелях могут отображаться как ключи перевода. Проверка не подавляет
TypeError/ReferenceError и падает, если они встречаются в любом из двух логов.

Повторение из каталога пакета:

```sh
SHELLCHECK=/tmp/spacewar-mobile.YfwsWd/qa-tools/shellcheck-v0.11.0/shellcheck \
OMARCHY_QA_ROOT=/tmp/spacewar-mobile.YfwsWd/base/usr/share/omarchy tests/check.sh

env LD_LIBRARY_PATH=/tmp/spacewar-mobile.YfwsWd/qa-tools/usr/lib \
  OMARCHY_QA_ROOT=/tmp/spacewar-mobile.YfwsWd/base/usr/share/omarchy \
  MOBILE_QA_ROOT="$PWD/pkg/nothing-spacewar-mobile-ui/usr/share/nothing-spacewar/mobile" \
  LABWC=/tmp/spacewar-mobile.YfwsWd/qa-tools/usr/bin/labwc \
  WLR_RANDR=/tmp/spacewar-mobile.YfwsWd/qa-tools/usr/bin/wlr-randr \
  QA_OUTPUT=/tmp/spacewar-mobile-v2-qa \
  dbus-run-session python3 tests/headless.py
```

Принципы: prove-it-works — настоящий r7031 и собранный пакет;
sequence-verifiable-units — проверенные отдельные коммиты setup, UI и QA;
laziness-protocol — удалены копии bar/home и дубли сетевых сервисов;
fix-root-causes — найден отложенный вызов штатной панели, исключён конфликтующий
command entry вместо перехвата/подавления исключений. Телефонные проверки,
перечисленные в README, остаются владельцу; пароль и lock не модифицировались.
