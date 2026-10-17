# Spacewar UCM: HiFi и экспериментальный VoiceMMode1

**VoiceCall не проверен на телефоне.** Пакет устанавливает рабочий профиль HiFi
из pmOS и отдельный экспериментальный use case Voice Call. Kernel baseline: b90de19446e8 + 40 патчей
woodyst + наш 0041 (275a8467d). Драйверы общего стека не изменены.

## Установка пакета

```sh
cd pkgs/nothing-spacewar-ucm
makepkg
```

`PKGBUILD` устанавливает только `Nothing/spacewar/{spacewar,HiFi,VoiceCall}.conf`
и относительную ссылку `conf.d/sm8250/NP1.conf` на `spacewar.conf`.
Путь соответствует [pmaports UCM на закреплённом коммите](https://github.com/sc7280-mainline/alsa-ucm-conf/blob/3dbb936f0cc85a5d3f12bab12a4578d85768061c/ucm2/conf.d/sm8250/NP1.conf):
имя карты — NP1, драйвер — sm8250, несмотря на SoC sm7325
(обоснование также в `pkgs/linux-sc7280/0001-arm64-dts-qcom-sm7325-nothing-spacewar-enable-WCD938.patch:12–16`).
`HiFi.conf` скопирован побайтно из того же коммита; BootSequence и три Include
из `Nothing/spacewar/NP1.conf` сохранены. Добавлены только Define и Voice Call.

Общие `ucm.conf`, `lib/` и `codecs/` предоставляет зависимость `alsa-ucm-conf`.
В Arch `alsa-ucm-conf 1.2.16.1-1` и alsa-project master
`d260eedd1900dbf3b477047e048d5382a5f50e24` нет файлов NP1/Nothing; пересечений
содержимого нет, поэтому `conflicts`/`replaces` не нужны. Установленная pmOS
замена `alsa-ucm-conf-qcom-sc7280` здесь не используется.
Упаковка следует [образцу Arch](https://github.com/archlinux/svntogit-packages/blob/packages/alsa-ucm-conf/trunk/PKGBUILD)
(архивный рецепт 1.2.9: данные в `/usr/share/alsa/ucm2`, отдельная лицензия)
и `ref/alsa-ucm-conf-qcom-sc7280/APKBUILD:16–19`.

Voice Call требует отдельно установленного `dummystreamhack` и пользовательского
`dummystreamhack@.service`; пакет их не поставляет. До проверки PCM и службы
использовать HiFi. Проверка пакета на компьютере не подтверждает звук на телефоне.

## Источники и сравнение

Проверено через `gh api` 17.10.2026:

- [dubai DTS, 6266f398f6a46df5df3a9908b12a2fbf3013f689](https://github.com/sc7280-mainline/linux/commit/6266f398f6a46df5df3a9908b12a2fbf3013f689).
  AuthorDate 01.08.2026, CommitDate 29.09.2026 (дата в задании — дата включения).
- [sc7280 UCM, 3dbb936f0cc85a5d3f12bab12a4578d85768061c](https://github.com/sc7280-mainline/alsa-ucm-conf/tree/3dbb936f0cc85a5d3f12bab12a4578d85768061c),
  совпадает с `_commit` в `ref/alsa-ucm-conf-qcom-sc7280/APKBUILD:11`.
  `ucm2/Motorola/dubai/VoiceCall.conf:5–20` и
  `ucm2/Fairphone/fp5/VoiceCall.conf:5–20` включают VoiceMMode1 и обычные
  мультимедийные sink/source. Отличаются RX: SEN_MI2S / QUIN_MI2S.
  TX у обоих TX_CODEC_DMA_TX_3. Это текущий доступный профиль в ветке sc7280;
  новые маршруты в форке ядра не заимствовались.
- В [alsa-project/alsa-ucm-conf master, d260eedd1900dbf3b477047e048d5382a5f50e24](https://github.com/alsa-project/alsa-ucm-conf/tree/d260eedd1900dbf3b477047e048d5382a5f50e24)
  поиск `VoiceMMode1|VOICEMMODE1` по `ucm2` не дал результатов;
  каталогов Motorola/dubai и Fairphone/fp5 нет. Поэтому образец взят из
  явно указанного в задании sc7280 UCM, а не выдан за alsa-project upstream.
- `research/spacewar-pmos/device/ucm/Nothing/spacewar/VoiceCall.conf:1–36`:
  старый surya-профиль использует CS-Voice, SLIMBUS_7, vendor calibration,
  `Voice Rx`/`Voice Tx`; в новом профиле этих контролов нет.
  Наблюдение woodyst о нижнем AMIC1/ADC1/DEC0 использовано как аппаратная
  гипотеза, а не как результат проверки общего стека. Верхний микрофон для
  speakerphone пока не настроен: оба режима используют Mic1.

## Аппаратные пути и точные имена

Пути ниже относительно `.work/linux`, номера строк — после 0041.
Имена ALSA DAPM-контролов образуются из имени widget и имени его control.

| Назначение | Доказательство в исходниках |
| --- | --- |
| Voice DAI / сессия | `sound/soc/qcom/qdsp6/q6voice-dai.c:20` и `:89`: VOICEMMODE1 → Q6VOICE_PATH_VOICEMMODE1; `:27` startup вызывает q6voice_start |
| RX Spacewar | `arch/arm64/boot/dts/qcom/sm7325-nothing-spacewar.dts:1606`: I2S Playback, PRIMARY_MI2S_RX → tfa9873_l/r; `:1148`/`:1160`: каналы 0/1, префиксы Earpiece/Speaker |
| WCD playback/capture | тот же DTS `:1622`/`:1638`: RX_CODEC_DMA_RX_0 через swr0/lpass_rx_macro; TX_CODEC_DMA_TX_3 через swr1/lpass_tx_macro |
| Микрофоны | тот же DTS `:1563`: AMIC1–4/MIC BIAS1–4 и ADC1/2/3/4 → TX SWR_INPUT0/1/4/5; `:1216`: DMIC не используется |
| `PRI_MI2S_RX Voice Mixer VoiceMMode1` | `q6voice-dai.c:279`, `:329`, `:375`, `:382` |
| `VoiceMMode1 Capture Mixer TX_CODEC_DMA_TX_3` | `q6voice-dai.c:268`, `:326`, `:364` |
| `PRI_MI2S_RX Audio Mixer MultiMedia1` | `sound/soc/qcom/qdsp6/q6routing.c:30`, `:775`, `:985` |
| `MultiMedia3 Mixer TX_CODEC_DMA_TX_3` | `q6routing.c:320`, `:955`, `:1047` |
| `Earpiece Output Switch`, `Speaker Output Switch` | `sound/soc/codecs/tfa9872.c:106–118` + префиксы из DTS `:1149`/`:1161` |
| `ADC1_MIXER Switch`, `ADC1 Switch`, `TX0 MODE` | `sound/soc/codecs/wcd938x.c:1735`, `:2609`, `:2718`, `:1833`; допустимые режимы `:1632` |
| `TX DEC0 MUX`, `TX SMIC MUX0`, `TX_AIF1_CAP Mixer DEC0`, `TX_DEC0 Volume` | `sound/soc/codecs/lpass-tx-macro.c:1457`, `:1883`, `:1523`, `:2029`; SWR_MIC `:1265`, ZERO/SWR_MIC0 `:1836` |

dubai использует WCD9375 и AW88261 через SENARY_MI2S_RX
(`sm7325-motorola-dubai-common.dtsi:1482`, `:1529`);
FP5 — WCD9385 и AW88261 через QUINARY_MI2S_RX
(`qcm6490-fairphone-fp5.dts:1545`, `:1593`). Разговорный динамик Spacewar —
верхний TFA9873, а не выход EAR WCD. Поэтому перенос Senary/Quinary контролов
или AW88261 Profile Set был бы ошибкой.

`q6voice-dai.c:253–274,357–367` поддерживает TX: PRI/SEC/TERT/QUAT/QUIN/SEN MI2S
и TX_CODEC_DMA_TX_1–4. RX: шесть MI2S
(`:276–316,375–387`). У CS-Voice нет codec-DMA capture (`:238–251`), поэтому
старый FE заменён, а не оставлен вторым параллельным голосовым трактом.

## Недостающие маршруты и ограничения

- Для пары PRIMARY_MI2S_RX + TX_CODEC_DMA_TX_3 ничего добавлять в драйвер не нужно.
- RX_CODEC_DMA_RX_0 (WCD, проводные наушники) в голосовых RX mixers/routes
  отсутствует. Для него нужны согласованные control, widget и DAPM routes в
  q6voice-dai, затем проверка AFE/CVP media format и реального DSP. Драйверный
  код вслепую не добавлен; Headphones в VoiceCall отсутствует.
- SLIMBUS_7 SCO и surya-калибровки не перенесены. Bluetooth в черновике отсутствует.
- Нет `Voice Calibration`, `Voice Rx Playback Volume`, `Voice Tx Capture Switch`:
  их нет среди контролов общего q6voice-dai. Программный mute/volume PipeWire
  на мультимедийном PCM не гарантирует mute/volume модемного аудио.
- Реальные topology-контролы — `VoiceMMode1 TX Topology` / `RX Topology`
  (`q6voice-dai.c:231–236`), но значения Nothing не угаданы и не задаются.
  Сохраняются defaults NONE/RX_DEFAULT (`q6voice.c:271–272`): качество, эхо,
  усиление, совместимость firmware и маршрутизацию модемной сессии нужно проверить.

## Нужен ли q6voiced

Для выбранной схемы **отдельный q6voiced не нужен**: роль открытия PCM выполняет
`dummystreamhack`. Так устроены оба образца: dubai `VoiceCall.conf:30,60`
открывает R/T на PCM 5; FP5 `:30,60` — на PCM 7. Зависимость пакета pmOS —
`dummystreamhack` (`ref/alsa-ucm-conf-qcom-sc7280/APKBUILD:9`). В общем драйвере
сессия стартует при открытии обоих направлений (`q6voice.c:135–171`, проверка
`started != 3`), а не автоматически от наличия DTS.

В pmOS `soc-qcom` отдельно тянет q6voiced и включает его OpenRC-службу
(`ref/soc-qcom/APKBUILD:91,110`, `soc-qcom-modem-openrc.post-install:2`).
Это общая зависимость modem-пакета, а не доказательство, что именно профили
FP5/dubai используют его вместо своих exec. Одновременное владение voice PCM
двумя помощниками нужно исключить. Если вместо dummystreamhack выбирается
q6voiced, сначала проверить поддержку выбора VoiceMMode1 и порядок установки
маршрутов в конкретной версии; старую настройку на CS-Voice не переносить.

## Интеграция и проверка на телефоне

1. Включить общий q6voice и 0041, проверить загрузку q6voice/q6cvp/q6cvs/q6mvm/
   q6voice-dai. В конфиге пакета обе опции `SND_SOC_QDSP6_Q6VOICE` и
   `SND_SOC_QDSP6_Q6VOICE_DAI` уже `m` (`:5460–5461`). Отдельных CONFIG_Q6CVP/
   Q6CVS/Q6MVM нет: их объекты включаются через Q6VOICE
   (`sound/soc/qcom/qdsp6/Makefile:14–16`, `sound/soc/qcom/Kconfig:159–165`).
2. Снять `/proc/asound/pcm`, `aplay -l`, `arecord -l`, `amixer -c NP1 contents`.
   `Define.VoicePCM "3"` — **расчёт по порядку четырёх FE в DTS**, не измерение.
   Уточнить номер именно VoiceMMode1 и исправить Define до запуска.
   Мультимедийные PCM 0/2 также проверить. Номера 5/7 из чужих телефонов не копировать.
3. Для Voice Call установить dummystreamhack с пользовательским `dummystreamhack@.service`, как
   в профилях sc7280; подтвердить смысл R/T и готовность службы. Этот репозиторий
   не устанавливает её. Инициализацию WCD/HiFi пакет сохраняет из pmOS.
4. Установить собранный пакет: он уже связывает NP1 с `spacewar.conf`,
   регистрирует HiFi и Voice Call и сохраняет BootSequence pmOS.
5. Проверить `alsaucm -c NP1 list _verbs`, выбор Voice Call, Earpiece либо Speaker
   **и Mic1 одновременно**, отсутствие ошибок cset и запуск обоих помощников.
   Громкость начать с осторожного уровня; проверить каналы, звук в обе стороны,
   эхо, микрофон, завершение и повтор звонка, смену динамика. Для speakerphone
   отдельно подобрать верхний микрофон/ECNS. DisableSequence возвращает оба
   усилителя во включённое состояние для обычного стерео HiFi; произвольное
   предыдущее состояние не сохраняется. Не переключать HiFi параллельно звонку.

На рабочей машине выполнен только синтаксический разбор UCM через libasound;
проверки наличия ALSA-контролов, выполнения exec и аудио требуют телефона.
