<div align="center">

# 🔧 msc-wizard

**Interactive installer wizard for [My Summer Car](https://store.steampowered.com/app/516750/My_Summer_Car/) on Linux**

Install MSCLoader and/or WreckMP multiplayer — safely, interactively, in minutes.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.2.0-green.svg)](msc-wizard.sh)
[![Platform](https://img.shields.io/badge/platform-Linux-orange.svg)]()
[![Language](https://img.shields.io/badge/language-bash-lightgrey.svg)]()
[![Steam](https://img.shields.io/badge/Steam%20app-516750-1b2838?logo=steam)](https://store.steampowered.com/app/516750/)

[English](#-english) · [Українська](#-ukrainian)

</div>

---

## 🇬🇧 English

### What is this?

An interactive bash wizard that installs **MSCLoader** (mod loader) and/or **WreckMP** (multiplayer) for *My Summer Car* on Linux via Steam + Proton.

**Nothing changes without a warning.** Every step checks if it's already done — you can stop anytime and re-run to continue.

### Features

- 🔄 **Idempotent** — safe to run multiple times
- 🧪 **Dry-run mode** — preview all actions without changing anything
- 🌐 **Bilingual** — Ukrainian / English, auto-detected from locale
- 📦 **Any Steam** — native, Flatpak, Snap
- 🎮 **Non-Steam copy** — Wine / Lutris / Bottles / Heroic / Steam shortcut
- 🔍 **Status check** — inspect current setup without changes
- 🛠️ **Repair** — fixes the launcher's *"register/registry not found"* (game path in its registry, written straight into the prefix files, no protontricks) and aligns MachineGuid — after a Proton/Steam update, moving the game or a new Steam shortcut/account
- ⚡ **Tune for this PC** — detects GPU/CPU/RAM and generates matching Steam Launch Options (hybrid NVIDIA/AMD/Intel laptops, Steam Deck, Flatpak/Snap Steam)
- 🚀 **Launcher auto-close** — WreckMP launcher closes itself 5 s after the game starts; multiplayer keeps working. The wizard offers it right after installing WreckMP (and in item 9 / `--tune`) and **writes the Launch Options into Steam by itself** — game and launcher shortcut (it closes Steam first, asking you)
- 🔎 **GPU check** — shows whether the running game uses DXVK or wined3d and which GPU

### Requirements

- bash 4.4+
- Steam with Proton (or Wine/Lutris/etc. for non-Steam copy)
- [protontricks](https://github.com/Matoking/protontricks)
- *My Summer Car* installed (Steam App ID: 516750)

### Install & Run

```bash
curl -LO https://raw.githubusercontent.com/Volod3/msc-wizard/main/msc-wizard.sh
bash msc-wizard.sh
```

### Usage

```
bash msc-wizard.sh                   # language → run type → menu
bash msc-wizard.sh --dry-run         # dry run: same questions, nothing changed
bash msc-wizard.sh --status          # show state only (no changes)
bash msc-wizard.sh --steam-info      # Steam cheat sheet: Proton, launch options, paths
bash msc-wizard.sh --tune             # detect this PC and print the best Launch Options
bash msc-wizard.sh --gpu-check        # while the game runs: DXVK or wined3d? which GPU?
bash msc-wizard.sh --fix-guid        # repair: launcher registry + MachineGuid
bash msc-wizard.sh --fix-reg         # only fix "register/registry not found"
bash msc-wizard.sh --nonsteam        # game is NOT from Steam (Wine / Lutris / Bottles / Heroic)
bash msc-wizard.sh --game-dir /path  # specify game folder manually
bash msc-wizard.sh --lang uk|en      # interface language (skips the question)
bash msc-wizard.sh --help            # short help
bash msc-wizard.sh --readme          # full manual
```

### Menu

```
What do we do?
  1) MSCLoader only (mods without multiplayer)
  2) WreckMP only (MSCLoader is already installed)
  3) Everything: MSCLoader + WreckMP
  4) Show the state and check the setup
  5) Steam cheat sheet
  6) Repair after an update / moving the game (launcher registry + MachineGuid)
  7) Settings
  8) Help / README
  9) Tune for this PC (hardware -> Launch Options)
  0) Quit
```


### Tune for this PC

`bash msc-wizard.sh --tune` (or menu item 9) reads the hardware from `/sys`, `/proc` and, if present, `lspci` / `nvidia-smi` (no root, any distro) and prints Launch Options for your machine:

| Hardware | What is set |
|---|---|
| NVIDIA (proprietary) + Intel/AMD iGPU | PRIME offload variables + `DXVK_FILTER_DEVICE_NAME` |
| AMD / Intel / nouveau with a second GPU | `DRI_PRIME=1` |
| Single GPU / Steam Deck | no GPU variables, shader-cache settings only |
| `gamemoderun` installed | added (not for Flatpak/Snap Steam) |

It also creates `<game folder>/.msc-wizard/msc_launch.sh`, which switches MSCLoader / WreckMP mode, removes `PROTON_USE_WINED3D` for the game (the usual cause of ~1 FPS) and closes the WreckMP launcher 5 s after the game starts. The Launch Options are monolithic: delete the script and the game still starts. While the game runs, `bash msc-wizard.sh --gpu-check` shows whether DXVK is used and whether the game is really on the discrete GPU.

> Values are chosen conservatively per hardware class. FPS gains were not measured, and the hybrid/AMD paths are untested on real hardware.

---

## 🇺🇦 Ukrainian

### Що це?

Інтерактивний bash-майстер, який встановлює **MSCLoader** (мод-лоадер) та/або **WreckMP** (мультиплеєр) для гри *My Summer Car* на Linux через Steam + Proton.

**Нічого не змінюється без попередження.** Кожен крок перевіряє, чи вже зроблений — можна зупинитись і запустити знову.

### Особливості

- 🔄 **Ідемпотентний** — безпечно запускати повторно
- 🧪 **Dry-run режим** — покаже що буде зроблено, нічого не змінюючи
- 🌐 **Двомовний** — Українська / English, автовизначення за локаллю
- 📦 **Будь-який Steam** — native, Flatpak, Snap
- 🎮 **Non-Steam копія** — Wine / Lutris / Bottles / Heroic / Steam shortcut
- 🔍 **Статус** — перевірка поточного стану без змін
- 🚀 **Автозакриття лаунчера** — лаунчер WreckMP сам закривається через 5 с після старту гри, мультиплеєр працює далі. Майстер пропонує це одразу після встановлення WreckMP (і в пункті 9 / `--tune`) та **сам записує параметри запуску в Steam** — для гри й ярлика лаунчера (спершу спитає й закриє Steam)
- 🛠️ **Ремонт** — виправляє *«register/registry not found»* у лаунчері (шлях до гри в його реєстрі пишеться прямо у файли prefix-у, без protontricks) і вирівнює MachineGuid — після оновлення Proton/Steam, переносу гри чи нового ярлика/акаунта Steam
- ⚡ **Оптимізація під ПК** — визначає GPU/CPU/RAM і дає відповідні параметри запуску Steam (гібридні ноутбуки NVIDIA/AMD/Intel, Steam Deck, Flatpak/Snap Steam)
- 🚀 **Автозакриття лаунчера** — лаунчер WreckMP закривається сам через 5 с після старту гри; мультиплеєр лишається
- 🔎 **Перевірка GPU** — показує, чи гра на DXVK чи wined3d і на якій відеокарті

### Вимоги

- bash 4.4+
- Steam з Proton (або Wine/Lutris/тощо для non-Steam копії)
- [protontricks](https://github.com/Matoking/protontricks)
- Встановлена гра *My Summer Car* (Steam App ID: 516750)

### Встановлення та запуск

```bash
curl -LO https://raw.githubusercontent.com/Volod3/msc-wizard/main/msc-wizard.sh
bash msc-wizard.sh
```

### Використання

```
bash msc-wizard.sh                   # мова → тип запуску → меню
bash msc-wizard.sh --dry-run         # пробний запуск: ті самі запитання, нічого не змінюється
bash msc-wizard.sh --status          # показати стан (нічого не змінює)
bash msc-wizard.sh --steam-info      # шпаргалка Steam: Proton, параметри запуску, шляхи
bash msc-wizard.sh --tune             # визначити цей ПК і дати найкращі параметри запуску
bash msc-wizard.sh --gpu-check        # поки гра працює: DXVK чи wined3d? яка відеокарта?
bash msc-wizard.sh --fix-guid        # ремонт: реєстр лаунчера + MachineGuid
bash msc-wizard.sh --fix-reg         # лише виправити «register/registry not found»
bash msc-wizard.sh --nonsteam        # гра НЕ зі Steam (Wine / Lutris / Bottles / Heroic)
bash msc-wizard.sh --game-dir /path  # вказати папку гри вручну
bash msc-wizard.sh --lang uk|en      # мова інтерфейсу (пропускає запитання)
bash msc-wizard.sh --help            # коротка довідка
bash msc-wizard.sh --readme          # повний мануал
```

### Меню

```
Що робимо?
  1) Тільки MSCLoader (моди без мультиплеєра)
  2) Тільки WreckMP (MSCLoader уже стоїть)
  3) Усе: MSCLoader + WreckMP
  4) Показати стан і перевірити налаштування
  5) Шпаргалка Steam
  6) Полагодити після оновлення / переносу гри (реєстр лаунчера + MachineGuid)
  7) Налаштування
  8) Довідка / README
  9) Оптимізація під цей ПК (залізо -> параметри запуску)
  0) Вийти
```

### Оптимізація під цей ПК

`bash msc-wizard.sh --tune` (або пункт 9 меню) читає залізо з `/sys`, `/proc` та, якщо є, `lspci` / `nvidia-smi` (без root, будь-який дистрибутив) і дає параметри запуску для твоєї машини:

| Залізо | Що ставиться |
|---|---|
| NVIDIA (пропрієтарний) + Intel/AMD iGPU | змінні PRIME offload + `DXVK_FILTER_DEVICE_NAME` |
| AMD / Intel / nouveau з другим GPU | `DRI_PRIME=1` |
| Один GPU / Steam Deck | без змінних GPU, лише кеш шейдерів |
| встановлений `gamemoderun` | додається (не для Flatpak/Snap Steam) |

Також створює `<папка гри>/.msc-wizard/msc_launch.sh`: він перемикає режим MSCLoader / WreckMP, знімає `PROTON_USE_WINED3D` для гри (типова причина ~1 FPS) і закриває лаунчер WreckMP через 5 с після старту гри. Параметри монолітні: видалиш скрипт, гра все одно запуститься. Поки гра працює, `bash msc-wizard.sh --gpu-check` покаже, чи використовується DXVK і чи гра справді на дискретній відеокарті.

> Значення підібрані консервативно під клас заліза. Приріст FPS не вимірювався, а гібридні/AMD шляхи не перевірені на справжньому залізі.

---

## 🔗 Related

- [MSCLoader](https://github.com/piotrulos/MSCModLoader) — mod loader for My Summer Car
- [WreckMP](https://www.nexusmods.com/mysummercar/mods/5271) — multiplayer mod
- [protontricks](https://github.com/Matoking/protontricks) — Winetricks for Proton prefixes

---

## 📄 License

MIT — do whatever you want, no warranty.
