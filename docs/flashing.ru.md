# План прошивки этапа 2: Omarchy

Прошивать только по «да» пользователя. Каждый шаг заканчивается проверкой, следующий начинается только после зелёной.

## Перед прошивкой
1. Сборка rootfs завершилась с `exit 0`, `SHA256SUMS` напечатан (`logs/rootfs-build.log`).
2. `pkexec tools/verify-image.sh /var/tmp/spacewar-build/stage2` — все пункты PASS.
3. Скопировать артефакты в папку пользователя для fastboot (без root): `pkexec install -m644 -o user /var/tmp/spacewar-build/stage2/{boot.img,spacewar-rootfs.sparse.img,SHA256SUMS} rollback/stage2/` и сверить `sha256sum -c`.
4. Наблюдатель `tools-watch-phone.sh` запущен (USB + Wi-Fi 192.168.1.x).
5. На телефоне pmOS (этап 1) открыта по Wi-Fi. Уйти в fastboot: `ssh … sudo reboot bootloader`, либо Power + громкость вниз.

## Прошивка
```
fastboot getvar current-slot                      # ожидается a
fastboot flash boot_a rollback/stage2/boot.img
fastboot flash boot_b rollback/stage2/boot.img
fastboot erase userdata && fastboot erase metadata
fastboot flash userdata rollback/stage2/spacewar-rootfs.sparse.img
fastboot set_active a && fastboot reboot
```
Не трогаем: `super`, `abl`, `xbl`, `vbmeta`, `modem`, `persist`, `fsg`, `modemst1/2`, `fsc`. `dtbo` и `vendor_boot` уже стёрты на этапе 1.

## Первая загрузка
- Ожидание: логотип, затем Hyprland с автовходом. Первая загрузка дольше: `growfs` расширяет ext4 на весь `userdata`, генерируются SSH-ключи хоста.
- Доступ: USB `172.16.42.1` (сервис reprobe + гаджет), запасной — Wi-Fi (те же сети, что в pmOS), SSH-ключ `~/.ssh/id_ed25519_spacewar`.
- Проверка: `tools/hw-check-omarchy.sh`.

## Если не загрузилось
| Симптом | Действие |
|---|---|
| Сразу fastboot или «Load Error» | `fastboot boot rollback/pmos/boot-debug.img` → debug-shell pmOS проверяет, видны ли разделы; затем откат boot |
| Логотип, нет USB и Wi-Fi > 3 мин | Power + громкость вниз → fastboot; повтор с отладочным cmdline (`console=tty0`, без `quiet`) |
| Загрузилось, но чёрный экран | SSH по USB/Wi-Fi, `journalctl -b`, `hyprctl`; телефон доступен |

## Откат
- **На pmOS этапа 1:** `fastboot flash boot_a/boot_b rollback/pmos/boot-fixed.img`, затем прошить сохранённый rootfs pmOS (`pmbootstrap flasher flash_rootfs`).
- **На Nothing OS:** `rollback/boot/{boot,dtbo,vendor_boot,vbmeta}.img` в оба слота, затем `fastboot -w`. `super` не трогали.
