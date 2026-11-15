<div align="center">

# 🔧 msc-wizard

**Interactive installer wizard for [My Summer Car](https://store.steampowered.com/app/516750/My_Summer_Car/) on Linux**

Install MSCLoader and/or WreckMP multiplayer — safely, interactively, in minutes.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.1.0-green.svg)](msc-wizard.sh)
[![Platform](https://img.shields.io/badge/platform-Linux-orange.svg)]()
[![Language](https://img.shields.io/badge/language-bash-lightgrey.svg)]()
[![Steam](https://img.shields.io/badge/Steam%20app-516750-1b2838?logo=steam)](https://store.steampowered.com/app/516750/)

[Українська](#-ukrainian) · [English](#-english)

</div>

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
- 🛠️ **Fix MachineGuid** — після оновлення Proton/Steam

### Вимоги

- bash 4.4+
- Steam з Proton (або Wine/Lutris/тощо для non-Steam копії)
- [protontricks](https://github.com/Matoking/protontricks)
- Встановлена гра *My Summer Car* (Steam App ID: 516750)

### Встановлення та запуск

```bash
# Завантажити
curl -LO https://raw.githubusercontent.com/Volod3/msc-wizard/main/msc-wizard.sh

# Запустити
bash msc-wizard.sh
```

### Використання

```
bash msc-wizard.sh                   # мова → тип запуску → меню
bash msc-wizard.sh --dry-run         # пробний запуск: ті самі запитання, нічого не змінюється
bash msc-wizard.sh --status          # показати стан (нічого не змінює)
bash msc-wizard.sh --steam-info      # шпаргалка Steam: Proton, параметри запуску, шляхи
bash msc-wizard.sh --fix-guid        # вирівняти MachineGuid (після оновлення Proton/Steam)
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
  6) Вирівняти MachineGuid
  7) Налаштування
  8) Довідка / README
  0) Вийти
```

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
- 🛠️ **Fix MachineGuid** — after a Proton/Steam update

### Requirements

- bash 4.4+
- Steam with Proton (or Wine/Lutris/etc. for non-Steam copy)
- [protontricks](https://github.com/Matoking/protontricks)
- *My Summer Car* installed (Steam App ID: 516750)

### Install & Run

```bash
# Download
curl -LO https://raw.githubusercontent.com/Volod3/msc-wizard/main/msc-wizard.sh

# Run
bash msc-wizard.sh
```

### Usage

```
bash msc-wizard.sh                   # language → run type → menu
bash msc-wizard.sh --dry-run         # dry run: same questions, nothing changed
bash msc-wizard.sh --status          # show state only (no changes)
bash msc-wizard.sh --steam-info      # Steam cheat sheet: Proton, launch options, paths
bash msc-wizard.sh --fix-guid        # align MachineGuid (after Proton/Steam update)
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
  6) Align MachineGuid
  7) Settings
  8) Help / README
  0) Quit
```

---

## 🔗 Related

- [MSCLoader](https://github.com/piotrulos/MSCModLoader) — mod loader for My Summer Car
- [WreckMP](https://www.nexusmods.com/mysummercar/mods/5271) — multiplayer mod
- [protontricks](https://github.com/Matoking/protontricks) — Winetricks for Proton prefixes

---

## 📄 License

MIT — do whatever you want, no warranty.
