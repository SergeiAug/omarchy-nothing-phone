# woodyst → sc7280-7.2.y

Проверено 17.10.2026. База: [`b90de19446e8bdaf222380b5a1d230c006d2912a`](https://github.com/sc7280-mainline/linux/commit/b90de19446e8bdaf222380b5a1d230c006d2912a),
голова `sc7280-7.2.y` на эту дату, на 7 коммитов впереди `v7.2.9-sc7280`.
Исходная серия: [woodyst/spacewar-pmos `a975d531a7365194752fa715db15d32db89b5e4e`](https://github.com/woodyst/spacewar-pmos/tree/a975d531a7365194752fa715db15d32db89b5e4e/kernel), 52 патча для 7.2.2.
Учтён предыдущий анализ [grok-final-verified.md, раздел 2](../../../research/grok-final-verified.md#2-woodyst-против-v729-sc7280--все-52-патча).

Каждый исходный патч проверен и последовательно передан `git am --3way` в shallow clone
(`gh repo clone sc7280-mainline/linux .work/linux -- --depth 50 --branch sc7280-7.2.y`).
«applied clean» означает успешный прямой `git apply --check` и `git am --3way`;
«applied with 3way» — автоматическое слияние после неудачи прямой проверки.
Нехватка старого blob в shallow history сама по себе не считалась логическим конфликтом:
для 0006/0050 разобраны rejects и механически перенесены только изменённые строки.

Итог попыток: **42 applied clean, 0 applied with 3way, 10 conflict, 0 already upstream**.
Из конфликтных механически разрешены 0006 и 0050, остальные 8 пропущены.
Ещё 4 чисто применившихся патча исключены из-за зависимостей: 0010, 0019, 0022, 0031.
После сборочной проверки механически адаптирован чисто применившийся 0013.
**Экспортировано 40 патчей: 37 без ручной адаптации и 3 с механической адаптацией;
всего пропущено 12.** Счётчик пропущенных пересекается со статусами попыток.

Итоговая история собрана заново от базы без исключённых коммитов; файлы получены
`git format-patch --no-signature b90de19446e8bdaf222380b5a1d230c006d2912a` и применяются в порядке `_patches` в PKGBUILD.
Нумерация экспортированных файлов сквозная 0001–0040, исходные номера указаны ниже.
Лицензия изменений — GPL-2.0; авторы `From:` и списки `Signed-off-by:` сохранены
(проверены для всех 40 файлов), дополнительные подписи не добавлялись.

## Голос: общий стек q6voice вместо surya

После исходных **40 патчей woodyst** добавлен один наш: итого **41 патч** в PKGBUILD.
[0041-arm64-dts-qcom-sm7325-nothing-spacewar-add-q6voice-r.patch](0041-arm64-dts-qcom-sm7325-nothing-spacewar-add-q6voice-r.patch),
коммит ядра `275a8467dcde0a836a3b54d1cbec52e6b9959ed4`, автор из локального git:
Sergey Ok <zdepat@gmail.com>. Дополнительный Signed-off-by не добавлялся.

Образец — dubai `6266f398f6a46df5df3a9908b12a2fbf3013f689`
(AuthorDate 01.08.2026, CommitDate 29.09.2026) и FP5 из той же базы.
В Spacewar include q6voice и включённые q6cvp/q6cvs/q6mvm уже внесены 0010;
0041 добавляет `q6voicedai/dai@1` и заменяет CS-Voice FE на VoiceMMode1.
Старый CS-Voice capture mixer общего стека не поддерживает codec-DMA TX.
Драйверы surya, calibration/volume-патчи не импортировались; ранее пропущенные
патчи остаются пропущенными. Прежние сохранённые Bluetooth-заготовки не менялись.

Адаптация портов: Spacewar — **PRIMARY_MI2S_RX → два TFA9873**
(Earpiece channel 0, Speaker channel 1), **TX_CODEC_DMA_TX_3 ← WCD9385**;
dubai — SENARY_MI2S_RX/AW88261/WCD9375, FP5 — QUINARY_MI2S_RX/AW88261/WCD9385.
Оба нужных Spacewar маршрута уже есть в `sound/soc/qcom/qdsp6/q6voice-dai.c`:
TX `:268,326,364`, RX `:279,329,375,382`. Драйверный код не добавлялся.
**Отдельная недостающая функция:** RX_CODEC_DMA_RX_0 для WCD/проводных наушников
не имеет voice RX mixer/routes; потребует согласованного расширения q6voice-dai
и проверки DSP/AFE/CVP. Основной разговорный динамик Spacewar подключён к MI2S,
так что отсутствие codec-DMA RX не блокирует предложенный тракт.

UCM-черновик и подробные ссылки файл:строка:
[../../nothing-spacewar-ucm/README.md](../../nothing-spacewar-ucm/README.md).
Он использует реальные VoiceMMode1 mixer names, Earpiece/Speaker и Mic1,
без вымышленных Voice Calibration/Voice Rx/Voice Tx и SLIMBUS_7 controls.
**Не проверено на телефоне.** Как у FP5/dubai в sc7280 UCM, оба направления
voice PCM открывает dummystreamhack; отдельный q6voiced для этого способа не нужен.
Номер PCM 3 предположен по порядку FE и должен быть проверен на устройстве.

Конфиг пакета не менялся: `CONFIG_SND_SOC_QDSP6_Q6VOICE=m` и
`CONFIG_SND_SOC_QDSP6_Q6VOICE_DAI=m` (`config-postmarketos-qcom-sc7280.aarch64:5460–5461`).
Отдельных опций q6cvp/q6cvs/q6mvm нет: все три объекта включаются через Q6VOICE
(`sound/soc/qcom/qdsp6/Makefile:14–16`). Недостающих CONFIG для выбранного стека нет.

Проверка 17.10.2026 после копирования пакетного конфига и `olddefconfig`:

- `make ARCH=arm64 LLVM=1 qcom/sm7325-nothing-spacewar.dtb` до/после успешен.
  В обоих запусках принудительно выполнен DTC (до — удалён старый DTB, после —
  изменён DTS); warnings/errors: **0 / 0**, новых предупреждений нет.
  Использован `.work/kernel-make` с локальными LLD/bc и LD_LIBRARY_PATH, без sudo.
- Новый DTB: **152728 байт**, SHA-256
  `9b322f11c1d91fa5751b9e4531874448df1c56b068dc8e67586bebb6396ea051`.
- Журналы: `.work/voice-logs/dtb-before.log`, `dtb-after.log`, `olddefconfig.log`.
- UCM: оба файла синтаксически разобраны `snd_config_load` из libasound;
  это не проверка контролов, UCM expansion или исполнения sequences на карте.
- `makepkg --verifysource --ignorearch`: все **44 SHA-512** совпали
  (архив, конфиг, preset, 41 патч). `bash -n PKGBUILD` успешен.
- `makepkg --nobuild --nodeps --ignorearch` в новом `.work/voice-package-build`
  распаковал чистый архив, применил все 41 патч и выполнил `olddefconfig`.
  Итоговый Spacewar DTS побайтно совпадает с коммитом ядра.
  Журнал: `.work/voice-logs/prepare-clean.log`.
- Полное ядро, DT-schema и аппаратные звонки не проверялись. Риски: firmware,
  топологии/эхо, уровень/тишина микрофона, отсутствие DSP volume/mute,
  номера PCM и интеграция dummystreamhack/HiFi. Звонки не объявляются рабочими.

## Результаты всех 52 патчей

| Исходный патч | Статус попытки | Итог / комментарий |
| --- | --- | --- |
| [0001](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0001-arm64-dts-qcom-sm7325-nothing-spacewar-enable-WCD9385-audio.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: enable WCD9385 audio (adapted to 7.2.2) | applied clean | [0001-arm64-dts-qcom-sm7325-nothing-spacewar-enable-WCD938.patch](0001-arm64-dts-qcom-sm7325-nothing-spacewar-enable-WCD938.patch). Без ручных изменений. |
| [0002](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0002-FROMLIST-arm64-dts-qcom-sm7325-nothing-spacewar-Add-.patch) — FROMLIST: arm64: dts: qcom: sm7325-nothing-spacewar: Add ath11k calibration-variant | applied clean | [0002-FROMLIST-arm64-dts-qcom-sm7325-nothing-spacewar-Add-.patch](0002-FROMLIST-arm64-dts-qcom-sm7325-nothing-spacewar-Add-.patch). Без ручных изменений. |
| [0003](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0003-FROMLIST-drivers-media-i2c-s5kjn1-Add-support-for-19.patch) — FROMLIST: drivers: media: i2c: s5kjn1: Add support for 19.2MHz MCLK | applied clean | [0003-FROMLIST-drivers-media-i2c-s5kjn1-Add-support-for-19.patch](0003-FROMLIST-drivers-media-i2c-s5kjn1-Add-support-for-19.patch). Без ручных изменений. |
| [0004](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0004-FROMLIST-RFT-dt-bindings-media-i2c-dw9719-Document-D.patch) — FROMLIST RFT: dt-bindings: media: i2c: dw9719: Document DW9800W | applied clean | [0004-FROMLIST-RFT-dt-bindings-media-i2c-dw9719-Document-D.patch](0004-FROMLIST-RFT-dt-bindings-media-i2c-dw9719-Document-D.patch). Без ручных изменений. |
| [0005](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0005-FROMLIST-RFT-media-i2c-dw9719-Add-DW9800W-support.patch) — FROMLIST RFT: media: i2c: dw9719: Add DW9800W support | applied clean | [0005-FROMLIST-RFT-media-i2c-dw9719-Add-DW9800W-support.patch](0005-FROMLIST-RFT-media-i2c-dw9719-Add-DW9800W-support.patch). Без ручных изменений. |
| [0006](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0006-FROMLIST-RFT-arm64-dts-qcom-sm7325-nothing-spacewar-.patch) — FROMLIST RFT: arm64: dts: qcom: sm7325-nothing-spacewar: Add UW camera actuator | conflict → resolved mechanically | [0006-FROMLIST-RFT-arm64-dts-qcom-sm7325-nothing-spacewar-.patch](0006-FROMLIST-RFT-arm64-dts-qcom-sm7325-nothing-spacewar-.patch). Механически: в базе снята метка camu_s5kjn1 у camera@2d; actuator и lens-focus перенесены без изменения логики. |
| [0007](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0007-arm64-dts-qcom-sm7325-nothing-spacewar-tfa9873-stereo.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: give each TFA9873 its own channel and name prefix | applied clean | [0007-arm64-dts-qcom-sm7325-nothing-spacewar-give-each-TFA.patch](0007-arm64-dts-qcom-sm7325-nothing-spacewar-give-each-TFA.patch). Без ручных изменений. |
| [0008](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0008-ASoC-qdsp6-q6voice-import-the-CS-voice-call-stack-fr.patch) — ASoC: qdsp6: q6voice: import the CS voice call stack from surya (r93) | conflict → skipped | Немеханический add/add: уже существуют 12 файлов q6voice/q6cvp/q6cvs/q6mvm и dt-binding, но импорт r93 меняет API, calibration/session/routing и удаляет VOICEMMODE1 ID; повторный импорт дублирует Kconfig/Makefile. Нужен отдельный перенос логики. |
| [0009](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0009-ASoC-qdsp6-AFE-SLIMBUS_7-port-voice-routing-custom-t.patch) — ASoC: qdsp6: AFE SLIMBUS_7 port, voice routing, custom topologies and ADM/ASM changes from surya (r93) | conflict → skipped | Конфликт q6core.c при регистрации/снятии custom topologies; q6routing дополнительно вызывает отсутствующие без 0008 q6voice_incall_record_route/playback_route. Нужен согласованный перенос со стеком r93, частичный патч не экспортируется. |
| [0010](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0010-ASoC-qcom-sm8250-Bluetooth-SCO-over-SLIMbus-links-an.patch) — ASoC: qcom: sm8250: Bluetooth SCO over SLIMbus links and voice support from surya (r93) | applied clean → skipped | Применился чисто, но исключён: common.c использует VOICE_PLAYBACK_TX, sm8250.c — SLIMBUS_7_RX/TX из пропущенного 0009; без него объекты не компилируются. |
| [0011](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0011-Bluetooth-hci_qca-SCO-offload-changes-from-surya-r93.patch) — Bluetooth: hci_qca: SCO offload changes from surya (r93) | applied clean | [0008-Bluetooth-hci_qca-SCO-offload-changes-from-surya-r93.patch](0008-Bluetooth-hci_qca-SCO-offload-changes-from-surya-r93.patch). Без ручных изменений. |
| [0012](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0012-slimbus-qcom-ngd-ctrl-stream-channel-removal-and-rob.patch) — slimbus: qcom-ngd-ctrl: stream channel removal and robustness fixes from surya (r93) | applied clean | [0009-slimbus-qcom-ngd-ctrl-stream-channel-removal-and-rob.patch](0009-slimbus-qcom-ngd-ctrl-stream-channel-removal-and-rob.patch). Без ручных изменений. |
| [0013](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0013-arm64-dts-qcom-sm7325-nothing-spacewar-wire-up-q6voi.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: wire up q6voice CS voice call audio | applied clean → adapted after DTB check | [0010-arm64-dts-qcom-sm7325-nothing-spacewar-wire-up-q6voi.patch](0010-arm64-dts-qcom-sm7325-nothing-spacewar-wire-up-q6voi.patch). Применился чисто; DTB выявил duplicate labels q6mvm/q6cvs/q6cvp/q6voicedai: определения уже есть в kodiak.dtsi (disabled). Механическая адаптация: включены существующие &q6mvm/&q6cvs/&q6cvp, сохранены FE и #sound-dai-cells=1 из базы. |
| [0014](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0014-ASoC-codecs-tfa9872-add-an-output-switch-to-power-do.patch) — ASoC: codecs: tfa9872: add an output switch to power down one amplifier | applied clean | [0011-ASoC-codecs-tfa9872-add-an-output-switch-to-power-do.patch](0011-ASoC-codecs-tfa9872-add-an-output-switch-to-power-do.patch). Без ручных изменений. |
| [0015](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0015-slimbus-no-aplazar-el-sondeo-si-el-dispositivo-aun-n.patch) — slimbus: no aplazar el sondeo si el dispositivo aun no tiene direccion | applied clean | [0012-slimbus-no-aplazar-el-sondeo-si-el-dispositivo-aun-n.patch](0012-slimbus-no-aplazar-el-sondeo-si-el-dispositivo-aun-n.patch). Без ручных изменений. |
| [0016](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0016-ASoC-codecs-add-the-WCN399x-Bluetooth-SLIMBus-audio-.patch) — ASoC: codecs: add the WCN399x Bluetooth SLIMBus audio driver | applied clean | [0013-ASoC-codecs-add-the-WCN399x-Bluetooth-SLIMBus-audio-.patch](0013-ASoC-codecs-add-the-WCN399x-Bluetooth-SLIMBus-audio-.patch). Без ручных изменений. |
| [0017](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0017-ASoC-wcn-bt-slim-stop-pinning-the-SLIMBus-controller.patch) — ASoC: wcn-bt-slim: stop pinning the SLIMBus controller awake | applied clean | [0014-ASoC-wcn-bt-slim-stop-pinning-the-SLIMBus-controller.patch](0014-ASoC-wcn-bt-slim-stop-pinning-the-SLIMBus-controller.patch). Без ручных изменений. |
| [0018](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0018-ASoC-codecs-wcn-bt-slim-add-the-WCN6750-product-0x22.patch) — ASoC: codecs: wcn-bt-slim: add the WCN6750 (product 0x221) | applied clean | [0015-ASoC-codecs-wcn-bt-slim-add-the-WCN6750-product-0x22.patch](0015-ASoC-codecs-wcn-bt-slim-add-the-WCN6750-product-0x22.patch). Без ручных изменений. |
| [0019](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0019-arm64-dts-qcom-sm7325-nothing-spacewar-Bluetooth-SCO.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: Bluetooth SCO over SLIMbus | applied clean → skipped | Применился чисто, но исключён: DTS использует SLIMBUS_7_RX/TX из пропущенного 0009; без определений DTB не собирается. |
| [0020](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0020-Bluetooth-hci_qca-allow-the-SLIMbus-HFP-offload-on-W.patch) — Bluetooth: hci_qca: allow the SLIMbus HFP offload on WCN6750 too | applied clean | [0016-Bluetooth-hci_qca-allow-the-SLIMbus-HFP-offload-on-W.patch](0016-Bluetooth-hci_qca-allow-the-SLIMbus-HFP-offload-on-W.patch). Без ручных изменений. |
| [0021](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0021-ASoC-codecs-tfa9872-expose-the-amplifier-gain-as-a-v.patch) — ASoC: codecs: tfa9872: expose the amplifier gain as a volume control | applied clean | [0017-ASoC-codecs-tfa9872-expose-the-amplifier-gain-as-a-v.patch](0017-ASoC-codecs-tfa9872-expose-the-amplifier-gain-as-a-v.patch). Без ручных изменений. |
| [0022](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0022-arm64-dts-qcom-sm7325-nothing-spacewar-in-call-recor.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: in-call record and far-end links | applied clean → skipped | Применился чисто, но исключён: DTS использует VOICE_RECORD_RX/TX и VOICE_PLAYBACK_TX из пропущенного 0009; без них DTB не собирается. |
| [0023](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0023-arm64-dts-qcom-sm7325-nothing-spacewar-map-the-WCD93.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: map the WCD9385 DMIC port to its own SoundWire port | applied clean | [0018-arm64-dts-qcom-sm7325-nothing-spacewar-map-the-WCD93.patch](0018-arm64-dts-qcom-sm7325-nothing-spacewar-map-the-WCD93.patch). Без ручных изменений. |
| [0024](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0024-ASoC-codecs-wcn-bt-slim-fix-the-module-device-table-.patch) — ASoC: codecs: wcn-bt-slim: fix the module device table type so the module autoloads | applied clean | [0019-ASoC-codecs-wcn-bt-slim-fix-the-module-device-table-.patch](0019-ASoC-codecs-wcn-bt-slim-fix-the-module-device-table-.patch). Без ручных изменений. |
| [0025](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0025-ASoC-codecs-tfa9872-expose-the-total-TDM-speaker-gai.patch) — ASoC: codecs: tfa9872: expose the total TDM speaker gain (TDMSPKG) | applied clean | [0020-ASoC-codecs-tfa9872-expose-the-total-TDM-speaker-gai.patch](0020-ASoC-codecs-tfa9872-expose-the-total-TDM-speaker-gai.patch). Без ручных изменений. |
| [0026](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0026-ASoC-qdsp6-q6voice-take-the-voice-calibration-direct.patch) — ASoC: qdsp6: q6voice: take the voice calibration directory from a parameter | conflict → skipped | Конфликт q6voice.c: cal_dir заменяет пути загрузчика калибровок r93, которого нет без 0008; не механический перенос на текущий стек. |
| [0027](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0027-misc-fastrpc-give-remote-heap-memory-back-to-HLOS-be.patch) — misc: fastrpc: give remote heap memory back to HLOS before freeing it | applied clean | [0021-misc-fastrpc-give-remote-heap-memory-back-to-HLOS-be.patch](0021-misc-fastrpc-give-remote-heap-memory-back-to-HLOS-be.patch). Без ручных изменений. |
| [0028](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0028-ASoC-qdsp6-q6voice-expose-the-call-downlink-volume-a.patch) — ASoC: qdsp6: q6voice: expose the call downlink volume as a mixer control | conflict → skipped | Конфликты q6voice-dai.c, q6voice.c, q6voice.h: RX volume control обращается к состоянию/калибровкам стека r93 из пропущенного 0008. Требуется логический перенос API. |
| [0029](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0029-ASoC-qdsp6-q6voice-size-the-call-volume-to-the-vendo.patch) — ASoC: qdsp6: q6voice: size the call volume to the vendor volume table | conflict → skipped | Конфликты q6voice-dai.c/q6voice.c: меняет RX volume table и control из отсутствующих 0008/0028; соответствующих структур и загрузчика в базе нет. |
| [0030](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0030-ASoC-qdsp6-q6voice-send-the-Rx-volume-gain-of-the-st.patch) — ASoC: qdsp6: q6voice: send the Rx volume gain of the step to the vocproc | conflict → skipped | Конфликты q6cvp.h/q6voice.c: отправка gain зависит от отсутствующего vendor volume table и RX volume API из 0008/0028/0029; не механический перенос. |
| [0031](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0031-arm64-dts-qcom-sm7325-nothing-spacewar-the-WCN6750-e.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: the WCN6750 enumerates as product 0x222 | applied clean → skipped | Применился чисто, но исключён: корректирует WCN6750 node из исключённого 0019; узла больше нет в итоговой серии. |
| [0032](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0032-firmware-qcom-scm-register-the-Gunyah-watchdog-on-th.patch) — firmware: qcom: scm: register the Gunyah watchdog on the Nothing Phone (1) | applied clean | [0022-firmware-qcom-scm-register-the-Gunyah-watchdog-on-th.patch](0022-firmware-qcom-scm-register-the-Gunyah-watchdog-on-th.patch). Без ручных изменений. |
| [0033](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0033-ASoC-qdsp6-q6afe-SLIMBus-AFE-ports-use-hardware-bloc.patch) — ASoC: qdsp6: q6afe: SLIMBus AFE ports use hardware block 0 on the Nothing Phone (1) | conflict → skipped | Конфликт q6afe.c: меняет default slim_dev_id из 0009, но в базе нет самого параметра и присваиваний slim_dev_id/slim_data_format в port config. Без 0009 перенос добавил бы неиспользуемые параметры. |
| [0034](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0034-ASoC-qdsp6-q6voice-do-not-rebuild-the-whole-session-.patch) — ASoC: qdsp6: q6voice: do not rebuild the whole session on a device switch by default | conflict → skipped | Конфликт q6voice.c: switch_full_session меняет логику смены устройств из отсутствующего 0008; в базе другой session lifecycle. Не угадываем поведение. |
| [0035](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0035-slimbus-qcom-ngd-ctrl-remove-a-stream-s-channels-by-.patch) — slimbus: qcom-ngd-ctrl: remove a stream's channels by default | applied clean | [0023-slimbus-qcom-ngd-ctrl-remove-a-stream-s-channels-by-.patch](0023-slimbus-qcom-ngd-ctrl-remove-a-stream-s-channels-by-.patch). Без ручных изменений. |
| [0036](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0036-ASoC-codecs-wcn-bt-slim-select-channel-bit-0-for-the.patch) — ASoC: codecs: wcn-bt-slim: select channel bit 0 for the TX port in the sco parameter | applied clean | [0024-ASoC-codecs-wcn-bt-slim-select-channel-bit-0-for-the.patch](0024-ASoC-codecs-wcn-bt-slim-select-channel-bit-0-for-the.patch). Без ручных изменений. |
| [0037](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0037-ASoC-codecs-wcn-bt-slim-hold-the-SLIMBus-controller-.patch) — ASoC: codecs: wcn-bt-slim: hold the SLIMBus controller up while the chip has no address | applied clean | [0025-ASoC-codecs-wcn-bt-slim-hold-the-SLIMBus-controller-.patch](0025-ASoC-codecs-wcn-bt-slim-hold-the-SLIMBus-controller-.patch). Без ручных изменений. |
| [0038](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0038-ASoC-codecs-wcn-bt-slim-do-not-hold-the-bus-while-Bl.patch) — ASoC: codecs: wcn-bt-slim: do not hold the bus while Bluetooth boots the chip | applied clean | [0026-ASoC-codecs-wcn-bt-slim-do-not-hold-the-bus-while-Bl.patch](0026-ASoC-codecs-wcn-bt-slim-do-not-hold-the-bus-while-Bl.patch). Без ручных изменений. |
| [0039](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0039-ASoC-codecs-wcn-bt-slim-look-for-the-chip-when-a-str.patch) — ASoC: codecs: wcn-bt-slim: look for the chip when a stream starts, after the offloaded SCO | applied clean | [0027-ASoC-codecs-wcn-bt-slim-look-for-the-chip-when-a-str.patch](0027-ASoC-codecs-wcn-bt-slim-look-for-the-chip-when-a-str.patch). Без ручных изменений. |
| [0040](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0040-ASoC-codecs-wcn-bt-slim-keep-the-stream-startup-look.patch) — ASoC: codecs: wcn-bt-slim: keep the stream startup look for the chip short | applied clean | [0028-ASoC-codecs-wcn-bt-slim-keep-the-stream-startup-look.patch](0028-ASoC-codecs-wcn-bt-slim-keep-the-stream-startup-look.patch). Без ручных изменений. |
| [0041](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0041-input-misc-add-the-Qualcomm-SPMI-PMIC-haptics-driver.patch) — input: misc: add the Qualcomm SPMI PMIC haptics driver (v7 by Fenglin Wu) | applied clean | [0029-input-misc-add-the-Qualcomm-SPMI-PMIC-haptics-driver.patch](0029-input-misc-add-the-Qualcomm-SPMI-PMIC-haptics-driver.patch). Без ручных изменений. |
| [0042](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0042-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: describe the PM8350B haptics | applied clean | [0030-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch](0030-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch). Без ручных изменений. |
| [0043](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0043-input-qcom-spmi-haptics-play-FF_RUMBLE-at-full-scale.patch) — input: qcom-spmi-haptics: play FF_RUMBLE at full scale and advertise FF_SINE | applied clean | [0031-input-qcom-spmi-haptics-play-FF_RUMBLE-at-full-scale.patch](0031-input-qcom-spmi-haptics-play-FF_RUMBLE-at-full-scale.patch). Без ручных изменений. |
| [0044](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0044-arm64-dts-qcom-sm7325-nothing-spacewar-S5KJN1-link-f.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: S5KJN1 link frequency is 700 MHz | applied clean | [0032-arm64-dts-qcom-sm7325-nothing-spacewar-S5KJN1-link-f.patch](0032-arm64-dts-qcom-sm7325-nothing-spacewar-S5KJN1-link-f.patch). Без ручных изменений. |
| [0045](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0045-WIP-media-i2c-add-a-Sony-IMX766-sensor-driver.patch) — WIP: media: i2c: add a Sony IMX766 sensor driver | applied clean | [0033-WIP-media-i2c-add-a-Sony-IMX766-sensor-driver.patch](0033-WIP-media-i2c-add-a-Sony-IMX766-sensor-driver.patch). Без ручных изменений. |
| [0046](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0046-WIP-arm64-dts-qcom-sm7325-nothing-spacewar-describe-.patch) — WIP: arm64: dts: qcom: sm7325-nothing-spacewar: describe the IMX766 main camera | applied clean | [0034-WIP-arm64-dts-qcom-sm7325-nothing-spacewar-describe-.patch](0034-WIP-arm64-dts-qcom-sm7325-nothing-spacewar-describe-.patch). Без ручных изменений. |
| [0047](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0047-media-i2c-imx471-the-sensor-reads-out-RGGB.patch) — media: i2c: imx471: the sensor reads out RGGB | applied clean | [0035-media-i2c-imx471-the-sensor-reads-out-RGGB.patch](0035-media-i2c-imx471-the-sensor-reads-out-RGGB.patch). Без ручных изменений. |
| [0048](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0048-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: describe the IMX766 focus actuator | applied clean | [0036-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch](0036-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch). Без ручных изменений. |
| [0049](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0049-power-supply-qcom_battmgr-expose-the-notification-re.patch) — power: supply: qcom_battmgr: expose the notification request fields | applied clean | [0037-power-supply-qcom_battmgr-expose-the-notification-re.patch](0037-power-supply-qcom_battmgr-expose-the-notification-re.patch). Без ручных изменений. |
| [0050](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0050-crypto-qce-Add-runtime-PM-and-interconnect-bandwidth.patch) — crypto: qce - Add runtime PM and interconnect bandwidth scaling support | conflict → resolved mechanically | [0038-crypto-qce-Add-runtime-PM-and-interconnect-bandwidth.patch](0038-crypto-qce-Add-runtime-PM-and-interconnect-bandwidth.patch). Механически: отсутствующий в базе include mod_devicetable.h мешал первому hunk; добавлены только pm.h/pm_runtime.h в существующий блок include. Остальные четыре hunk применились без изменений. |
| [0051](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0051-leds-add-the-Awinic-AW21018-glyph-LED-driver.patch) — leds: add the Awinic AW21018 glyph LED driver | applied clean | [0039-leds-add-the-Awinic-AW21018-glyph-LED-driver.patch](0039-leds-add-the-Awinic-AW21018-glyph-LED-driver.patch). Без ручных изменений. |
| [0052](https://github.com/woodyst/spacewar-pmos/blob/a975d531a7365194752fa715db15d32db89b5e4e/kernel/0052-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-glyph-LEDs.patch) — arm64: dts: qcom: sm7325-nothing-spacewar: describe the glyph LEDs | applied clean | [0040-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch](0040-arm64-dts-qcom-sm7325-nothing-spacewar-describe-the-.patch). Без ручных изменений. |

**Известная гонка в 0037 woodyst:** `notif_apply_set` может использовать освобождённый `qcom_battmgr_instance` при конкурентном удалении устройства; статический анализ описан в [отчёте ревью](../../../research/review-2026-10-17.md#находки), сам патч не изменён.

## Пропущенные изменения

- **0008**: Немеханический add/add: уже существуют 12 файлов q6voice/q6cvp/q6cvs/q6mvm и dt-binding, но импорт r93 меняет API, calibration/session/routing и удаляет VOICEMMODE1 ID; повторный импорт дублирует Kconfig/Makefile. Нужен отдельный перенос логики.
- **0009**: Конфликт q6core.c при регистрации/снятии custom topologies; q6routing дополнительно вызывает отсутствующие без 0008 q6voice_incall_record_route/playback_route. Нужен согласованный перенос со стеком r93, частичный патч не экспортируется.
- **0010**: Применился чисто, но исключён: common.c использует VOICE_PLAYBACK_TX, sm8250.c — SLIMBUS_7_RX/TX из пропущенного 0009; без него объекты не компилируются.
- **0019**: Применился чисто, но исключён: DTS использует SLIMBUS_7_RX/TX из пропущенного 0009; без определений DTB не собирается.
- **0022**: Применился чисто, но исключён: DTS использует VOICE_RECORD_RX/TX и VOICE_PLAYBACK_TX из пропущенного 0009; без них DTB не собирается.
- **0026**: Конфликт q6voice.c: cal_dir заменяет пути загрузчика калибровок r93, которого нет без 0008; не механический перенос на текущий стек.
- **0028**: Конфликты q6voice-dai.c, q6voice.c, q6voice.h: RX volume control обращается к состоянию/калибровкам стека r93 из пропущенного 0008. Требуется логический перенос API.
- **0029**: Конфликты q6voice-dai.c/q6voice.c: меняет RX volume table и control из отсутствующих 0008/0028; соответствующих структур и загрузчика в базе нет.
- **0030**: Конфликты q6cvp.h/q6voice.c: отправка gain зависит от отсутствующего vendor volume table и RX volume API из 0008/0028/0029; не механический перенос.
- **0031**: Применился чисто, но исключён: корректирует WCN6750 node из исключённого 0019; узла больше нет в итоговой серии.
- **0033**: Конфликт q6afe.c: меняет default slim_dev_id из 0009, но в базе нет самого параметра и присваиваний slim_dev_id/slim_data_format в port config. Без 0009 перенос добавил бы неиспользуемые параметры.
- **0034**: Конфликт q6voice.c: switch_full_session меняет логику смены устройств из отсутствующего 0008; в базе другой session lifecycle. Не угадываем поведение.

Конфликтующие add/add пути 0008:

- `include/dt-bindings/sound/qcom,q6voice.h`
- `sound/soc/qcom/qdsp6/q6cvp.c`
- `sound/soc/qcom/qdsp6/q6cvp.h`
- `sound/soc/qcom/qdsp6/q6cvs.c`
- `sound/soc/qcom/qdsp6/q6cvs.h`
- `sound/soc/qcom/qdsp6/q6mvm.c`
- `sound/soc/qcom/qdsp6/q6mvm.h`
- `sound/soc/qcom/qdsp6/q6voice-common.c`
- `sound/soc/qcom/qdsp6/q6voice-common.h`
- `sound/soc/qcom/qdsp6/q6voice-dai.c`
- `sound/soc/qcom/qdsp6/q6voice.c`
- `sound/soc/qcom/qdsp6/q6voice.h`

Чистое применение не означает совместимость: у 0010, 0019, 0022 отсутствуют определения
`SLIMBUS_7_RX/TX`, `VOICE_RECORD_RX/TX`, `VOICE_PLAYBACK_TX` из 0009; 0031 меняет
удалённый вместе с 0019 узел. Вносить только эти определения означало бы неполный перенос
маршрутизации. Исключён весь соответствующий патч, без вырезания «неудобных» hunks.
Сохранённые Bluetooth/SLIMBus заготовки не доказывают работоспособность SCO/CS voice:
стек r93, custom topologies, калибровки и маршрутизация требуют отдельной работы.

## Новые Kconfig-опции, отсутствующие в конфиге пакета

Конфиг `config-postmarketos-qcom-sc7280.aarch64` оставлен неизменённым.
Без явного включения новые драйверы остаются выключенными после `olddefconfig`.

| Опция | Исходный патч | Рекомендация | Условия |
| --- | --- | --- | --- |
| `CONFIG_SND_SOC_WCN_BT_SLIM` | 0016 | `m` | Также `CONFIG_SLIMBUS=m` и `CONFIG_SLIM_QCOM_NGD_CTRL=m`; сейчас SLIMBUS выключен. Для SCO нужен отдельный перенос пропущенных 0008–0010/0019, одной опции недостаточно. |
| `CONFIG_INPUT_QCOM_SPMI_HAPTICS` | 0041 | `m` | Нужен `MFD_SPMI_PMIC`; в конфиге уже включены он и `INPUT_FF_MEMLESS`. |
| `CONFIG_VIDEO_IMX766` | 0045 | `m` | WIP-драйвер; нужны OF/GPIOLIB и V4L2, выбирает V4L2_CCI_I2C. Аппаратно не проверен. |
| `CONFIG_LEDS_AW21018` | 0051 | `m` | Нужны I2C и LEDS_CLASS, в исходном конфиге доступны. |

`SND_SOC_QDSP6_Q6VOICE` и `SND_SOC_QDSP6_Q6VOICE_DAI` из 0008 уже есть в базе
и исходном конфиге (`m`), поэтому не входят в список недостающих новых опций.
`y` можно выбрать для нужной до загрузки модулей функции; для этих периферийных
драйверов рекомендуется `m`, как у остальных камер/кодеков пакета.

## Проверки исходных 40 патчей без полной сборки

- clang 23.1.3 уже установлен. LLD 23.1.3 и bc 1.08.2 распакованы из пакетов
  Arch/Omarchy в `.work/toolchain` без установки в систему и без sudo.
- Исходный конфиг скопирован в `.config`; `make ARCH=arm64 LLVM=1 olddefconfig` успешен.
- `make ARCH=arm64 LLVM=1 -j8 qcom/sm7325-nothing-spacewar.dtb` успешен с исходным
  конфигом после механической адаптации 0013. Без неё dtc останавливался на четырёх
  duplicate labels из уже включённого `kodiak.dtsi`; существующие service nodes
  теперь включаются через `status = "okay"`, без повторного объявления.
- DTB: 152692 байта, SHA-256
  `0cd6e83103b1c153102406bde35ea17583852036dbb78df98891b31187375a55`.
- Для проверки новых C-драйверов только в рабочем конфиге установлены `m` для четырёх
  новых опций, `SLIMBUS` и `SLIM_QCOM_NGD_CTRL`, затем выполнен `olddefconfig`.
  Все 15 затронутых C-файлов скомпилированы через прямые цели `.o` с `ARCH=arm64 LLVM=1 -j8`.
  Единственное предупреждение: `sound/soc/codecs/wcn-bt-slim.c:1201`,
  неиспользуемая `probe_la` (`-Wunused-variable`); код woodyst оставлен без изменения.
  Часть объектов — LLVM bitcode из-за LTO в исходном конфиге.
- `makepkg --verifysource --ignorearch`: все 43 SHA-512 совпали (архив, конфиг,
  preset, 40 патчей). Архив скачан через `gh api` по URL снимка из PKGBUILD.
- `makepkg --nobuild --nodeps --ignorearch` с `LLVM=1 CROSS_COMPILE=aarch64-linux-gnu-`
  успешно распаковал свежий архив, применил все 40 патчей в `prepare()` и выполнил
  `olddefconfig`. Полная сборка этой командой не запускается.
- `bash -n PKGBUILD` успешен. `_kmake` и выбор GNU cross prefix не изменены.

Полное ядро, модули и headers не собирались и не линковались; загрузка на телефоне,
DT-schema и работа периферии не проверялись. Сборка отдельных объектов не заменяет
сборку всего ядра и проверку символов модулей.

Цели объектной проверки:

```text
drivers/bluetooth/hci_qca.o
drivers/crypto/qce/core.o
drivers/firmware/qcom/qcom_scm.o
drivers/input/misc/qcom-spmi-haptics.o
drivers/leds/leds-aw21018.o
drivers/media/i2c/dw9719.o
drivers/media/i2c/imx471.o
drivers/media/i2c/imx766.o
drivers/media/i2c/s5kjn1.o
drivers/misc/fastrpc.o
drivers/power/supply/qcom_battmgr.o
drivers/slimbus/core.o
drivers/slimbus/qcom-ngd-ctrl.o
sound/soc/codecs/tfa9872.o
sound/soc/codecs/wcn-bt-slim.o
```

Подробные локальные журналы: `.work/kernel-logs/`; исходные `ref/` и `research/` не изменялись.
