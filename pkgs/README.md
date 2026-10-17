# Nothing Phone (1): пакеты Arch Linux ARM

Это начальный порт пакетов, не готовый образ ОС. Телефон и разделы не меняются;
`spacewar-mkbootimg` пишет только файл, pacman-хук — `/boot/boot.img`.

## Источники и раскладка

- `linux-sc7280` / `linux-sc7280-headers`: [APKBUILD](../ref/linux-postmarketos-qcom-sc7280/APKBUILD),
  неизменённая копия [конфига](../ref/linux-postmarketos-qcom-sc7280/config-postmarketos-qcom-sc7280.aarch64),
  снимок [`b90de19446e8`](https://github.com/sc7280-mainline/linux/commit/b90de19446e8bdaf222380b5a1d230c006d2912a)
  ветки `sc7280-7.2.y` (версия пакета `7.2.9.r7.gb90de19`).
  В `prepare()` применяется [серия из 40 патчей woodyst](linux-sc7280/patches/SERIES.md);
  там же статусы всех 52 исходных патчей, пропуски, проверки и рекомендации Kconfig.
  DTB `sm7325-nothing-spacewar.dtb` собран clang/LLD 23.1.3. Новые драйверы
  по умолчанию выключены в исходном конфиге; расширения CS voice/SCO требуют
  отдельного переноса конфликтного стека r93. Аппаратная работа не проверялась.
  Модули: `/usr/lib/modules/$kernver`, ядро: `/boot/Image`, `/boot/Image.gz`,
  `/boot/vmlinuz` (gzip с дополнением BSS), DTB: `/boot/dtbs/qcom/sm7325-nothing-spacewar.dtb`.
  Суффикс версии `-1-sc7280` отделяет модули этого пакета; `olddefconfig` адаптирует
  исходный LLVM-конфиг к выбранному GCC. Структура headers и раскладка основаны на
  [Arch Linux ARM linux-aarch64](https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/linux-aarch64/PKGBUILD).
  Конфликт с `linux-aarch64` намеренный: общие `/boot/Image` и дерево DTB.
- `firmware-nothing-spacewar`: [APKBUILD](../ref/firmware-nothing-spacewar/APKBUILD),
  [`cc01a8900344afb8a8e254f7bb607d1b4affeb3c`](https://github.com/mainlining/firmware-nothing-spacewar/tree/cc01a8900344afb8a8e254f7bb607d1b4affeb3c).
  Upstream `lib/firmware` перенесён в `/usr/lib/firmware` (в Arch `/lib` — ссылка),
  `usr/share/qcom` сохранён: это данные DSP/сенсоров, их нельзя выбрасывать.
  SHA-512 firmware-архива и конфига взяты из `ref/`; SHA-512 снимка ядра
  и итоговых патчей рассчитаны по скачанным/экспортированным файлам. Прошивки проприетарные,
  условия перераспространения необходимо отдельно проверить перед публикацией пакетов.
- `nothing-spacewar-boot`: точные копии [udev-правила](../ref/device-nothing-spacewar/81-libssc-nothing-spacewar.rules)
  и [deviceinfo](../ref/device-nothing-spacewar/deviceinfo); пять имён модулей из
  [modules-initfs](../ref/device-nothing-spacewar/modules-initfs) добавляются через
  `/etc/mkinitcpio.conf.d/spacewar.conf` (встроенный `msm` — допустим).

## boot.img и cmdline

В `spacewar-mkbootimg` перед заменой образа `sync FILE` из coreutils сохраняет данные
и метаданные временного файла. После rename `sync -f DIRECTORY` синхронизирует
всю файловую систему назначения, включая изменение каталога; это также сохраняет
перенос из временного подкаталога. Python и новые зависимости для синхронизации не нужны.
Ошибка любого sync завершает команду без сообщения об успехе. Отключение питания
и гарантии конкретного накопителя этой проверкой не моделировались.

Генерации в одном каталоге вывода сериализуются через `flock` из util-linux
на самом каталоге. Под блокировкой следующий запуск удаляет оставшиеся после
аварии каталоги текущего владельца `.spacewar-mkbootimg.` с шестью буквами/цифрами
в суффиксе. Проверяются только непосредственные подкаталоги назначения, без
перехода по символьным ссылкам. Активная генерация удерживает ту же блокировку.

Параметр `--deviceinfo FILE` исполняет файл как shell-код через `source`; передавайте
только доверенный файл. По умолчанию используется упакованный
`/usr/share/nothing-spacewar/deviceinfo`. Все адреса читаются из него:
header **2**, pagesize **4096**, base **0x00000000**, kernel **0x00008000**,
ramdisk **0x01000000**, second **0x00000000**, tags **0x00000100**, DTB **0x01f00000**.
Скрипт не использует `flash_kernel_on_update`: прошивка разделов не предусмотрена.

Проверены исходники [boot-deploy-functions.sh, commit 4529ed6](https://gitlab.com/postmarketOS/boot-deploy/-/blob/4529ed643b65d68645fd04c51f65bef3e4986586/boot-deploy-functions.sh):
`append_or_copy_dtb()` конкатенирует сжатое ядро и сырой DTB;
`create_bootimg()` при header v2 дополнительно передаёт `--dtb` и `--dtb_offset`.
По [Makefile.zboot этого тега](https://github.com/sc7280-mainline/linux/blob/v7.2.9-sc7280/drivers/firmware/efi/libstub/Makefile.zboot)
`vmlinuz` — gzip от Image, дополненного до размера из младших 32 бит `image_size`
(смещение 16). Скрипт воспроизводит этот шаг из `/boot/Image`, затем добавляет DTB.
Это отличается от простого gzip исходного Image.

В локальном `deviceinfo` нет `deviceinfo_kernel_cmdline`. В проверенной версии
boot-deploy `get_cmdline()` объединяет deviceinfo и append, добавляя UUID/опции из
fstab/crypttab как `${distro_prefix}_root_uuid`, `_boot_uuid`, `_rootfsopts`.
[pmbootstrap, commit 7954019, flasher/variables.py](https://gitlab.com/postmarketOS/pmbootstrap/-/blob/7954019f0ca6106a0fc20deb472ce56392615b11/pmb/flasher/variables.py)
также берёт `kernel_cmdline` или пустую строку; скрытой cmdline устройства там нет.
[Новая документация pmOS](https://docs.postmarketos.org/pmaports/main/kernel-cmdline.html)
описывает переход на `generate-kernel-cmdline`; это не задаёт root для Arch.
Параметры `pmos_*` обслуживает initramfs pmOS, поэтому здесь нужен явный
`/etc/kernel/cmdline` для mkinitcpio, например **после выбора целевого rootfs**:

```text
root=UUID=<UUID-целевой-rootfs> rw rootwait
```

UUID не угадывается и не читается с компьютера сборки. Файл — одна строка;
для шифрования/другой ФС нужны соответствующие HOOKS, MODULES и параметры root.
При сборке initramfs вне телефона проверьте `autodetect`: он видит хост, а не телефон;
добавьте нужные модули явно или уберите этот HOOK. UFS/QCOM UFS PHY и ext4 в ref
встроены в ядро; f2fs — модуль.

```sh
# В установленной целевой системе, после настройки cmdline и mkinitcpio:
spacewar-mkbootimg --rebuild-initramfs
# Или из уже подготовленных файлов; можно запускать без root в рабочем каталоге:
spacewar-mkbootimg --image ./Image --dtb ./sm7325-nothing-spacewar.dtb \
  --initramfs ./initramfs.img --cmdline ./cmdline \
  --deviceinfo ./pkgs/nothing-spacewar-boot/deviceinfo --output ./boot.img
```

Хук `99-spacewar-boot.hook` выполняется после стандартного mkinitcpio-хука при
установке/обновлении ядра, файлов пакета устройства или mkinitcpio, а также при
изменениях общих входов штатного хука (firmware, initcpio и другие пути, включая
удаление). Он явно пересобирает
initramfs для упакованного `kernel.release`, чтобы ошибка предыдущего хука не
привела к упаковке старого ramdisk. Поэтому возможен повторный запуск mkinitcpio.
Без cmdline хук сообщит об ошибке; pacman уже установит пакеты, затем надо настроить
cmdline и повторить команду. При ошибке генерации существующий boot.img сохраняется;
замена готового файла атомарная. `/boot` должен быть смонтирован до обновления.

## Сборка

Предпочтительно обычный пользователь внутри **заранее подготовленного aarch64-chroot**
Arch Linux ARM с base-devel, зависимостями `makedepends` и `qemu-user-static`
на x86_64 (нужны заранее настроенные binfmt либо запуск aarch64 shell через
qemu-aarch64-static). Подготовка chroot/binfmt здесь не выполняется и обычно требует
администратора. Внутри chroot `CARCH=aarch64`, инструменты и headers получаются ARM64:

```sh
cd pkgs/linux-sc7280
makepkg --verifysource
makepkg
# Аналогично в pkgs/firmware-nothing-spacewar и pkgs/nothing-spacewar-boot.
```

Без chroot на x86_64 установите зависимости сборки для хоста и GNU toolchain
`aarch64-linux-gnu-gcc`/binutils. В `_kmake` всегда `ARCH=arm64`; при
`CARCH != aarch64` добавляется `CROSS_COMPILE=aarch64-linux-gnu-`.
Можно также явно передать `CROSS_COMPILE` при целевом CARCH=aarch64.
Чтобы выходные пакеты оставались aarch64, используйте отдельный makepkg-config:

```sh
# Из корня репозитория; все создаваемые файлы остаются внутри проекта.
mkdir -p .work
cp /etc/makepkg.conf .work/makepkg-cross.conf
cat >> .work/makepkg-cross.conf <<'CONFIG'
CARCH=aarch64
CHOST=aarch64-linux-gnu
PKGEXT='.pkg.tar.zst'
CONFIG
cd pkgs/linux-sc7280
CROSS_COMPILE=aarch64-linux-gnu- makepkg --config ../../.work/makepkg-cross.conf
```

Makepkg берёт архитектуру готового пакета из CARCH. Поэтому здесь CARCH=aarch64
и явно указан CROSS_COMPILE; один `--ignorearch` с CARCH=x86_64 ошибочно пометил бы
ARM64-пакеты как x86_64. CHOST описывает цель; HOSTCC остаётся нативным gcc.
Нативные host-tools внутри **headers кросс-сборки будут x86_64**: для DKMS на телефоне
соберите headers нативно в aarch64-chroot (или пересоберите host-tools там).
Само ядро/модули кросс-сборки предназначены для ARM64. Пакет boot не содержит ELF,
он, как и firmware, имеет `arch=('any')` и упаковывается на x86 без `--ignorearch`.
`makepkg -s` требует доступа к pacman; без sudo зависимости должны быть подготовлены заранее.

## Чего ещё не хватает

Проверено 2026-10-17 по базам [ALARM core](https://de3.mirror.archlinuxarm.org/aarch64/core/core.db),
[extra](https://de3.mirror.archlinuxarm.org/aarch64/extra/extra.db),
[списку файлов core](https://de3.mirror.archlinuxarm.org/aarch64/core/core.files)
и AUR RPC. Отсутствие ниже означает «не найдено в этих базах/поиске», а не отсутствие
любых сторонних портов.

| Компонент pmOS | Найдено и оставшаяся работа |
| --- | --- |
| hexagonrpcd | В core/extra нет; [AUR hexagonrpcd](https://aur.archlinux.org/packages/hexagonrpcd) 0.3.2.r0.gb7eff23-1 есть, включая systemd units. Проверить ARM64-сборку, FastRPC права и запуск DSP для spacewar. AUR ошибочно помечает компилируемый демон как `any`; нужен review, это не бинарный пакет ALARM. |
| qbootctl | В core/extra нет; [AUR qbootctl](https://aur.archlinux.org/packages/qbootctl) 0.2.2-1 есть. Проверить сборку aarch64 и сервис mark-boot-successful, который включает [soc-qcom-qbootctl](../ref/soc-qcom/APKBUILD); автоматически сервисы здесь не включаются. |
| firmware-qcom-adreno-a660 | Имя из Alpine не переносится буквально: ALARM core `linux-firmware-qcom` 20260916-1 содержит `qcom/a660_gmu.bin`, `qcom/a660_sqe.fw`. Device-specific `qcom/sm7325/nothing/spacewar/a660_zap.mbn` уже в firmware-nothing-spacewar. Отдельный порт a660-пакета не нужен. |
| soc-qcom-modem | Это метапакет pmOS: [ref/soc-qcom/APKBUILD](../ref/soc-qcom/APKBUILD) требует `81voltd`, `msm-modem`, `msm-modem-uim-selection`, `q6voiced`. Самого метапакета и демонов нет в проверенных core/extra; поиск AUR [msm-modem](https://aur.archlinux.org/rpc/v5/search/msm-modem), [q6voiced](https://aur.archlinux.org/rpc/v5/search/q6voiced), [81voltd](https://aur.archlinux.org/rpc/v5/search/81voltd) вернул 0. Нужны PKGBUILD-ы и systemd-интеграция, включая [modem-gnss.service](../ref/soc-qcom/modem-gnss.service), настройка ModemManager и UIM. |

Дополнительно ещё не портированы настройки `soc-qcom`, `make-dynpart-mappings`,
`alsa-ucm-conf-qcom-sc7280` из `ref/`; наличие firmware само по себе не обеспечивает
звук, звонки, сенсоры и Wi-Fi. `android-tools` в extra содержит инструменты Android;
именно его требует пакет boot для `mkbootimg`. Разметка, AVB/A-B, размер boot-раздела,
динамические разделы и реальная загрузка требуют отдельной проверки на устройстве.
Полная сборка ядра и запуск на телефоне в рамках этой задачи не выполняются.

## Проверки без сборки ядра

`makepkg --verifysource --ignorearch` выполнен для всех трёх PKGBUILD: все SHA-512
совпали. Firmware и boot упакованы через `makepkg --nodeps` без установки;
полное ядро/headers не собирались, `namcap` и GNU ARM64-кросс-компилятор на хосте отсутствуют.
Для новой серии отдельно выполнены LLVM `olddefconfig`, сборка DTB и проверка
затронутых объектов; точные результаты — в [SERIES.md](linux-sc7280/patches/SERIES.md).
`bash -n` проверяет синтаксис PKGBUILD и скрипта. Воспроизводимый тест с настоящими
`mkbootimg`/`unpack_bootimg` (из android-tools), синтетическими Image/DTB/initramfs:

```sh
python pkgs/tests/test-bootimg.py
```

Он проверяет header/offsets, gzip с дополнением нулями, оба экземпляра DTB,
ramdisk/cmdline и сохранность предыдущего boot.img при ошибках. Это проверка формата,
не доказательство загрузки на телефоне.
