# Omarchy на Nothing Phone (1) «Spacewar»

Настоящий Omarchy (Arch Linux ARM + Hyprland + официальные пакеты Omarchy) нативно на Nothing Phone (1): SM7325 / sc7280, Adreno 642L, экран 1080x2400. Конечная цель — телефон со звонками.
Подробное состояние и как продолжить работу.

## Состояние

| Подсистема | Состояние |
|---|---|
| Загрузка | ABL → boot.img v2 с appended DTB, слоты A/B, rootfs на `userdata` (sda10) |
| Ядро | `pkgs/linux-sc7280` 7.2.9: sc7280-mainline b90de19 + 40 патчей woodyst + 0041 voice; Landlock включён |
| Omarchy | `omarchy-dev` r7031 из pkgs.omarchy.org/edge/aarch64. Стабильный 4.0.4 ломается на Qt 6.12 (#14553) |
| Hyprland | 0.56.2, Lua-конфиг |
| Работает | GPU, тач, USB-сеть (NCM), Wi-Fi, Bluetooth, звук через PipeWire в оба динамика, фонарик, стек модема (нужна живая SIM) |
| Мобильный интерфейс | `nothing-spacewar-mobile-shell` 0.3.x: домашний экран и сетка Derek Ross, 105 виджетов Simon Schubert, шторка за пальцем, жесты снизу (домой и недавние), «назад» с края, наша RU/EN клавиатура |
| Нет | камеры, GPS, датчики, звонки (не проверены), блокировка по PIN, энергосбережение |

Как решались проблемы: `docs/notes.md`.

## С чего начать

1. `docs/notes.md`: что и как решалось.
2. `docs/flashing.ru.md`: прошивка и откат.
3. Чек-лист проверки на телефоне: `pkgs/nothing-spacewar-mobile-shell/VALIDATION.md`.

## Доступ к телефону

- SSH по USB: `user@172.16.42.1`, ключ `~/.ssh/id_ed25519_spacewar`, `UserKnownHostsFile=~/.ssh/known_hosts_spacewar`. По Wi-Fi — адрес из DHCP роутера.
- Пароль пользователя по умолчанию задаёт `tools/build-rootfs.sh` (тестовый PIN). Смените его и включите вход по SSH только по ключу.
- Hyprland из SSH: `XDG_RUNTIME_DIR=/run/user/$(id -u)`, `HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)`, `WAYLAND_DISPLAY=wayland-1`.

## Структура

| Путь | Что там |
|---|---|
| `pkgs/linux-sc7280` | ядро (PKGBUILD + серия патчей), кросс-сборка clang LLVM=1 на ноутбуке |
| `pkgs/firmware-nothing-spacewar`, `pkgs/nothing-spacewar-boot`, `pkgs/nothing-spacewar-ucm` | прошивки, boot.img и USB/audio reprobe, UCM + WirePlumber (S16LE) |
| `pkgs/modem/*` | qrtr, rmtfs (только `-r`), tqftpserv, hexagonrpcd, 81voltd, msm-modem, q6voiced (не включать), dummystreamhack, bootmac. Собраны на телефоне (.pkg.tar.xz) |
| `pkgs/nothing-spacewar-mobile-shell` | текущий мобильный интерфейс: плагины штатной оболочки Omarchy |
| `pkgs/nothing-spacewar-mobile-ui` | прежний слой v3, заменён; для отката |
| `pkgs/omarchy-osk-spacewar` | пакет нашей клавиатуры. Исходник форка: отдельный репозиторий `omarchy-osk-spacewar` (см. ниже) |
| `pkgs/hyprgrass` | плагин жестов, больше не используется |
| `tools/build-rootfs.sh`, `tools/verify-image.sh`, `tools/export-image.sh` | сборка образа rootfs+boot, проверка (132 пункта), экспорт с хешами |
| `device-info/` | getprop и разделы стоковой прошивки |

Образы, бэкапы и прошивки производителя в репозиторий не входят: прошивки берутся с вашего телефона.

## Сборка и установка

- Образ: `sudo tools/build-rootfs.sh <имя>` → `/var/tmp/spacewar-build/<имя>`; `tools/verify-image.sh`; `tools/export-image.sh` → `rollback/<имя>`.
- Прошивка: `docs/flashing.ru.md`. Шьются только `boot_a/boot_b` и `userdata`. Никогда: `super`, `abl`, `xbl`, `vbmeta`, `modem`, `persist`, `fsg`, `modemst1/2`, `fsc`.
- Пакеты интерфейса (`arch=any`) собираются `makepkg` на ноутбуке и ставятся на телефоне `pacman -U`, затем `spacewar-shell-setup` и перезапуск оболочки. Если удаляется плагин Hyprland, нужен перезапуск сеанса (`systemctl restart sddm`), а не `hyprctl reload`.

## Откат

- Интерфейс: `spacewar-shell-setup --undo` возвращает настройки из архива, который setup делает перед изменениями.
- Система: прошить предыдущий образ из `rollback/<имя>` (его кладёт `tools/export-image.sh`) или стоковый Nothing OS (Spacewar_V3.2 из nothing_archive).

## Источники и лицензии

Мобильная оболочка собрана из [derekross/omarchy-mobile](https://github.com/derekross/omarchy-mobile) (MIT, GPL для части клавиатуры), механики жестов [SimonSchubert/omarchy-mobile](https://github.com/SimonSchubert/omarchy-mobile) и [Cube-Oakley/omarchy-mobile](https://github.com/Cube-Oakley/omarchy-mobile), виджетов [SimonSchubert/omarchy-widgets](https://github.com/SimonSchubert/omarchy-widgets). Подробно: `pkgs/nothing-spacewar-mobile-shell/ATTRIBUTION.md`. Клавиатура — форк [yeutterg/omarchy-on-screen-keyboard](https://github.com/yeutterg/omarchy-on-screen-keyboard). Ядро — sc7280-mainline и патчи postmarketOS/woodyst.
