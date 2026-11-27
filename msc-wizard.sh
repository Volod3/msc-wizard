#!/usr/bin/env bash
# msc-wizard.sh - interactive wizard that installs MSCLoader and/or the WreckMP multiplayer
# for My Summer Car on Linux (Steam + Proton). Works on any distribution (native, Flatpak or
# Snap Steam). Changes nothing without a warning. Every step checks whether it is already done,
# so you can stop with Ctrl+C and run it again.
#
# msc-wizard.sh - інтерактивний майстер встановлення MSCLoader та/або мультиплеєра WreckMP
# для My Summer Car на Linux (Steam + Proton). Працює на будь-якому дистрибутиві.
# Нічого не змінює без попередження. Кожен крок перевіряє, чи він уже зроблений.
#
#   bash msc-wizard.sh                language -> run type -> menu
#   bash msc-wizard.sh --dry-run      rehearsal: same questions, nothing is changed
#   bash msc-wizard.sh --status       show the state and check the setup (changes nothing)
#   bash msc-wizard.sh --steam-info   Steam cheat sheet: Proton, launch options, shortcut paths
#   bash msc-wizard.sh --tune         detect this PC's GPU/CPU and give matching Steam launch options
#   bash msc-wizard.sh --gpu-check   while the game runs: which renderer / GPU it really uses
#   bash msc-wizard.sh --fix-guid     repair: launcher registry + MachineGuid (after an update / moving the game)
#   bash msc-wizard.sh --fix-reg      fix WreckMP "register/registry not found" only
#   bash msc-wizard.sh --nonsteam     the game is NOT from Steam (Wine / Lutris / Bottles / Heroic / Steam shortcut)
#   bash msc-wizard.sh --game-dir P   game folder (otherwise found automatically); --prefix P = Wine prefix; --wine P = wine binary
#   bash msc-wizard.sh --lang uk|en   interface language (skips the question)
#   bash msc-wizard.sh --help         short help;  --readme = full manual
set -u

VERSION="2.4.0"
STEAM_APPID=516750
GAME_APPID=$STEAM_APPID
GAME_NAME="My Summer Car"
MSCL_VERSION="1.4.2"
LINK_WRECKMP="https://www.nexusmods.com/mysummercar/mods/5271"
URL_MSCLOADER="https://github.com/piotrulos/MSCModLoader/releases/download/v${MSCL_VERSION}/MSCLoader.zip"
URL_DOTNET="https://aka.ms/dotnet/6.0/windowsdesktop-runtime-win-x64.exe"
LINK_DOTNET="https://dotnet.microsoft.com/en-us/download/dotnet/6.0"
GAME_OPTS='WINEDLLOVERRIDES="winhttp=n,b" %command%'
LAUNCHER_OPTS='PROTON_USE_WINED3D=1 DOTNET_EnableWriteXorExecute=0 %command%'
WINE_OPTS='WINEDLLOVERRIDES="winhttp=n,b"'   # the same argument for a copy that is launched without Steam
PROTON_GAME="Proton 9.0 (Beta)"
PROTON_LAUNCHER="Proton 11.0"
PROTON_INSTALL="Proton 9.0 / Proton 9.0 (Beta)"
LAUNCHER_DIALOG="The game didn't start in 5 minutes"
WORK="${MSC_WIZARD_WORK:-$HOME/msc-wizard-work}"   # visible folder: Flatpak protontricks cannot see ~/.cache
SELF="$(basename "$0")"

UI="${MSC_WIZARD_LANG:-}"        # uk | en
GAME_DIR=""; LIB=""; COMPAT=""; DOTNET_EXE=""; PV_ASKED=""
# game copy: SRC_KIND = steam|other (what the user chose), GAME_SRC = steam|shortcut|wine (how it is run)
SRC_KIND=""; GAME_SRC=""; GAME_PFX=""; GAME_DIR_ARG=""; PFX_ARG=""; WINE_BIN="${MSC_WINE:-}"; WINESERVER_BIN=""
G_APPID=""; G_EXE=""; G_START=""; G_OPTS=""   # the game's own non-Steam shortcut (GAME_SRC=shortcut)
LA=""; L_APPID=""; L_NAME=""; L_EXE=""; L_START=""; L_OPTS=""
PT=(); PTL=()
# DRY=1: rehearsal, changes nothing.  DEMO=1: ignore already finished steps (show all of them)
DRY=0; DEMO=0
SIM_MSCL=0; SIM_WMP=0; SIM_DOTNET_GAME=0; SIM_DOTNET_LA=0; SIM_REG=0; SIM_GUID=0; SIM_HOSTS=0
DRY_LOG=()

# ================================================================== i18n
# m KEY "українською" "in English": printf format strings. Keep %s placeholders in the same
# order in both languages and never use a bare % sign.
declare -A UK=() EN=()
m() { UK["$1"]="$2"; EN["$1"]="$3"; }
t() {
  local k="$1" fmt; shift
  if [ "$UI" = en ]; then fmt="${EN[$k]-}"; else fmt="${UK[$k]-}"; fi
  [ -n "$fmt" ] || fmt="$k"
  # shellcheck disable=SC2059
  printf -- "$fmt" "$@"
}
detect_locale() {
  local l="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  case "$l" in uk*|UK*) echo uk ;; *) echo en ;; esac
}
set_lang() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    uk|ua|ukr|ukrainian|1) UI=uk ;;
    en|eng|english|2)      UI=en ;;
    *) return 1 ;;
  esac
}

# --- general
m press_enter   'Натисни Enter, коли готово... ' 'Press Enter when done... '
m back_to_menu  'Натисни Enter, щоб повернутись у меню... ' 'Press Enter to return to the menu... '
m interrupted   'Перервано. Запусти знову, продовжимо з того ж місця.' 'Interrupted. Run again to continue from where you left off.'
m banner        '%s на Linux: MSCLoader і мультиплеєр WreckMP, покроковий майстер (v%s)' '%s on Linux: MSCLoader and WreckMP multiplayer, step-by-step wizard (v%s)'
m real_banner   'Нічого не змінюється без попередження. Ctrl+C зупиняє, запуск знову продовжує.' 'Nothing changes without a warning. Ctrl+C stops; running again resumes where you stopped.'
m bad_choice    'Невідомий вибір: %s' 'Unknown choice: %s'
m choice_prompt 'Вибір [%s]: ' 'Choice [%s]: '
m dry_suffix    ' (у пробному режимі: умовно)' ' (dry run: simulated)'
m none_val      '(нічого)' '(nothing)'
m unset_val     '(не задано)' '(not set)'
m not_set       '(не вибрано)' '(not set)'
m word_game     'гри' 'game'
m word_launcher 'лаунчера' 'launcher'
m lang_name     'Українська' 'English'
m q_retry       'Спробувати ще раз?' 'Try again?'

# --- run type / dry run
m runtype_head  'Режим запуску:' 'Run type:'
m runtype_1     '1) Справжній: виконує установку (з попередженням перед кожною зміною)' '1) Real: performs the installation (warns before every change)'
m runtype_2     '2) Пробний (dry-run): ті самі запитання, але НІЧОГО не змінюється' '2) Dry run: the same questions, but NOTHING is changed'
m mode_real     'справжній' 'real'
m mode_dry      'ПРОБНИЙ (нічого не змінюється)' 'DRY RUN (nothing is changed)'
m dry_b1        '*** ПРОБНИЙ ЗАПУСК (--dry-run) ***' '*** DRY RUN (--dry-run) ***'
m dry_b2        'Запитання ті самі, шляхи й команди генеруються так само, але нічого не завантажується,' 'The questions are the same and paths/commands are generated the same way, but nothing is downloaded,'
m dry_b3        'не запускається, не пишеться на диск і не змінюється. Дії лише показуються як [DRY-RUN].' 'launched, written to disk or modified. Actions are only shown as [DRY-RUN].'
m dry_b4        'Поточний справжній стан системи тільки читається.' 'The real current state of the system is only read.'
m dry_demo_q    'Показати ВСІ кроки, навіть уже виконані у тебе?' 'Show ALL steps, even the ones you have already done?'
m dry_sum_head  'Пробний запуск завершено: НІЧОГО не змінено' 'Dry run finished: NOTHING was changed'
m dry_sum_none  'Жодної зміни не знадобилось би (усе вже налаштовано).' 'No change would be needed (everything is already set up).'
m dry_sum_n     'Справжній запуск виконав би таке (%s дій):' 'A real run would do the following (%s actions):'
m dry_sum_demo  '(Режим показу всіх кроків: наявні файли й налаштування ігнорувались, щоб показати кожен крок.)' '(Show-all-steps mode: existing files and settings were ignored so that every step is shown.)'

# --- menu
m menu_state    'Мова: %s   Режим: %s' 'Language: %s   Run type: %s'
m menu_head     'Що робимо?' 'What do we do?'
m menu_1        '1) Тільки MSCLoader (моди без мультиплеєра)' '1) MSCLoader only (mods without multiplayer)'
m menu_2        '2) Тільки WreckMP (MSCLoader уже стоїть)' '2) WreckMP only (MSCLoader is already installed)'
m menu_3        '3) Усе: MSCLoader + WreckMP' '3) Everything: MSCLoader + WreckMP'
m menu_4        '4) Показати стан і перевірити налаштування (нічого не змінює)' '4) Show the state and check the setup (changes nothing)'
m menu_5        '5) Шпаргалка Steam: Proton, параметри запуску, шляхи для ярлика' '5) Steam cheat sheet: Proton versions, launch options, shortcut paths'
m menu_6        '6) Полагодити після оновлення / переносу гри (реєстр лаунчера + MachineGuid)' '6) Repair after an update / moving the game (launcher registry + MachineGuid)'
m menu_7        '7) Налаштування: мова, режим запуску, папка гри, тип копії' '7) Settings: language, run type, game folder, game copy'
m menu_8        '8) Довідка / README' '8) Help / README'
m menu_0        '0) Вийти' '0) Quit'
m set_head      'Налаштування:' 'Settings:'
m set_1         '1) Мова' '1) Language'
m set_2         '2) Режим запуску (справжній / пробний)' '2) Run type (real / dry run)'
m set_3         '3) Папка гри (зараз: %s)' '3) Game folder (now: %s)'
m set_0         '0) Назад' '0) Back'

# --- game folder
m st_gamedir    'Папка гри' 'Game folder'
m q_gamedir     'Шлях до папки %s (Tab доповнює, q = скасувати):' 'Path to the %s folder (Tab completes, q = cancel):'
m gamedir_nf    'mysummercar.exe не знайдено в "%s". Спробуй ще раз.' 'mysummercar.exe not found in "%s". Try again.'
m gamedir_dryq  '(dry-run) Використати цей шлях попри це?' '(dry run) Use this path anyway?'
m gamedir_lib   'Копія зі Steam має лежати в бібліотеці Steam (.../steamapps/common/...). Якщо це копія НЕ зі Steam: Налаштування -> 4.' 'A Steam copy must be inside a Steam library (.../steamapps/common/...). If this is a copy NOT from Steam: Settings -> 4.'
m gamedir_dlib  '(пробний режим) шлях не в steamapps/common: Steam-бібліотеку підставляю умовно.' '(dry run) the path is not under steamapps/common: using a placeholder Steam library.'

# --- tools
m need_pt_1     'Не знайдено protontricks (потрібен, щоб запускати інсталятори всередині prefix-ів).' 'protontricks was not found (it is needed to run installers inside prefixes).'
m need_pt_2     'Для твого дистрибутиву:' 'For your distribution:'
m need_pt_3     'Або Flatpak:  flatpak install flathub com.github.Matoking.protontricks' 'Or Flatpak:  flatpak install flathub com.github.Matoking.protontricks'
m need_pt_dry   'Тут справжній запуск зупинився б із цією підказкою; у пробному режимі йду далі з умовною командою protontricks.' 'A real run would stop here with this hint; in dry run I continue with a placeholder protontricks command.'
m need_pt_4     'Встанови його (можна в іншому терміналі) і вибери пункт меню ще раз.' 'Install it (a second terminal is fine) and pick the menu item again.'

# --- idle / run in prefix
m idle_warn     'Зараз працюють процеси гри/Wine (це можуть бути й Wine-процеси інших програм):' 'Game/Wine processes are running (they may also belong to other Wine programs):'
m idle_dry      'Тут майстер запропонував би їх закрити (pkill) або зачекати.' 'Here the wizard would offer to close them (pkill) or wait.'
m q_idle        'Закрити їх зараз (гру, лаунчер і wineserver)?' 'Close them now (game, launcher and wineserver)?'
m idle_manual   'Закрий їх вручну.' 'Close them manually.'
m pv_1          'Інсталятори запускаються через protontricks. За замовчуванням береться Proton, вказаний у Steam для цього prefix-у.' 'Installers are run through protontricks. By default it uses the Proton selected in Steam for that prefix.'
m pv_2          'Встановлені Proton:' 'Installed Proton versions:'
m pv_3          'В автора інсталятори (MSCLoader, WreckMP) і .NET працювали з: %s.' 'In the author’s setup the installers (MSCLoader, WreckMP) and .NET worked with: %s.'
m pv_q          'Назва Proton для інсталяторів (Enter = за замовчуванням): ' 'Proton name for the installers (Enter = default): '
m run_dry       'Запустив би %s у prefix %s' 'Would run %s in prefix %s'
m run_now       'Запускаю %s у prefix %s ...' 'Running %s in prefix %s ...'
m act_mkwork    'Створити робочу теку %s' 'Create the work folder %s'
m act_fp        'Дозволити Flatpak-protontricks доступ до %s' 'Allow Flatpak protontricks to access %s'
m lt_pre        'WreckMP-лаунчер часто вилітає на старті через новини з patreon.com (в автора це лікувалось блоком у /etc/hosts). Краще заблокувати до першого запуску.' 'The WreckMP launcher often crashes at start because of the news fetched from patreon.com (the author fixed it with a block in /etc/hosts). Better to block it before the first launch.'

# --- Steam settings for the game
m st_gsettings  'Налаштування гри в Steam' 'Game settings in Steam'
m gs_already    'Launch Options і prefix гри вже є.' 'Launch Options and the game prefix are already in place.'
m gs_1          'У Steam: ПКМ на %s -> Властивості.' 'In Steam: right-click %s -> Properties.'
m gs_2          'Сумісність -> "Примусово використовувати певний інструмент сумісності Steam Play" -> %s' 'Compatibility -> "Force the use of a specific Steam Play compatibility tool" -> %s'
m gs_3          'Загальні -> Параметри запуску, встав точно це:' 'General -> Launch Options, paste exactly this:'
m gs_now        'Зараз у Steam: Proton = %s; Параметри запуску = %s' 'Currently in Steam: Proton = %s; Launch Options = %s'
m gs_dry_wait   'Тут майстер чекав би, поки Steam створить prefix гри (запуск гри один раз).' 'Here the wizard would wait for Steam to create the game prefix (launch the game once).'
m gs_pfx_found  'Prefix гри знайдено: %s' 'Game prefix found: %s'
m gs_wait       'Prefix гри ще не існує. Запусти гру зі Steam один раз, дочекайся головного меню, закрий гру.' 'The game prefix does not exist yet. Launch the game from Steam once, wait for the main menu, then close the game.'
m gs_pfx_ok     'Prefix гри знайдено.' 'Game prefix found.'
m clip_done     '(скопійовано в буфер обміну)' '(copied to the clipboard)'
m proton_ok     '[✓] %s: встановлено' '[✓] %s: installed'
m proton_missing '[ ] %s: не знайдено серед встановлених (зазвичай Steam сам завантажує версію, коли обрати її в списку сумісності)' '[ ] %s: not found among installed tools (Steam usually downloads a version by itself once you pick it in the compatibility list)'

# --- native leftovers / MSCLoader
m nl_warn       'Знайдено залишки нативного (Linux) експериментального MSCLoader:' 'Leftovers of the native (Linux) experimental MSCLoader were found:'
m nl_1          'В автора нативна версія не запустилась, і її довелось прибирати. Видали ці файли і в Steam зроби' 'The native version did not run for the author and had to be removed. Delete these files and in Steam run'
m nl_2          '"Перевірити цілісність файлів", інакше вони заважатимуть (майстер сам нічого не видаляє).' '"Verify integrity of game files", otherwise they will get in the way (the wizard deletes nothing by itself).'
m st_mscl       'MSCLoader %s (через MSCLInstaller.exe у prefix гри)' 'MSCLoader %s (via MSCLInstaller.exe in the game prefix)'
m mscl_have     'MSCLoader вже встановлено.' 'MSCLoader is already installed.'
m q_dl_mscl     'Завантажити MSCLoader %s з GitHub автоматично?' 'Download MSCLoader %s from GitHub automatically?'
m act_dl_mscl   'Завантажити MSCLoader' 'Download MSCLoader'
m mscl_manual   'Скачай MSCLoader.zip вручну (GitHub, акаунт не потрібен):' 'Download MSCLoader.zip manually (GitHub, no account needed):'
m q_path_mscl   'Шлях до MSCLoader.zip (Tab доповнює):' 'Path to MSCLoader.zip (Tab completes):'
m file_nf_dry   '(пробний режим) файл не знайдено: %s, але йду далі' '(dry run) file not found: %s, continuing anyway'
m file_nf       'Файл не знайдено: %s' 'File not found: %s'
m act_unzip     'Розпакував би %s у тимчасову теку %s' 'Would unzip %s into the temporary folder %s'
m mktemp_fail   'Не вдалося створити тимчасову теку.' 'Could not create a temporary folder.'
m unzip_fail    'Не вдалося розпакувати архів (потрібен unzip, python3 або bsdtar; можливо, файл завантажився пошкодженим).' 'Could not extract the archive (needs unzip, python3 or bsdtar; the download may be corrupted).'
m no_installer  'У архіві немає MSCLInstaller.exe.' 'MSCLInstaller.exe is not in the archive.'
m mscl_open_1   'Зараз відкриється інсталятор MSCLoader (у prefix гри %s).' 'The MSCLoader installer will open now (in game prefix %s).'
m mscl_open_2   'Якщо він питає папку гри, вкажи (Windows-шлях):' 'If it asks for the game folder, give (Windows path):'
m mscl_open_3   'У вікні інсталятора: "Install MSCLoader" -> кнопка "Select option"; папку для модів обери папку гри (так радить автор MSCLoader).' 'In the installer window: "Install MSCLoader" -> "Select option" button; pick the game folder as the Mods folder (recommended by the MSCLoader author).'
m mscl_missing  'Файли MSCLoader (winhttp.dll, doorstop_config.ini, MSCLoader.dll) у папці гри не з’явились.' 'The MSCLoader files (winhttp.dll, doorstop_config.ini, MSCLoader.dll) did not appear in the game folder.'
m mscl_need     'Без MSCLoader продовжувати не можна.' 'Cannot continue without MSCLoader.'
m mscl_done     'MSCLoader встановлено%s.' 'MSCLoader installed%s.'

# --- WreckMP
m st_wmp        'WreckMP' 'WreckMP'
m wmp_need_dry  '(пробний режим) MSCLoader не знайдено; справжній запуск тут зупинився б.' '(dry run) MSCLoader not found; a real run would stop here.'
m wmp_need      'Спершу потрібен MSCLoader (пункт меню 1 або 3).' 'MSCLoader is needed first (menu item 1 or 3).'
m wmp_have      'WreckMP вже в %s/WreckMP' 'WreckMP is already in %s/WreckMP'
m wmp_dl_1      'Скачай WreckMP у браузері (Nexus Mods, потрібен безкоштовний акаунт):' 'Download WreckMP in your browser (Nexus Mods, a free account is required):'
m wmp_dl_2      'Manual download. В автора це був інсталятор WreckMPsetup.exe (не ZIP); майстер розуміє обидва варіанти.' 'Use "Manual download". In the author’s case it was the WreckMPsetup.exe installer (not a ZIP); the wizard handles both.'
m q_path_wmp    'Шлях до скачаного файлу (Tab доповнює):' 'Path to the downloaded file (Tab completes):'
m act_unzip_wmp 'Розпакував би ZIP і скопіював вміст у %s/WreckMP' 'Would unzip the ZIP and copy its contents into %s/WreckMP'
m unzip_wmp_fail 'Не вдалося розпакувати ZIP.' 'Could not extract the ZIP.'
m wmp_exe_1     'Запускаю інсталятор у prefix гри. Інсталяція має лягти в папку гри (в автора вийшло %s/WreckMP).' 'Running the installer in the game prefix. It must install into the game folder (in the author’s case: %s/WreckMP).'
m wmp_exe_2     'Якщо інсталятор питає шлях, вкажи папку гри:' 'If the installer asks for a path, give the game folder:'
m bad_filetype  'Невідомий тип файлу (очікую .exe або .zip).' 'Unknown file type (expected .exe or .zip).'
m wmp_verify    'Після встановлення не знайдено ні Updater.exe, ні WreckMPLauncher.exe в %s/WreckMP (перевір структуру вручну і запусти майстер знову).' 'After the installation neither Updater.exe nor WreckMPLauncher.exe was found in %s/WreckMP (check the layout manually and run the wizard again).'
m wmp_done      'WreckMP встановлено%s.' 'WreckMP installed%s.'

# --- .NET
m st_dotnet     '.NET 6 Desktop Runtime у prefix %s (%s)' '.NET 6 Desktop Runtime in the %s prefix (%s)'
m dn_have       'Вже встановлено.' 'Already installed.'
m dn_note       'Не .NET Framework і не winetricks dotnet48: у автора вони не спрацювали. Потрібен саме .NET 6 Desktop Runtime.' 'Not .NET Framework and not winetricks dotnet48: they did not work for the author. You need exactly the .NET 6 Desktop Runtime.'
m dn_q_dl       'Завантажити .NET 6 Desktop Runtime (x64, ~55 МБ) автоматично з microsoft.com?' 'Download the .NET 6 Desktop Runtime (x64, ~55 MB) automatically from microsoft.com?'
m act_dl_dn     'Завантажити .NET 6 Desktop Runtime' 'Download the .NET 6 Desktop Runtime'
m dn_dl_fail    'Автоматично завантажити не вдалося.' 'The automatic download failed.'
m dn_manual     'Скачай "windowsdesktop-runtime-6.0.x-win-x64.exe" (.NET 6.0 Desktop Runtime, x64; в автора 6.0.36):' 'Download "windowsdesktop-runtime-6.0.x-win-x64.exe" (.NET 6.0 Desktop Runtime, x64; the author used 6.0.36):'
m dn_q_path     'Шлях до інсталятора:' 'Path to the installer:'
m dn_none       'Немає інсталятора .NET 6.' 'There is no .NET 6 installer.'
m dn_missing    '.NET 6 у prefix %s не знайдено.' '.NET 6 was not found in prefix %s.'
m dn_need       'Без .NET 6 лаунчер/мод не працюватимуть.' 'The launcher/mod will not work without .NET 6.'
m dn_done       '.NET 6 встановлено в prefix %s%s.' '.NET 6 installed in prefix %s%s.'

# --- updater, shortcut
m st_updater    'Updater.exe в prefix гри' 'Updater.exe in the game prefix'
m up_note       'Цей крок НЕОБОВ’ЯЗКОВИЙ і за замовчуванням пропускається (prefix гри %s). Запуск Updater.exe через protontricks може закінчитись помилкою, а через ярлик у Steam (Proton лаунчера) він працює. Чи потрібен цей запуск взагалі, не перевірено. Відповідай y, лише якщо хочеш спробувати.' 'This step is OPTIONAL and skipped by default (game prefix %s). Running Updater.exe through protontricks may fail, while through the Steam shortcut (the launcher Proton) it works. Whether this run is needed at all has not been verified. Answer y only if you want to try.'
m q_up          'Запустити Updater.exe в prefix гри?' 'Run Updater.exe in the game prefix?'
m up_wait       'Дочекайся, поки він закінчить роботу, і закрий вікно.' 'Wait until it finishes, then close the window.'
m st_shortcut   'Додати лаунчер у Steam' 'Add the launcher to Steam'
m no_entry      'Не знайдено Updater.exe/WreckMPLauncher.exe.' 'Updater.exe/WreckMPLauncher.exe was not found.'
m sc_1          'Steam -> Ігри -> "Додати стороннюю гру до моєї бібліотеки" -> Огляд...' 'Steam -> Games -> "Add a Non-Steam Game to My Library" -> Browse...'
m sc_2          'У діалозі виберіть тип файлів "Усі файли" і виберіть:' 'In the dialog set the file type to "All files" and pick:'
m sc_3          'Натисни "Додати вибрані програми".' 'Click "Add Selected Programs".'
m sc_4          'ПКМ на новому записі -> Властивості. Заповнюй поля по черзі.' 'Right-click the new entry -> Properties. Fill in the fields one by one.'
m sc_5          '1) Назва (будь-яка, наприклад WreckMPLauncher) і Ціль (Target) має бути точно:' '1) Name (anything, e.g. WreckMPLauncher); Target must be exactly:'
m sc_6          '2) Почати в (Start In):' '2) Start In:'
m sc_7          '3) Параметри запуску:' '3) Launch Options:'
m sc_8          '(Так було в автора. Чи потрібна кожна змінна окремо, не перевірено.)' '(This is how the author had it. Whether each variable is needed on its own has not been verified.)'
m sc_9          '4) Сумісність -> примусово -> %s (версія, яку перевірив автор).' '4) Compatibility -> force -> %s (the version the author tested).'

# --- first launcher start / verification
m st_first      'Перший запуск ярлика лаунчера (Steam створює його prefix)' 'First launch of the launcher shortcut (Steam creates its prefix)'
m fs_1          'Запусти новий ярлик зі Steam один раз. Він може вилетіти або показати помилку через відсутній .NET: це нормально,' 'Launch the new shortcut from Steam once. It may crash or show an error about missing .NET: that is fine,'
m fs_2          'Steam має лише створити prefix. Закрий вікно, якщо воно лишилось.' 'Steam only has to create the prefix. Close the window if it stays open.'
m fs_found      'Prefix лаунчера визначено за shortcuts.vdf: %s' 'Launcher prefix detected from shortcuts.vdf: %s'
m fs_notfound   'Не вдалося визначити prefix за shortcuts.vdf (Steam міг ще не записати ярлик; закрий і відкрий Steam).' 'Could not detect the prefix from shortcuts.vdf (Steam may not have written the shortcut yet; close and reopen Steam).'
m fs_cands      'Prefix-теки, крім гри, найновіші першими:' 'Prefix folders other than the game, newest first:'
m fs_q          'Номер prefix-у лаунчера: ' 'Launcher prefix number: '
m fs_dry_none   '(пробний режим) prefix "%s" не існує; далі підставляю умовний номер.' '(dry run) prefix "%s" does not exist; using a placeholder number.'
m fs_nosuch     'Немає такого prefix-у: "%s". Запусти ярлик зі Steam і спробуй знову.' 'No such prefix: "%s". Launch the shortcut from Steam and try again.'
m vf_target_ok  'Target ярлика збігається: %s' 'Shortcut Target matches: %s'
m vf_target_bad 'Target ярлика інший: "%s" (очікується "%s")' 'Shortcut Target differs: "%s" (expected "%s")'
m vf_start_ok   'Start In ярлика збігається.' 'Shortcut Start In matches.'
m vf_start_bad  'Start In ярлика інший: "%s" (очікується "%s")' 'Shortcut Start In differs: "%s" (expected "%s")'
m vf_opts_ok    'Параметри запуску ярлика збігаються.' 'Shortcut Launch Options match.'
m vf_opts_bad   'Параметри запуску ярлика інші: "%s" (очікується "%s")' 'Shortcut Launch Options differ: "%s" (expected "%s")'
m vf_proton     'Proton для ярлика: %s (в автора: %s)' 'Proton for the shortcut: %s (the author used: %s)'
m vf_proton_none 'Proton для ярлика не заданий примусово (в автора: %s)' 'Proton is not forced for the shortcut (the author used: %s)'
m vf_flush      '(Steam записує зміни у свої файли при виході: якщо поля щойно змінено, закрий Steam і перевір знову через --status)' '(Steam writes changes to its files on exit: if you just changed the fields, close Steam and check again with --status)'

# --- launcher test / patreon
m st_ltest      'Перевірка лаунчера' 'Launcher check'
m lt_1          'Запусти ярлик лаунчера зі Steam. Дочекайся вікна з новинами, потім закрий його.' 'Launch the launcher shortcut from Steam. Wait for the news window, then close it.'
m q_lt          'Вікно лаунчера відкрилось нормально?' 'Did the launcher window open normally?'
m lt_1w         'Запусти лаунчер командою вище (або start-wreckmp.sh). Дочекайся вікна з новинами, потім закрий його.' 'Start the launcher with the command above (or start-wreckmp.sh). Wait for the news window, then close it.'
m lt_hosts      'patreon.com уже заблоковано, тож причина інша. Подивись %s/WreckMP/startup_debug.log і conn.log.' 'patreon.com is already blocked, so the cause is different. Look at %s/WreckMP/startup_debug.log and conn.log.'
m lt_crash      'Якщо лаунчер вилітає на старті (c0000005 у wininet після Patreon cookie), в автора це лікувалось блоком patreon.com в /etc/hosts.' 'If the launcher crashes at start (c0000005 in wininet after the Patreon cookie), the author fixed it by blocking patreon.com in /etc/hosts.'
m lt_retry      'Запусти лаунчер ще раз і перевір, чи вікно відкрилось.' 'Launch the launcher again and check whether the window opens.'
m lt_skip       'Пропущено.' 'Skipped.'
m bp_1          'Додам у /etc/hosts (потрібен sudo):' 'I will add to /etc/hosts (needs sudo):'
m bp_2          'Побічний ефект: patreon.com перестане відкриватись у браузері. Скасувати:' 'Side effect: patreon.com will stop opening in your browser. To undo:'
m bp_3          '(Якщо /etc/hosts у тебе керується декларативно, наприклад NixOS, додай ці рядки у конфігурацію.)' '(If your /etc/hosts is managed declaratively, e.g. on NixOS, add these lines to your configuration instead.)'
m q_bp          'Додати блок зараз?' 'Add the block now?'
m act_hosts     'Дописав би два рядки в /etc/hosts (через sudo)' 'Would append two lines to /etc/hosts (via sudo)'
m bp_nosudo     'sudo/doas/pkexec не знайдено: додай ці два рядки в /etc/hosts вручну від імені root.' 'sudo/doas/pkexec not found: add these two lines to /etc/hosts manually as root.'
m bp_failed     'Не вдалося дописати в /etc/hosts (NixOS: додай networking.extraHosts у конфігурацію; SteamOS: спершу sudo steamos-readonly disable).' 'Could not append to /etc/hosts (NixOS: use networking.extraHosts in your configuration; SteamOS: run sudo steamos-readonly disable first).'

# --- registry / GUID
m st_reg        'Папка гри в реєстрі лаунчера' 'Game folder in the launcher registry'
m reg_have      'Запис WreckMP у реєстрі prefix-у %s вже є.' 'The WreckMP registry entry in prefix %s already exists.'
m act_reg_w     'Записав би файл %s з таким вмістом:' 'Would write the file %s with this content:'
m act_reg_i     'Імпортував би його в prefix %s' 'Would import it into prefix %s'
m reg_note      'Імпортую %s у prefix %s (в автора такий запис був; чи потрібен, не перевірено).' 'Importing %s into prefix %s (the author had such an entry; whether it is required has not been verified).'
m reg_ok        'Записано.' 'Written.'
m reg_bad       'Запис не з’явився в user.reg; перевір вручну.' 'The entry did not appear in user.reg; check manually.'
m reg_direct    'Записую шлях до гри прямо в реєстр prefix-у %s (без protontricks).' 'Writing the game path straight into the registry of prefix %s (no protontricks needed).'
m reg_fixed     'Лаунчер WreckMP (prefix %s): шлях до гри виправлено → %s' 'WreckMP launcher (prefix %s): game path fixed → %s'
m reg_fix_ok    'Шляхи до гри в реєстрі лаунчера WreckMP правильні.' 'The game path in the WreckMP launcher registry is correct.'
m reg_fix_busy  'Гра / лаунчер / Wine зараз працюють: реєстр не чіпаю (закрий їх і запусти: bash %s --fix-reg).' 'The game / launcher / Wine are running: registry left untouched (close them and run: bash %s --fix-reg).'
m reg_fix_none  'Не знайдено жодного ярлика WreckMP зі створеним prefix-ом (запусти лаунчер зі Steam один раз).' 'No WreckMP shortcut with an existing prefix was found (start the launcher from Steam once).'
m st_regfix     'Перевірка реєстру лаунчера WreckMP («register/registry not found»)' 'Checking the WreckMP launcher registry ("register/registry not found")'
m no_la         'Не знайдено prefix лаунчера (ярлик у Steam?).' 'Launcher prefix not found (is the shortcut in Steam?).'
m st_guid       'MachineGuid гри і лаунчера' 'MachineGuid of the game and the launcher'
m guid_intro    'Лаунчер і мод у грі мають бачити один і той самий MachineGuid, а prefix-и в них різні.' 'The launcher and the in-game mod must see the same MachineGuid, but their prefixes are different.'
m guid_dry_nd   'MachineGuid прочитати не вдалося (prefix-а ще немає або умовний). Справжній запуск тут вирівняв би їх.' 'Could not read MachineGuid (the prefix does not exist yet or is a placeholder). A real run would align them here.'
m guid_nol      'Не знайшов MachineGuid у prefix-і лаунчера (%s).' 'MachineGuid not found in the launcher prefix (%s).'
m guid_nog      'Не знайшов MachineGuid у prefix-і гри (%s).' 'MachineGuid not found in the game prefix (%s).'
m guid_same     'MachineGuid однакові (%s).' 'MachineGuid values are identical (%s).'
m guid_l        'MachineGuid лаунчера: %s' 'Launcher MachineGuid: %s'
m guid_g        'MachineGuid гри:      %s' 'Game MachineGuid:     %s'
m guid_close    'Закрий Steam, гру й лаунчер повністю. Копію system.reg буде збережено поруч.' 'Close Steam, the game and the launcher completely. A backup of system.reg will be saved next to it.'
m act_guid_bak  'Зробив би копію %s' 'Would make a backup %s'
m act_guid_sed  'Замінив би MachineGuid гри на %s' 'Would replace the game MachineGuid with %s'
m guid_bakfail  'Не вдалось зробити копію.' 'Could not make a backup.'
m guid_done     'Готово. Копія: %s' 'Done. Backup: %s'
m guid_fail     'Не вдалося замінити. Копія: %s' 'Replacement failed. Backup: %s'

# --- status
m st_title      'Стан і перевірка' 'Status and checks'
m ck_pt         'protontricks знайдено' 'protontricks found'
m ck_py         'python3 знайдено (читає налаштування Steam)' 'python3 found (reads the Steam settings)'
m ck_dl         'curl або wget знайдено (автозавантаження)' 'curl or wget found (automatic download)'
m ck_unzip      'unzip, bsdtar або python3 знайдено (розпакування)' 'unzip, bsdtar or python3 found (extraction)'
m ck_prefix     'Prefix гри (%s) існує' 'Game prefix (%s) exists'
m ck_lo         'Launch Options гри з winhttp (за localconfig.vdf)' 'Game Launch Options contain winhttp (per localconfig.vdf)'
m ck_mscl       'MSCLoader встановлено (winhttp.dll, Doorstop, dll)' 'MSCLoader installed (winhttp.dll, Doorstop, dll)'
m ck_wmp        'WreckMP встановлено (%s/WreckMP)' 'WreckMP installed (%s/WreckMP)'
m ck_short      'Ярлик лаунчера в Steam + його prefix%s' 'Launcher shortcut in Steam + its prefix%s'
m ck_target     'Target ярлика вказує на існуючий файл WreckMP' 'Shortcut Target points to an existing WreckMP file'
m ck_start      'Start In ярлика = тека Target' 'Shortcut Start In = the Target folder'
m ck_lopts      'Launch Options ярлика (PROTON_USE_WINED3D, DOTNET_EnableWriteXorExecute)' 'Shortcut Launch Options (PROTON_USE_WINED3D, DOTNET_EnableWriteXorExecute)'
m ck_dn_game    '.NET 6 Desktop Runtime у prefix гри' '.NET 6 Desktop Runtime in the game prefix'
m ck_dn_la      '.NET 6 Desktop Runtime у prefix лаунчера' '.NET 6 Desktop Runtime in the launcher prefix'
m ck_hosts      'patreon.com заблоковано в /etc/hosts' 'patreon.com is blocked in /etc/hosts'
m ck_reg        'Папка гри записана в реєстр лаунчера' 'Game folder is written to the launcher registry'
m ck_guid       'MachineGuid гри = MachineGuid лаунчера' 'Game MachineGuid = launcher MachineGuid'
m inf_pg        'Proton у Steam для гри: %s (в автора: %s)' 'Proton in Steam for the game: %s (the author used: %s)'
m inf_pl        'Proton у Steam для лаунчера: %s (в автора: %s)' 'Proton in Steam for the launcher: %s (the author used: %s)'
m st_hint       'Пункт "[ ]" не завжди помилка: деякі кроки потрібні лише для мультиплеєра (патч patreon.com лише якщо лаунчер вилітає).' 'A "[ ]" is not always an error: some steps are only for multiplayer (the patreon.com block is only needed if the launcher crashes).'

# --- cheat sheet
m st_cheat      'Шпаргалка: що вписати в Steam' 'Cheat sheet: what to enter in Steam'
m ch_a          'A) Гра "%s"  (ПКМ -> Властивості)' 'A) The game "%s"  (right-click -> Properties)'
m ch_compat     'Сумісність -> примусово -> %s' 'Compatibility -> force -> %s'
m ch_opts       'Параметри запуску (Launch Options):' 'Launch Options:'
m ch_now_p      'зараз у Steam, Proton: %s' 'currently in Steam, Proton: %s'
m ch_now_o      'зараз у Steam, параметри: %s' 'currently in Steam, options: %s'
m ch_b          'B) Лаунчер WreckMP  (Steam -> Ігри -> Додати стороннюю гру -> Огляд -> "Усі файли")' 'B) The WreckMP launcher  (Steam -> Games -> Add a Non-Steam Game -> Browse -> "All files")'
m ch_b_file     'Файл, який вибрати:' 'File to pick:'
m ch_b_guess    '(WreckMP ще не встановлено: шлях орієнтовний)' '(WreckMP is not installed yet: the path is approximate)'
m ch_target     'Ціль (Target), з лапками:' 'Target, with the quotes:'
m ch_start      'Почати в (Start In), з лапками:' 'Start In, with the quotes:'
m ch_now_t      'зараз у Steam, Target: %s' 'currently in Steam, Target: %s'
m ch_now_s      'зараз у Steam, Start In: %s' 'currently in Steam, Start In: %s'
m ch_c          'C) Інсталятори, які майстер запускає через protontricks' 'C) Installers that the wizard runs through protontricks'
m ch_c1         'Proton для них (як в автора): %s' 'Proton for them (as the author used): %s'
m ch_flush      'Steam записує зміни у свої файли при виході: якщо поля щойно змінено, закрий Steam і подивись знову.' 'Steam writes changes to its files on exit: if you just changed the fields, close Steam and look again.'

# --- big warning (all caps on purpose)
m caps_head     'УВАГА! ПРОЧИТАЙ ПЕРЕД ГРОЮ ПО МЕРЕЖІ!' 'ATTENTION! READ BEFORE PLAYING ONLINE!'
m caps_1        'ПІСЛЯ ЗАПУСКУ ГРИ З МУЛЬТИПЛЕЄРОМ РЕКОМЕНДУЄТЬСЯ\nЗАКРИТИ ЛАУНЧЕР WRECKMP. ІНАКШЕ ЧЕРЕЗ 5 ХВИЛИН З’ЯВИТЬСЯ\nВІКНО "%s":\nПРОСТО НАТИСНИ OK, ГРА ВІД ЦЬОГО НЕ СТРАЖДАЄ.' 'AFTER STARTING THE GAME WITH MULTIPLAYER IT IS RECOMMENDED\nTO CLOSE THE WRECKMP LAUNCHER. OTHERWISE AFTER 5 MINUTES A\nWINDOW "%s" APPEARS:\nJUST PRESS OK, THE GAME IS NOT AFFECTED.'
m caps_2        'НЕ ПЕРЕВІРЕНО, ЧИ ПРАЦЮЄ МУЛЬТИПЛЕЄР БЕЗ ЛАУНЧЕРА.\nЯКЩО ЩОСЬ ЛАМАЄТЬСЯ - ТРИМАЙ ЛАУНЧЕР ВІДКРИТИМ.' 'IT IS NOT VERIFIED THAT MULTIPLAYER WORKS WITHOUT THE LAUNCHER.\nIF ANYTHING BREAKS - KEEP THE LAUNCHER OPEN.'
m caps_3        'ГРУ З МУЛЬТИПЛЕЄРОМ ЗАПУСКАЙ З ЯРЛИКА ЛАУНЧЕРА\n(КНОПКА PLAY): ЛАУНЧЕР САМ ЗАПУСКАЄ ГРУ.' 'START THE GAME WITH MULTIPLAYER FROM THE LAUNCHER SHORTCUT\n(PLAY BUTTON): THE LAUNCHER STARTS THE GAME ITSELF.'
m caps_4        'ПІСЛЯ ОНОВЛЕННЯ PROTON/STEAM ЗАПУСТИ:' 'AFTER A PROTON/STEAM UPDATE RUN:'

# --- recap
m st_done       'Готово' 'Done'
m rc_steam      'Налаштування в Steam' 'Settings in Steam'
m rc_game       '%s ....... %s   Параметри запуску: %s' '%s ....... %s   Launch Options: %s'
m rc_launcher   'WreckMP-лаунчер ..... %s  Параметри запуску: %s' 'WreckMP launcher ..... %s  Launch Options: %s'
m rc_how        'Як користуватись' 'How to use it'
m rc_1_1        '1. Запускай гру зі Steam як зазвичай. Моди розпаковуй у папку Mods, яку обрав в інсталяторі (рекомендовано: папка гри).' '1. Launch the game from Steam as usual. Unpack mods into the Mods folder you picked in the installer (recommended: the game folder).'
m rc_1_2        '2. У головному меню має бути MSCLoader (в output_log.txt: "MSCLoader v%s").' '2. The main menu should show MSCLoader (output_log.txt: "MSCLoader v%s").'
m rc_2_1        '1. Запусти ярлик лаунчера зі Steam і натисни Play. Лаунчер запускає гру.' '1. Launch the launcher shortcut from Steam and press Play. The launcher starts the game.'
m rc_2_2        '2. Лаунчер далі показує крапки: це очікувано (він не бачить гру, вона в іншому prefix-і).' '2. The launcher keeps showing dots: this is expected (it cannot see the game, which lives in another prefix).'
m rc_2_3        'Через 5 хвилин з’явиться "%s": натисни OK. Гра не страждає.' 'After 5 minutes "%s" appears: press OK. The game is not affected.'
m rc_2_4        '3. Коли гра вже запущена, лаунчер краще закрити, щоб не було цього вікна.' '3. Once the game is running it is better to close the launcher so that this window does not appear.'
m rc_2_5        'НЕ ПЕРЕВІРЕНО, чи працює мультиплеєр без лаунчера. Якщо щось ламається, тримай його відкритим.' 'NOT VERIFIED whether multiplayer works without the launcher. If something breaks, keep it open.'
m rc_2_6        '4. Після оновлення Proton/Steam запусти:  bash %s --fix-guid' '4. After a Proton/Steam update run:  bash %s --fix-guid'
m rc_dont       'Не роби: нативний Linux-MSCLoader (experimental) і winetricks dotnet48: в автора вони не спрацювали.' 'Do not use: the native Linux MSCLoader (experimental) and winetricks dotnet48: they did not work for the author.'
m rc_more       'Шпаргалка Steam: bash %s --steam-info    Довідка: bash %s --help' 'Steam cheat sheet: bash %s --steam-info    Help: bash %s --help'

# --- game copy (Steam / not from Steam), Wine mode, distributions
m src_head      'Яка у тебе копія гри?' 'Which copy of the game do you have?'
m src_1         '1) Зі Steam (встановлена через Steam)' '1) From Steam (installed through Steam)'
m src_2         '2) НЕ зі Steam (скачана окремо: архів, інший магазин тощо)' '2) NOT from Steam (downloaded separately: an archive, another store, etc.)'
m src_name_steam    'зі Steam' 'from Steam'
m src_name_shortcut 'не Steam, запуск через ярлик у Steam' 'not Steam, launched through a Steam shortcut'
m src_name_wine     'не Steam, Wine-prefix' 'not Steam, Wine prefix'
m menu_src      'Копія гри: %s' 'Game copy: %s'
m set_4         '4) Копія гри (Steam / не Steam)' '4) Game copy (Steam / not Steam)'
m fnd_search    'Шукаю автоматично (може тривати кілька секунд)...' 'Searching automatically (may take a few seconds)...'
m fnd_none      'Автоматично нічого не знайдено; введи шлях вручну.' 'Nothing found automatically; enter the path manually.'
m fnd_one       'Знайдено: %s' 'Found: %s'
m fnd_list      'Знайдені копії гри:' 'Game copies found:'
m fnd_pick      'Номер (Enter = %s, 0 = ввести вручну): ' 'Number (Enter = %s, 0 = enter manually): '
m how_head      'Як ти запускаєш цю копію гри?' 'How do you launch this copy of the game?'
m how_1         '1) Через Steam (як "стороння гра"; майстер підкаже, як додати)' '1) Through Steam (as a "non-Steam game"; the wizard shows how to add it)'
m how_2         '2) Без Steam: Wine / Lutris / Bottles / Heroic / командний рядок' '2) Without Steam: Wine / Lutris / Bottles / Heroic / command line'
m sc_found      'Гра вже додана в Steam як стороння: appid %s (prefix %s)' 'The game is already added to Steam as a non-Steam game: appid %s (prefix %s)'
m no_steam      'Steam не знайдено (немає теки steamapps). Для копії без Steam обери запуск через Wine.' 'Steam was not found (no steamapps folder). For a copy without Steam pick the Wine launch type.'
m gsc_nolink    'Steam ще не записав ярлик у shortcuts.vdf (закрий і знову відкрий Steam, тоді Enter).' 'Steam has not written the shortcut to shortcuts.vdf yet (close and reopen Steam, then Enter).'
m pfx_found     'Wine-prefix гри: %s' 'Game Wine prefix: %s'
m pfx_cands     'Знайдені Wine-prefix-и:' 'Wine prefixes found:'
m pfx_q         'Шлях до Wine-prefix (тека з system.reg; Tab доповнює, q = скасувати):' 'Path to the Wine prefix (the folder with system.reg; Tab completes, q = cancel):'
m pfx_bad       'У "%s" немає system.reg: це не Wine-prefix (створити новий: WINEPREFIX=<шлях> wineboot -u).' 'There is no system.reg in "%s": not a Wine prefix (to create one: WINEPREFIX=<path> wineboot -u).'
m pfx_dry_bad   '(пробний режим) іду далі з цим шляхом.' '(dry run) continuing with this path.'
m ck_wine       'wine знайдено' 'wine found'
m ck_pfx_wine   'Wine-prefix гри існує (%s)' 'Game Wine prefix exists (%s)'
m need_wine_1   'Не знайдено wine (потрібен, щоб запускати інсталятори у Wine-prefix).' 'wine was not found (it is needed to run installers in a Wine prefix).'
m need_wine_hint 'Можна вказати свій: --wine /шлях/до/wine (Lutris, Bottles, Proton) або змінна MSC_WINE.' 'You can point to your own: --wine /path/to/wine (Lutris, Bottles, Proton) or the MSC_WINE variable.'
m need_wine_dry 'Тут справжній запуск зупинився б; у пробному режимі йду далі з умовною командою wine.' 'A real run would stop here; in dry run I continue with a placeholder wine command.'
m wine_cands    'Знайдені збірки Wine/Proton:' 'Wine/Proton builds found:'
m wine_pick     'Номер (Enter = %s): ' 'Number (Enter = %s): '
m wine_using    'Wine: %s' 'Wine: %s'
m ws_intro      'Копія запускається не через Steam, тому аргумент запуску треба задати там, звідки ти її запускаєш.' 'The copy is not launched through Steam, so the launch argument must be set where you start it from.'
m ws_pfx        'Wine-prefix: %s' 'Wine prefix: %s'
m ws_exe        'Гра: %s' 'Game: %s'
m ws_arg        'Аргумент (змінна оточення) для гри:' 'Argument (environment variable) for the game:'
m ws_lutris     'Lutris: Configure -> System options -> Environment variables: WINEDLLOVERRIDES = winhttp=n,b' 'Lutris: Configure -> System options -> Environment variables: WINEDLLOVERRIDES = winhttp=n,b'
m ws_bottles    'Bottles: Settings -> Environment variables: WINEDLLOVERRIDES = winhttp=n,b' 'Bottles: Settings -> Environment variables: WINEDLLOVERRIDES = winhttp=n,b'
m ws_heroic     'Heroic: Game settings -> Advanced -> Environment variables: WINEDLLOVERRIDES = winhttp=n,b' 'Heroic: Game settings -> Advanced -> Environment variables: WINEDLLOVERRIDES = winhttp=n,b'
m ws_cmd        'Командний рядок (шляхи підставлено автоматично):' 'Command line (paths filled in automatically):'
m ws_script_q   'Створити скрипт запуску %s?' 'Create the start script %s?'
m ws_script_have 'Скрипт уже існує: %s' 'The script already exists: %s'
m ws_script_done 'Скрипт створено: %s' 'Script created: %s'
m act_script    'Створив би скрипт запуску %s' 'Would create the start script %s'
m ws_pfx_missing 'У prefix-і ще немає system.reg. Запусти гру (або winecfg) один раз, закрий і натисни Enter.' 'The prefix has no system.reg yet. Run the game (or winecfg) once, close it and press Enter.'
m st_lwine      'Лаунчер WreckMP у Wine-prefix' 'WreckMP launcher in the Wine prefix'
m lw_1          'Лаунчер ділить prefix з грою (окремий ярлик Steam не потрібен), тому MachineGuid збігається сам.' 'The launcher shares the prefix with the game (no separate Steam shortcut needed), so MachineGuid matches by itself.'
m lw_2          'Команда лаунчера (шляхи підставлено автоматично):' 'Launcher command (paths filled in automatically):'
m lw_3          'У Lutris/Bottles/Heroic додай Updater.exe як окрему програму з тим самим prefix-ом.' 'In Lutris/Bottles/Heroic add Updater.exe as a separate program using the same prefix.'
m lw_4          'НЕ ПЕРЕВІРЕНО на справжній системі: в автора було два prefix-и у Steam.' 'NOT VERIFIED on a real system: the author used two prefixes in Steam.'
m st_cheat_w    'Шпаргалка: запуск без Steam (Wine)' 'Cheat sheet: launching without Steam (Wine)'
m guid_wine     'У Wine-режимі гра й лаунчер в одному prefix-і: вирівнювати MachineGuid не потрібно.' 'In Wine mode the game and the launcher share one prefix: there is nothing to align.'
m rcw_1         '1. Запусти гру цією командою (або start-msc.sh). Аргумент winhttp=n,b обов’язковий для MSCLoader:' '1. Start the game with this command (or start-msc.sh). The winhttp=n,b argument is required for MSCLoader:'
m rcw_2         '2. Для мультиплеєра запусти лаунчер (або start-wreckmp.sh) і натисни Play:' '2. For multiplayer start the launcher (or start-wreckmp.sh) and press Play:'
m rcw_3         '3. У Lutris/Bottles/Heroic задай WINEDLLOVERRIDES=winhttp=n,b у налаштуваннях гри.' '3. In Lutris/Bottles/Heroic set WINEDLLOVERRIDES=winhttp=n,b in the game settings.'
m rcw_4         'НЕ ПЕРЕВІРЕНО на справжній системі: Wine-режим складений за логікою, в автора був Steam із двома prefix-ами.' 'NOT VERIFIED on a real system: Wine mode follows the same logic, but the author used Steam with two prefixes.'
m inf_distro    'Дистрибутив: %s (пакетний менеджер: %s)' 'Distro: %s (package manager: %s)'
m inf_src       'Копія гри: %s' 'Game copy: %s'
m dep_miss      'Бракує: %s. Встановлення: %s' 'Missing: %s. Install: %s'

# --- PC tuning
m menu_9        '9) Оптимізація під цей ПК: визначити залізо й дати параметри запуску' '9) Tune for this PC: detect the hardware and give launch options'
m st_tune       'Оптимізація під цей ПК' 'Tune for this PC'
m st_gcheck     'Перевірка запущеної гри: який рендерер і яка відеокарта' 'Check the running game: which renderer and which GPU'
m tune_hw_head  'Знайдене залізо (тільки читання):' 'Detected hardware (read only):'
m tune_os       '  Система: %s (пакетний менеджер: %s)' '  System: %s (package manager: %s)'
m tune_cpu      '  Процесор: %s, потоків: %s' '  CPU: %s, threads: %s'
m tune_ram      '  Пам’ять: %s ГБ' '  RAM: %s GB'
m tune_sess     '  Сесія: %s' '  Session: %s'
m tune_gpu      '  GPU %s: %s [%s, драйвер: %s, VRAM: %s]' '  GPU %s: %s [%s, driver: %s, VRAM: %s]'
m tune_nogpu    'GPU не знайдено в /sys/class/drm (контейнер або дивна система). Параметри будуть базовими.' 'No GPU found in /sys/class/drm (container or unusual system). Options will be basic.'
m tune_deck     '  Це Steam Deck: окремі змінні не потрібні.' '  This is a Steam Deck: no extra variables are needed.'
m tune_sandbox  '  Steam у Flatpak/Snap: gamemode не додається (він недоступний у пісочниці), скрипт лежить у теці гри.' '  Steam is a Flatpak/Snap: gamemode is not added (unavailable in the sandbox); the script lives in the game folder.'
m tune_prof_nvidia '  Профіль: NVIDIA з пропрієтарним драйвером.' '  Profile: NVIDIA with the proprietary driver.'
m tune_prof_mesa   '  Профіль: Mesa (AMD / Intel / nouveau).' '  Profile: Mesa (AMD / Intel / nouveau).'
m tune_prof_deck   '  Профіль: Steam Deck.' '  Profile: Steam Deck.'
m tune_prof_vm     '  Профіль: віртуальна машина (немає справжнього GPU).' '  Profile: virtual machine (no real GPU).'
m tune_prof_unknown '  Профіль: невідомо.' '  Profile: unknown.'
m tune_hybrid   '  Гібридна графіка: гра примусово піде на %s.' '  Hybrid graphics: the game will be forced onto %s.'
m tune_soft     'Справжнього GPU не видно: гра рендеритиметься програмно (дуже повільно). Перевір драйвери.' 'No real GPU is visible: the game would render in software (very slow). Check the drivers.'
m tune_nouveau  'Є NVIDIA, але з драйвером nouveau: з ним мало FPS. Встанови пропрієтарний драйвер NVIDIA, тоді запусти це знову.' 'An NVIDIA card is present but runs on nouveau, which is slow. Install the proprietary NVIDIA driver and run this again.'
m tune_lowram   'Менше 7 ГБ RAM: закрий браузер перед грою, інакше будуть лаги від свопу.' 'Under 7 GB of RAM: close the browser before playing, or swapping will cause lag.'
m tune_nogm     'gamemode не встановлено (необов’язково, трохи допомагає з частотами CPU). Встановлення:' 'gamemode is not installed (optional, helps a little with CPU clocks). Install:'
m tune_badpath  'Шлях гри містить лапки, $ або зворотний слеш і не підходить для Launch Options: %s. Перемісти гру або перейменуй теки.' 'The game path contains quotes, $ or a backslash and cannot go into Launch Options: %s. Move the game or rename the folders.'
m act_tune_script 'Створив би скрипт перемикача й автозакриття лаунчера: %s' 'Would create the mode switch and launcher auto-close script: %s'
m act_tune_ds   'Створив би doorstop_config_vanilla.ini і doorstop_config_wmp.bak з поточного doorstop_config.ini' 'Would create doorstop_config_vanilla.ini and doorstop_config_wmp.bak from the current doorstop_config.ini'
m tune_ds_have  'Файли doorstop_config_vanilla.ini і doorstop_config_wmp.bak вже є, не чіпаю.' 'doorstop_config_vanilla.ini and doorstop_config_wmp.bak already exist, leaving them alone.'
m tune_ds_noini 'doorstop_config.ini немає: спершу встанови MSCLoader (пункт 1). Файли режимів не створено.' 'doorstop_config.ini is missing: install MSCLoader first (item 1). Mode files were not created.'
m tune_ds_notarget 'У doorstop_config.ini не знайшов рядок target...: створи doorstop_config_vanilla.ini і doorstop_config_wmp.bak вручну.' 'No target... line in doorstop_config.ini: create doorstop_config_vanilla.ini and doorstop_config_wmp.bak by hand.'
m tune_ds_nodll 'Не знайдено потрібну DLL (%s / %s): файли режимів не створено, зроби їх вручну (target MSCLoader.Preloader.dll і WreckMP.Preloader.dll).' 'A required DLL was not found (%s / %s): mode files were not created, make them by hand (target MSCLoader.Preloader.dll and WreckMP.Preloader.dll).'
m tune_ds_made  'Створено %s' 'Created %s'
m tune_wine_1   'Копія без Steam: додай ці змінні перед командою запуску гри (або в налаштування Lutris/Bottles/Heroic):' 'Copy without Steam: put these variables before the game start command (or into the Lutris/Bottles/Heroic settings):'
m tune_wine_2   'Перемикач режимів і автозакриття лаунчера потрібні лише для Steam-копії.' 'The mode switch and launcher auto-close are only for a Steam copy.'
m tune_game_head 'Steam -> %s -> Властивості -> Параметри запуску (заміни все, що там є):' 'Steam -> %s -> Properties -> Launch Options (replace whatever is there):'
m tune_launcher_head 'Steam -> ярлик лаунчера WreckMP -> Властивості -> Параметри запуску (заміни все):' 'Steam -> the WreckMP launcher shortcut -> Properties -> Launch Options (replace everything):'
m tune_steps    'Закрий і знову відкрий Steam, якщо параметри не зберігаються. Версії Proton лишаються як у кроках вище.' 'Restart Steam if the options do not stick. Proton versions stay as in the steps above.'
m tune_old      'Якщо в тебе вже є свій ~/msc_launch.sh, його можна не видаляти: нові параметри його не використовують.' 'If you already have your own ~/msc_launch.sh you can keep it: the new options do not use it.'
m tune_verify   'Запусти гру (для мультиплеєра через лаунчер) і, поки вона працює, виконай у терміналі:' 'Start the game (through the launcher for multiplayer) and, while it runs, execute in a terminal:'
m tune_unverified 'Змінні підібрані консервативно під тип заліза; приріст FPS не вимірювався. Лог перемикача: <тека гри>/.msc-wizard/msc.log' 'The variables are chosen conservatively for the hardware class; FPS gain was not measured. Switch log: <game folder>/.msc-wizard/msc.log'
m gc_nogame     'mysummercar.exe не запущений. Запусти гру й виконай це знову.' 'mysummercar.exe is not running. Start the game and run this again.'
m gc_pid        'Процес гри: PID %s' 'Game process: PID %s'
m gc_env        'Змінні в процесі гри:' 'Variables in the game process:'
m gc_noenv      'Не можу прочитати змінні процесу.' 'Cannot read the process variables.'
m gc_wined3d    'PROTON_USE_WINED3D=1 у грі: вона малює через OpenGL (wined3d), це причина 1 FPS. Знайди, звідки береться змінна (Launch Options, скрипти).' 'PROTON_USE_WINED3D=1 in the game: it renders through OpenGL (wined3d), a common cause of 1 FPS. Find where the variable comes from (Launch Options, scripts).'
m gc_dxvk       'DXVK завантажено (Vulkan): це правильний шлях.' 'DXVK is loaded (Vulkan): the correct path.'
m gc_wined3d_lib 'Завантажено wined3d (OpenGL).' 'wined3d (OpenGL) is loaded.'
m gc_lvp        'Є libvulkan_lvp: це лише драйвер, який бачить Vulkan-лоадер, сам по собі не означає софтовий рендер.' 'libvulkan_lvp is present: that is only a driver the Vulkan loader sees, it does not mean software rendering by itself.'
m gc_nv_yes     'Гра є в списку процесів nvidia-smi: рендер на NVIDIA.' 'The game is listed in nvidia-smi: rendering on NVIDIA.'
m gc_nv_no      'Гри немає в nvidia-smi: рендер іде не на NVIDIA (на гібридному ноутбуці це проблема).' 'The game is not in nvidia-smi: it is not rendering on NVIDIA (a problem on a hybrid laptop).'
m tune_a        'A) Гра "%s"' 'A) The game "%s"'
m tune_b        'B) Лаунчер WreckMP (Steam -> Ігри -> Додати стороннюю гру -> Огляд -> "Усі файли")' 'B) The WreckMP launcher (Steam -> Games -> Add a Non-Steam Game -> Browse -> "All files")'
m tune_proton   'Сумісність -> примусово -> %s' 'Compatibility -> force -> %s'
m tune_install_proton 'Інсталятори (MSCLoader, .NET, Updater через protontricks) запускай з %s; це не те саме, що Proton лаунчера.' 'Run the installers (MSCLoader, .NET, Updater via protontricks) with %s; that is not the same as the launcher Proton.'
m tune_ns_note  'Ціль і Почати в потрібні, лише якщо гра додана в Steam як стороння (для копії зі Steam Steam ставить їх сам):' 'Target and Start In are needed only if the game is added to Steam as a non-Steam game (for a Steam copy Steam sets them itself):'
m tune_confirm_1 'Буде створено файл: %s (папка .msc-wizard у теці гри; плюс doorstop_config_vanilla.ini / doorstop_config_wmp.bak, лише якщо їх ще немає; наявні файли не перезаписуються).' 'This will create the file: %s (the .msc-wizard folder inside the game folder, plus doorstop_config_vanilla.ini / doorstop_config_wmp.bak only if they are missing; existing files are never overwritten).'
m lo_q          'Записати ці параметри запуску в Steam автоматично (гра + ярлик лаунчера)?' 'Write these Launch Options into Steam automatically (game + launcher shortcut)?'
m lo_steam_on   'Steam зараз відкритий: він перезапише параметри при виході. Закрити Steam зараз?' 'Steam is running: it would overwrite the options when it exits. Close Steam now?'
m lo_closing    'Закриваю Steam...' 'Closing Steam...'
m lo_steam_left 'Steam не закрився: параметри не записано, встав їх вручну (нижче).' 'Steam did not close: options not written, paste them by hand (below).'
m lo_game_ok    'Параметри запуску гри записано (%s).' 'Game Launch Options written (%s).'
m lo_la_ok      'Параметри запуску ярлика лаунчера записано (%s).' 'Launcher shortcut Launch Options written (%s).'
m lo_la_none    'Ярлик лаунчера WreckMP у Steam не знайдено: його параметри встав вручну після створення ярлика.' 'The WreckMP launcher shortcut was not found in Steam: paste its options by hand once the shortcut exists.'
m lo_manual     'Вставляти вручну нічого не треба: усе вже в Steam. Нижче — для довідки.' 'Nothing to paste by hand: everything is already in Steam. Below is for reference.'
m ac_q          'Налаштувати автозакриття лаунчера WreckMP (через 5 с після старту гри) і автоперемикач MSCLoader / WreckMP?' 'Set up auto-closing the WreckMP launcher (5 s after the game starts) and the MSCLoader / WreckMP auto-switch?'
m tune_confirm_q 'Створити?' 'Create it?'
m tune_skipped  'Пропущено. Параметри нижче показано лише для довідки, скрипта не буде, тому вони працюватимуть лише як звичайний запуск.' 'Skipped. The options below are shown for reference only; without the script they only start the game normally.'
m ch_tune_hint  'Параметри запуску під ЦЕЙ ПК (GPU, автозакриття лаунчера) дає пункт 9 / bash %s --tune: вони важливіші за значення вище.' 'Launch options fitted to THIS PC (GPU, launcher auto-close) come from item 9 / bash %s --tune: they take priority over the values above.'

# ================================================================== helpers
step()  { printf '\n=== %s ===\n' "$*"; }
note()  { printf '  %s\n' "$*"; }
warn()  { printf '  ! %s\n' "$*"; }
ok()    { printf '  ✓ %s\n' "$*"; }
inf()   { printf '  [i] %s\n' "$*"; }
show()  { printf '\n      %s\n\n' "$*"; }
die()   { printf '\n  ✗ %s\n' "$*"; exit 1; }
tn() { note "$(t "$@")"; }
tw() { warn "$(t "$@")"; }
to() { ok "$(t "$@")"; }
ts() { step "$(t "$@")"; }
td() { die "$(t "$@")"; }
bye() { echo; exit 130; }                                  # input ended (EOF)
pause() { read -r -p "  $(t "${1:-press_enter}")" _ || bye; }
yesno() {  # yesno "question" [y|n default]
  local def="${2:-y}" hint a
  if [ "$def" = y ]; then hint="Y/n"; else hint="y/N"; fi
  read -r -p "  $1 [$hint] " a || bye
  a="${a:-$def}"
  case "$a" in y|Y|yes|YES|Yes|т|Т|так|Так|д|Д|да|Да) return 0 ;; *) return 1 ;; esac
}
clean_path() {  # trims blanks and quotes, handles file:// and "\ ", expands ~
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
  p="${p#\'}"; p="${p%\'}"; p="${p#\"}"; p="${p%\"}"
  case "$p" in file://*) p="${p#file://}"; p=$(printf '%b' "${p//%/\\x}") ;; esac
  p="${p//\\ / }"
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  printf '%s' "$p"
}
ask_path() {  # ask_path "question" [default]  ->  REPLY_PATH
  local ans
  if [ -n "${2:-}" ]; then read -e -r -i "$2" -p "  $1 " ans || bye; else read -e -r -p "  $1 " ans || bye; fi
  REPLY_PATH=$(clean_path "$ans")
}
win_path() { printf 'Z:%s' "$1" | sed 's#/#\\#g'; }   # /home/x -> Z:\home\x
guid_of()  { grep -m1 '^"MachineGuid"=' "$1" 2>/dev/null | sed 's/^"MachineGuid"="\([^"]*\)".*/\1/'; }
pfx_dir()  { if [ "$GAME_SRC" = wine ] && [ "$1" = "$GAME_APPID" ]; then printf '%s' "$GAME_PFX"; else printf '%s/%s/pfx' "$COMPAT" "$1"; fi; }
mark()     { if [ "$1" = "$2" ]; then printf '[✓]'; else printf '[ ]'; fi; }
have()     { command -v "$1" >/dev/null 2>&1; }

clip() {  # copy to the clipboard if a tool exists (never in dry run)
  [ "$DRY" = 1 ] && return 1
  if have wl-copy && [ -n "${WAYLAND_DISPLAY:-}" ]; then printf '%s' "$1" | wl-copy >/dev/null 2>&1
  elif have xclip && [ -n "${DISPLAY:-}" ]; then printf '%s' "$1" | xclip -selection clipboard >/dev/null 2>&1
  elif have xsel && [ -n "${DISPLAY:-}" ]; then printf '%s' "$1" | xsel -ib >/dev/null 2>&1
  else return 1; fi
}
show_copy() { show "$1"; clip "$1" && tn clip_done; }

# --- dry run
dry_note() {  # dry_note "what would be done" ["command"]
  DRY_LOG+=("$1")
  printf '  [DRY-RUN] %s\n' "$1"
  [ -n "${2:-}" ] && printf '            $ %s\n' "$2"
  return 0
}
act() {  # act "what" command...   dry run only shows it, a real run executes it
  local what="$1"; shift
  if [ "$DRY" = 1 ]; then dry_note "$what" "$*"; return 0; fi
  "$@"
}
dry_logged() { local x; for x in "${DRY_LOG[@]+"${DRY_LOG[@]}"}"; do [ "$x" = "$1" ] && return 0; done; return 1; }
mk_work() {  # create the work folder (in dry run: only mention it once)
  local what; what="$(t act_mkwork "$WORK")"
  if [ "$DRY" = 1 ] && dry_logged "$what"; then return 0; fi
  act "$what" mkdir -p "$WORK"
}
sim_reset() { SIM_MSCL=0; SIM_WMP=0; SIM_DOTNET_GAME=0; SIM_DOTNET_LA=0; SIM_REG=0; SIM_GUID=0; SIM_HOSTS=0; }

fetch() {  # fetch URL FILE
  if have curl; then curl -fL --retry 2 -o "$2" "$1"
  elif have wget; then wget -O "$2" "$1"
  else tw dep_miss curl "$(pm_hint curl)"; return 1; fi
}
extract_zip() {  # extract_zip ZIP DEST
  mkdir -p "$2" || return 1
  if have unzip; then unzip -q -o "$1" -d "$2"
  elif have python3; then python3 -I -m zipfile -e "$1" "$2"
  elif have bsdtar; then bsdtar -xf "$1" -C "$2"
  else return 1; fi
}
download_dirs() {
  local d
  d=$(xdg-user-dir DOWNLOAD 2>/dev/null) && [ -d "$d" ] && printf '%s\n' "$d"
  for d in "$HOME/Downloads" "$HOME/Завантажене" "$HOME/Загрузки"; do [ -d "$d" ] && printf '%s\n' "$d"; done
}
newest_match() {  # newest file in the download folders whose name matches the regex
  local re="$1" best="" d f
  while IFS= read -r d; do
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      printf '%s' "${f##*/}" | grep -qiE "$re" || continue
      if [ -z "$best" ] || [ "$f" -nt "$best" ]; then best="$f"; fi
    done
  done < <(download_dirs | sort -u)
  printf '%s' "$best"
}

# ================================================================== distro / tools
distro_id()   { [ -r /etc/os-release ] && ( . /etc/os-release; printf '%s %s' "${ID:-}" "${ID_LIKE:-}" ); }
distro_name() { if [ -r /etc/os-release ]; then ( . /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}" ); else printf 'Linux'; fi; }
detect_pm() {  # by what is installed, so derivatives work too; immutable systems are detected separately
  case " $(distro_id) " in *" nixos "*) echo nix; return ;; *" steamos "*) echo steamos; return ;; esac
  [ -e /run/ostree-booted ] && { echo ostree; return; }
  local p
  for p in pacman apt-get dnf zypper xbps-install emerge apk eopkg nix-env; do
    if have "$p"; then
      case "$p" in apt-get) echo apt ;; xbps-install) echo xbps ;; nix-env) echo nix ;; *) echo "$p" ;; esac
      return
    fi
  done
  echo unknown
}
pkg_name() {  # pkg_name TOOL PM -> package name
  case "$1:$2" in
    python3:pacman)      echo python ;;
    python3:emerge)      echo dev-lang/python ;;
    unzip:emerge)        echo app-arch/unzip ;;
    curl:emerge)         echo net-misc/curl ;;
    protontricks:emerge) echo games-util/protontricks ;;
    wine:emerge)         echo virtual/wine ;;
    wine:nix)            echo wineWowPackages.stable ;;
    *)                   echo "$1" ;;
  esac
}
pm_hint() {  # install command for a tool on the current distribution
  local tool="$1" pm p; pm=$(detect_pm); p=$(pkg_name "$tool" "$pm")
  if [ "$tool" = protontricks ]; then
    case "$pm" in
      steamos|ostree|apk|eopkg|unknown)
        echo "flatpak install flathub com.github.Matoking.protontricks   (or: pipx install protontricks)"; return ;;
    esac
  fi
  case "$pm" in
    pacman)  echo "sudo pacman -S $p" ;;
    apt)     echo "sudo apt install $p" ;;
    dnf)     echo "sudo dnf install $p" ;;
    zypper)  echo "sudo zypper install $p" ;;
    xbps)    echo "sudo xbps-install -S $p" ;;
    emerge)  echo "sudo emerge --ask $p" ;;
    apk)     echo "sudo apk add $p" ;;
    eopkg)   echo "sudo eopkg install $p" ;;
    nix)     echo "nix-shell -p $p   (or: nix profile install nixpkgs#$p)" ;;
    steamos) echo "sudo steamos-readonly disable && sudo pacman -S $p   (or use Flatpak / Distrobox)" ;;
    ostree)  echo "rpm-ostree install $p   (then reboot; or use distrobox / toolbox)" ;;
    *)       echo "(install '$p' with your package manager)" ;;
  esac
}
dep_hints() {  # prints the install command for every missing tool
  have python3 || tw dep_miss python3 "$(pm_hint python3)"
  have_dl      || tw dep_miss curl "$(pm_hint curl)"
  have_unzip   || tw dep_miss unzip "$(pm_hint unzip)"
  if [ "$GAME_SRC" = wine ]; then detect_wine || tw dep_miss wine "$(pm_hint wine)"
  else detect_pt || tw dep_miss protontricks "$(pm_hint protontricks)"; fi
}
detect_pt() {
  if have protontricks-launch && have protontricks; then
    PT=(protontricks); PTL=(protontricks-launch); return 0
  fi
  if have flatpak && flatpak info com.github.Matoking.protontricks >/dev/null 2>&1; then
    PT=(flatpak run com.github.Matoking.protontricks)
    PTL=(flatpak run --command=protontricks-launch com.github.Matoking.protontricks)
    return 0
  fi
  return 1
}
PT_GRANTED=""
pt_grant() {  # Flatpak protontricks sees only a few standard folders: let it see this one
  [ "${PT[0]:-}" = flatpak ] || return 0
  local d="$1"
  [ -n "$d" ] || return 0
  [ "$DRY" = 1 ] || [ -e "$d" ] || return 0
  case "$PT_GRANTED" in *"|$d|"*) return 0 ;; esac
  PT_GRANTED="$PT_GRANTED|$d|"
  if [ "$DRY" = 1 ]; then
    dry_note "$(t act_fp "$d")" "flatpak override --user --filesystem=$(printf '%q' "$d") com.github.Matoking.protontricks"
    return 0
  fi
  flatpak override --user --filesystem="$d" com.github.Matoking.protontricks >/dev/null 2>&1
}
ensure_pt_access() { pt_grant "$GAME_DIR"; pt_grant "$COMPAT"; pt_grant "$WORK"; }
need_pt() {
  if detect_pt; then ensure_pt_access; return 0; fi
  tw need_pt_1
  tn need_pt_2; show "$(pm_hint protontricks)"
  tn need_pt_3
  if [ "$DRY" = 1 ]; then
    dry_note "$(t need_pt_dry)"
    PT=(protontricks); PTL=(protontricks-launch); return 0
  fi
  tn need_pt_4
  return 1
}
have_dl()    { have curl || have wget; }
have_unzip() { have unzip || have bsdtar || have python3; }

# ================================================================== Steam
steam_roots() {
  local r
  for r in "${STEAM_ROOT:-}" "$HOME/.steam/debian-installation" "$HOME/.steam/steam" "$HOME/.steam/root" \
           "${XDG_DATA_HOME:-$HOME/.local/share}/Steam" "$HOME/.local/share/Steam" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" \
           "$HOME/snap/steam/common/.local/share/Steam"; do
    [ -n "$r" ] || continue
    [ -d "$r/steamapps" ] && readlink -f "$r"
  done | sort -u
}
libs_of() { grep -o '"path"[[:space:]]*"[^"]*"' "$1/steamapps/libraryfolders.vdf" 2>/dev/null | sed 's/^"path"[[:space:]]*"\(.*\)"$/\1/'; }
find_game_dirs() {  # every My Summer Car copy inside Steam libraries
  local r lib
  while IFS= read -r r; do
    { printf '%s\n' "$r"; libs_of "$r"; } | while IFS= read -r lib; do
      [ -f "$lib/steamapps/common/$GAME_NAME/mysummercar.exe" ] && printf '%s\n' "$lib/steamapps/common/$GAME_NAME"
    done
  done < <(steam_roots) | awk '!s[$0]++'
}
find_game_dir() { find_game_dirs | head -n1; }

# Reads Steam's own files (read only). Text VDF: localconfig.vdf, config.vdf.
# Binary VDF: shortcuts.vdf (the appid of a shortcut is taken from the file, not computed:
# the user may edit the shortcut).
PY_VDF=$(cat <<'PY'
import os
import re, sys

def unesc(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)

def parse_text(s):
    toks = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', s)
    pos = 0
    def block():
        nonlocal pos
        d = {}
        while pos < len(toks):
            k, b = toks[pos]; pos += 1
            if b == '}':
                return d
            if b == '{' or pos >= len(toks):
                continue
            v, b2 = toks[pos]; pos += 1
            if b2 == '{':
                d[unesc(k).lower()] = block()
            else:
                d[unesc(k).lower()] = unesc(v)
        return d
    return block()

def parse_bin(d):
    i = 0
    def cstr():
        nonlocal i
        j = d.index(b'\x00', i)
        s = d[i:j].decode('utf-8', 'replace')
        i = j + 1
        return s
    def block():
        nonlocal i
        out = {}
        while i < len(d):
            t = d[i]; i += 1
            if t == 8:
                return out
            k = cstr().lower()
            if t == 0:
                v = block()
            elif t == 1:
                v = cstr()
            elif t in (2, 3, 4, 6):
                v = int.from_bytes(d[i:i + 4], 'little'); i += 4
            elif t in (7, 10):
                v = int.from_bytes(d[i:i + 8], 'little'); i += 8
            else:
                raise ValueError(t)
            out[k] = v
        return out
    return block()

def walk(d, key):
    if isinstance(d, dict):
        for k, v in d.items():
            if k == key:
                yield v
            yield from walk(v, key)

def clean(x):
    return str(x).replace('\n', ' ').replace('\x1f', ' ')

mode = sys.argv[1]
try:
    if mode == 'launchopts':      # launchopts FILE APPID
        tree = parse_text(open(sys.argv[2], encoding='utf-8', errors='replace').read())
        for apps in walk(tree, 'apps'):
            e = apps.get(sys.argv[3]) if isinstance(apps, dict) else None
            if isinstance(e, dict) and e.get('launchoptions'):
                print(e['launchoptions']); break
    elif mode == 'compat':        # compat FILE APPID
        tree = parse_text(open(sys.argv[2], encoding='utf-8', errors='replace').read())
        for mp in walk(tree, 'compattoolmapping'):
            e = mp.get(sys.argv[3]) if isinstance(mp, dict) else None
            if isinstance(e, dict) and e.get('name'):
                print(e['name']); break
    elif mode == 'shortcuts':     # shortcuts FILE NEEDLE
        tree = parse_bin(open(sys.argv[2], 'rb').read())
        needle = sys.argv[3].lower()
        for e in tree.get('shortcuts', {}).values():
            if not isinstance(e, dict):
                continue
            exe = str(e.get('exe', '')).strip('"')
            name = str(e.get('appname', ''))
            appid = int(e.get('appid', 0)) & 0xFFFFFFFF
            if appid and needle in (exe + '\x00' + name).lower():
                print('\x1f'.join(clean(x) for x in (appid, name, exe,
                      str(e.get('startdir', '')).strip('"'), e.get('launchoptions', ''))))
    elif mode == 'setlaunch':     # setlaunch LOCALCONFIG APPID OPTS  (text VDF: apps/<APPID>/LaunchOptions)
        import re as _re
        path, appid, opts = sys.argv[2], sys.argv[3], sys.argv[4]
        txt = open(path, encoding='utf-8', errors='surrogateescape').read()
        val = opts.replace('\\', '\\\\').replace('"', '\\"')
        # find the "apps" block of the Steam section, then the APPID block inside it
        m = _re.search(r'"apps"\s*\{', txt, _re.I)
        if not m:
            print('noapps'); sys.exit(0)
        def block_end(i):           # i = index just after "{": returns index of the matching "}"
            depth, j, q = 1, i, False
            while j < len(txt):
                c = txt[j]
                if q:
                    if c == '\\': j += 2; continue
                    if c == '"': q = False
                elif c == '"': q = True
                elif c == '{': depth += 1
                elif c == '}':
                    depth -= 1
                    if depth == 0: return j
                j += 1
            return len(txt)
        a0, a1 = m.end(), block_end(m.end())
        am = _re.compile(r'\n(\s*)"%s"\s*\{' % _re.escape(appid)).search(txt, a0, a1)
        if am:
            b0 = am.end(); b1 = block_end(b0); ind = am.group(1) + '\t'
            lm = _re.compile(r'"LaunchOptions"\s*"((?:[^"\\]|\\.)*)"', _re.I).search(txt, b0, b1)
            if lm:
                txt = txt[:lm.start()] + '"LaunchOptions"\t\t"%s"' % val + txt[lm.end():]
            else:
                txt = txt[:b0] + '\n%s"LaunchOptions"\t\t"%s"' % (ind, val) + txt[b0:]
        else:
            ind = _re.search(r'\n(\s*)"apps"', txt[:a0], _re.I)
            ind = (ind.group(1) if ind else '\t\t\t\t') + '\t'
            txt = txt[:a0] + '\n%s"%s"\n%s{\n%s\t"LaunchOptions"\t\t"%s"\n%s}' % (ind, appid, ind, ind, val, ind) + txt[a0:]
        tmp = path + '.wizard-tmp'
        open(tmp, 'w', encoding='utf-8', errors='surrogateescape').write(txt)
        os.replace(tmp, path); print('ok')
    elif mode == 'setshortcut':   # setshortcut SHORTCUTS APPID OPTS  (binary VDF: LaunchOptions of one shortcut)
        import struct
        path, appid, opts = sys.argv[2], int(sys.argv[3]) & 0xFFFFFFFF, sys.argv[4]
        b = open(path, 'rb').read()
        key = b'\x02appid\x00' + struct.pack('<I', appid)
        i = b.lower().find(key.lower())
        if i < 0:
            print('noshortcut'); sys.exit(0)
        nxt = b.lower().find(b'\x02appid\x00', i + len(key))
        end = nxt if nxt >= 0 else len(b)
        # the entry starts a bit before "appid": search LaunchOptions in the whole entry (start = previous \x00<n>\x00 header)
        start = b.rfind(b'\x00\x00', 0, i)
        lo_key = b'\x01launchoptions\x00'
        j = b.lower().find(lo_key, max(0, start), end)
        new = opts.encode('utf-8')
        if j >= 0:
            v0 = j + len(lo_key); v1 = b.find(b'\x00', v0)
            b = b[:v0] + new + b[v1:]
        else:
            ins = i + len(key)
            b = b[:ins] + b'\x01LaunchOptions\x00' + new + b'\x00' + b[ins:]
        tmp = path + '.wizard-tmp'
        open(tmp, 'wb').write(b)
        os.replace(tmp, path); print('ok')
except Exception:
    pass
PY
)
vdf() { have python3 || return 1; python3 -I -c "$PY_VDF" "$@" 2>/dev/null; }

# Wine keeps its registry in plain text files (user.reg / system.reg). Writing them directly needs no
# wine/protontricks and works with any Proton; the only rule: wineserver of that prefix must not run.
PY_REG=$(cat <<'PY'
import os, re, sys, time

def esc(v):
    out = []
    for ch in v:
        o = ord(ch)
        if ch == '\\': out.append('\\\\')
        elif ch == '"': out.append('\\"')
        elif 32 <= o < 127: out.append(ch)
        elif o > 0xFFFF:
            o -= 0x10000
            out.append('\\x%04x\\x%04x' % (0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF)))
        else: out.append('\\x%04x' % o)
    return ''.join(out)

def unesc(v):
    v = re.sub(r'\\x([0-9a-fA-F]{1,4})', lambda m: chr(int(m.group(1), 16)), v)
    v = v.replace('\\"', '"').replace('\\\\', '\\')
    return v.encode('utf-16', 'surrogatepass').decode('utf-16', 'replace')   # \xd83c\xdfae pairs -> one char

def set_values(path, key, values):
    """key like Software\\Foo (single backslashes); values: {name: str}. Returns True if the file changed."""
    try:
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
    except OSError:
        return False
    hdr = '[' + key.replace('\\', '\\\\') + ']'
    lines = text.split('\n')
    start = next((i for i, l in enumerate(lines) if l.lower().startswith(hdr.lower() + ' ') or l.lower() == hdr.lower()), None)
    want = ['"%s"="%s"' % (esc(n), esc(v)) for n, v in values.items()]
    if start is None:
        now = int(time.time())
        ft = (now + 11644473600) * 10000000
        block = ['', '%s %d' % (hdr, now), '#time=%x' % ft] + want
        while lines and lines[-1] == '':
            lines.pop()
        lines += block + ['']
    else:
        end = start + 1
        while end < len(lines) and not lines[end].startswith('['):
            end += 1
        body = lines[start + 1:end]
        for n, v in values.items():
            pre = '"%s"=' % esc(n)
            idx = next((i for i, l in enumerate(body) if l.startswith(pre)), None)
            line = '"%s"="%s"' % (esc(n), esc(v))
            if idx is None:
                ins = len(body)
                while ins > 0 and body[ins - 1] == '':
                    ins -= 1
                body.insert(ins, line)
            else:
                body[idx] = line
        lines[start + 1:end] = body
    new = '\n'.join(lines)
    if new == text:
        return False
    tmp = path + '.wizard-tmp'
    with open(tmp, 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.write(new)
    os.replace(tmp, path)
    return True

def get_value(path, key, name):
    try:
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
    except OSError:
        return ''
    hdr = '[' + key.replace('\\', '\\\\') + ']'
    on = False
    for l in text.split('\n'):
        if l.startswith('['):
            on = l.lower().startswith(hdr.lower())
        elif on and l.startswith('"%s"=' % name):
            return unesc(l.split('=', 1)[1].strip().strip('"'))
    return ''

mode = sys.argv[1]
if mode == 'get':            # get PREFIX_DIR  -> GameDirectory (unescaped), empty if none
    print(get_value(os.path.join(sys.argv[2], 'user.reg'), r'Software\MaceeikoDevelopment\WreckMP', 'GameDirectory'))
elif mode == 'wmp':          # wmp PREFIX_DIR WIN_GAME_DIR  -> writes what the WreckMP installer writes
    pfx, w = sys.argv[2], sys.argv[3]
    ch = False
    for k in (r'Software\MaceeikoDevelopment\WreckMP', r'Software\Wow6432Node\MaceeikoDevelopment\WreckMP'):
        ch |= set_values(os.path.join(pfx, 'user.reg'), k, {'GameDirectory': w})
    for k in (r'Software\Microsoft\Windows\CurrentVersion\Uninstall\WreckMP',
              r'Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WreckMP'):
        ch |= set_values(os.path.join(pfx, 'system.reg'), k, {
            'DisplayIcon': w + '\\WreckMP\\Updater.exe', 'DisplayName': 'WreckMP',
            'InstallLocation': w + '\\WreckMP', 'UninstallString': w + '\\WreckMP\\Uninstall.exe'})
    print('changed' if ch else 'same')
PY
)
regpy() { have python3 || return 1; python3 -I -c "$PY_REG" "$@"; }
win_path_u() { printf 'Z:%s' "$1" | sed 's#/#\\#g'; }   # like win_path, single backslashes (for regpy)

# Every WreckMP shortcut (all Steam accounts): "APPID<TAB>EXE" lines
wmp_shortcuts() {
  local r f
  while IFS= read -r r; do
    for f in "$r"/userdata/*/config/shortcuts.vdf; do
      [ -f "$f" ] || continue
      vdf shortcuts "$f" WreckMP | awk -F '\037' '{print $1 "\t" $3}'
    done
  done < <(steam_roots) | awk '!s[$0]++'
}
game_dir_of_exe() {  # nearest folder above the launcher exe that contains mysummercar.exe
  local d; d=$(dirname "$1")
  while [ -n "$d" ] && [ "$d" != / ]; do
    [ -f "$d/mysummercar.exe" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}
# Fix the "register/registry not found" error of the WreckMP launcher: its prefix has no (or a stale)
# GameDirectory, e.g. after moving the game, a new Steam account / shortcut, or a fresh prefix.
fix_wmp_registry() {  # fix_wmp_registry [quiet]
  local quiet="${1:-}" a e g pfx cur want any=0 fixed=0
  have python3 || return 1
  if wine_busy; then [ -n "$quiet" ] || tw reg_fix_busy "$SELF"; return 1; fi
  while IFS=$'\t' read -r a e; do
    [ -n "$a" ] || continue
    pfx="$COMPAT/$a/pfx"
    [ -f "$pfx/user.reg" ] && [ -f "$pfx/system.reg" ] || continue
    g=$(game_dir_of_exe "$e") || g="$GAME_DIR"
    [ -n "$g" ] && [ -f "$g/mysummercar.exe" ] || continue
    g=$(readlink -f "$g"); any=1
    want=$(win_path_u "$g"); cur=$(regpy get "$pfx")
    if [ "$cur" != "$want" ] || ! grep -qF 'Uninstall\\WreckMP]' "$pfx/system.reg"; then
      if [ "$DRY" = 1 ]; then dry_note "$(t reg_fixed "$a" "$want")"; fixed=1; continue; fi
      cp -a "$pfx/user.reg" "$pfx/user.reg.wizard-bak" 2>/dev/null
      cp -a "$pfx/system.reg" "$pfx/system.reg.wizard-bak" 2>/dev/null
      regpy wmp "$pfx" "$want" >/dev/null && { to reg_fixed "$a" "$want"; fixed=1; }
    fi
  done < <(wmp_shortcuts)
  if [ "$any" = 0 ]; then [ -n "$quiet" ] || tn reg_fix_none; return 1; fi
  [ "$fixed" = 1 ] || [ -n "$quiet" ] || to reg_fix_ok
  return 0
}

detect_launcher_prefix() {  # no questions; sets LA (prefix id) and L_* (shortcut fields)
  # Several Steam accounts / old shortcuts are possible: the best one points to an existing launcher
  # inside the current game folder and already has a prefix.
  LA=""; L_APPID=""; L_NAME=""; L_EXE=""; L_START=""; L_OPTS=""
  local r f row a n e s o score best=-1 gd
  gd=$(readlink -f "${GAME_DIR:-/nonexistent}" 2>/dev/null)
  while IFS= read -r r; do
    for f in "$r"/userdata/*/config/shortcuts.vdf; do
      [ -f "$f" ] || continue
      while IFS= read -r row; do
        [ -n "$row" ] || continue
        IFS=$'\037' read -r a n e s o <<<"$row"
        score=0
        [ -f "$e" ] && score=$((score + 4))
        [ -n "$gd" ] && case "$(readlink -f "$e" 2>/dev/null)" in "$gd"/*) score=$((score + 2)) ;; esac
        [ -d "$COMPAT/$a/pfx" ] && score=$((score + 1))
        if [ "$score" -gt "$best" ]; then
          best=$score; L_APPID="$a"; L_NAME="$n"; L_EXE="$e"; L_START="$s"; L_OPTS="$o"
          if [ -d "$COMPAT/$a/pfx" ]; then LA="$a"; else LA=""; fi
        fi
      done < <(vdf shortcuts "$f" WreckMP)
    done
  done < <(steam_roots)
  [ -n "$LA" ]
}
steam_launch_opts() {  # steam_launch_opts APPID -> LaunchOptions saved in Steam
  local r f v
  while IFS= read -r r; do
    for f in "$r"/userdata/*/config/localconfig.vdf; do
      [ -f "$f" ] || continue
      v=$(vdf launchopts "$f" "$1" | head -n1)
      [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    done
  done < <(steam_roots)
  return 1
}
steam_compat_tool() {  # steam_compat_tool APPID -> internal name of the forced Proton (e.g. proton_8)
  local r v
  while IFS= read -r r; do
    v=$(vdf compat "$r/config/config.vdf" "$1" | head -n1)
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done < <(steam_roots)
  return 1
}
proton_id() { printf '%s' "$1" | sed -n 's/^Proton \([0-9][0-9]*\)\..*/proton_\1/p'; }   # "Proton 8.0" -> proton_8
list_protons() {  # names of installed Proton / compatibility tools
  local r lib d
  {
    while IFS= read -r r; do
      { printf '%s\n' "$r"; libs_of "$r"; } | while IFS= read -r lib; do
        for d in "$lib"/steamapps/common/Proton*; do [ -d "$d" ] && basename "$d"; done
      done
      for d in "$r"/compatibilitytools.d/*; do [ -d "$d" ] && basename "$d"; done
    done < <(steam_roots)
    for d in /usr/share/steam/compatibilitytools.d/*; do [ -d "$d" ] && basename "$d"; done
  } | sort -u
}
proton_state() { if list_protons | grep -qxF "$1"; then t proton_ok "$1"; else t proton_missing "$1"; fi; }

# ================================================================== states
# st SIMVAR check...: true if the step is "done" in the simulation, or (not DEMO and really done)
st() { local v="$1"; shift; [ "${!v}" = 1 ] && return 0; [ "$DEMO" = 1 ] && return 1; "$@"; }

game_prefix_ok()  { [ -f "$(pfx_dir "$GAME_APPID")/system.reg" ]; }
mscl_real()       { [ -e "$GAME_DIR/winhttp.dll" ] && [ -e "$GAME_DIR/doorstop_config.ini" ] && [ -e "$GAME_DIR/mysummercar_Data/Managed/MSCLoader.dll" ]; }
wmp_real()        { [ -f "$GAME_DIR/WreckMP/Updater.exe" ] || [ -f "$GAME_DIR/WreckMP/bin/WreckMPLauncher.exe" ] || [ -f "$GAME_DIR/WreckMP/WreckMPLauncher.exe" ]; }
dotnet_real()     { ls -d "$(pfx_dir "$1")/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App/"6.* >/dev/null 2>&1; }
hosts_real()      { grep -qE '^[^#]*patreon\.com' /etc/hosts 2>/dev/null; }
reg_real()        { [ -n "$LA" ] && grep -qF 'Uninstall\\WreckMP]' "$(pfx_dir "$LA")/system.reg" 2>/dev/null && reg_dir_ok "$(pfx_dir "$LA")"; }
reg_dir_ok() {  # GameDirectory in this prefix points to the current game folder (any spelling of the path)
  local cur; cur=$(regpy get "$1" 2>/dev/null) || cur=""
  [ -z "$cur" ] && cur=$(grep -m1 '^"GameDirectory"=' "$1/user.reg" 2>/dev/null | sed 's/^"GameDirectory"="\(.*\)"$/\1/; s/\\\\/\\/g')
  [ "$cur" = "$(win_path_u "$GAME_DIR")" ] || [ "$cur" = "$(win_path_u "$(readlink -f "$GAME_DIR")")" ]
}
guid_real()       { [ -n "$LA" ] && [ -n "$(guid_of "$(pfx_dir "$LA")/system.reg")" ] && [ "$(guid_of "$(pfx_dir "$LA")/system.reg")" = "$(guid_of "$(pfx_dir "$GAME_APPID")/system.reg")" ]; }

mscl_present()    { [ "$SIM_MSCL" = 1 ] || mscl_real; }            # for prerequisites (ignores DEMO)
mscl_installed()  { st SIM_MSCL mscl_real; }
wmp_installed()   { st SIM_WMP wmp_real; }
has_dotnet6()     { local v=SIM_DOTNET_LA; [ "$1" = "$GAME_APPID" ] && v=SIM_DOTNET_GAME; st "$v" dotnet_real "$1"; }
hosts_blocked()   { st SIM_HOSTS hosts_real; }
reg_written()     { st SIM_REG reg_real; }
guids_equal()     { st SIM_GUID guid_real; }
wmp_entry() {
  local n
  for n in Updater.exe bin/WreckMPLauncher.exe WreckMPLauncher.exe; do [ -f "$GAME_DIR/WreckMP/$n" ] && { printf '%s' "$GAME_DIR/WreckMP/$n"; return 0; }; done
  [ "$DRY" = 1 ] && { printf '%s' "$GAME_DIR/WreckMP/Updater.exe"; return 0; }
  return 1
}
wmp_entry_guess() { wmp_entry 2>/dev/null || printf '%s' "$GAME_DIR/WreckMP/Updater.exe"; }
launch_opts_ok() {
  local r f v
  case "$GAME_SRC" in
    wine)     return 0 ;;   # no Steam launch options: the argument goes into the start command
    shortcut) case "$G_OPTS" in *winhttp=n,b*) return 0 ;; esac; return 1 ;;
  esac
  if have python3; then
    v=$(steam_launch_opts "$GAME_APPID") || return 1
    case "$v" in *winhttp=n,b*) return 0 ;; esac
    return 1
  fi
  while IFS= read -r r; do   # no python3: rough text search
    for f in "$r"/userdata/*/config/localconfig.vdf; do
      [ -f "$f" ] && grep -A40 "\"$GAME_APPID\"" "$f" 2>/dev/null | grep -q 'winhttp=n,b' && return 0
    done
  done < <(steam_roots)
  return 1
}
busy_list() {  # by process name (comm), so a terminal that merely mentions these words does not count
  ps -eo pid=,comm=,args= 2>/dev/null | awk 'tolower($2) ~ /^(mysummercar\.ex|wreckmplauncher|wineserver)/ { $2 = ""; print }'
}
wine_busy() { [ -n "$(busy_list)" ]; }
kill_busy() {
  local p
  for p in $(busy_list | awk '{print $1}'); do kill -TERM "$p" 2>/dev/null; done
  sleep 3
  for p in $(busy_list | awk '{print $1}'); do kill -9 "$p" 2>/dev/null; done
  sleep 1
}
lopts_ok()  { case "$L_OPTS" in *.wmp_flag*) return 0 ;; esac; case "$L_OPTS" in *PROTON_USE_WINED3D=1*) ;; *) return 1 ;; esac; case "$L_OPTS" in *DOTNET_EnableWriteXorExecute=0*) return 0 ;; esac; return 1; }
target_ok() { [ -n "$L_EXE" ] && [ -f "$L_EXE" ] && case "$L_EXE" in */WreckMP/*) return 0 ;; esac; return 1; }
start_ok()  { [ -n "$L_EXE" ] && [ "${L_START%/}" = "$(dirname "$L_EXE")" ]; }

chk() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then printf '  [✓] %s\n' "$label"; else printf '  [ ] %s\n' "$label"; fi; }
show_status() {
  local DEMO=0 tool
  ts st_title
  inf "$(t inf_distro "$(distro_name)" "$(detect_pm)")"
  inf "$(t inf_src "$(t "src_name_${GAME_SRC:-steam}")")"
  case "$GAME_SRC" in
    wine)     LA="$GAME_APPID" ;;
    shortcut) adopt_game_shortcut; detect_launcher_prefix ;;
    *)        detect_launcher_prefix ;;
  esac
  if [ "$GAME_SRC" = wine ]; then chk "$(t ck_wine)" detect_wine; else chk "$(t ck_pt)" detect_pt; fi
  chk "$(t ck_py)"     have python3
  chk "$(t ck_dl)"     have_dl
  chk "$(t ck_unzip)"  have_unzip
  echo
  if [ "$GAME_SRC" = wine ]; then
    chk "$(t ck_pfx_wine "$GAME_PFX")"                     game_prefix_ok
  else
    chk "$(t ck_prefix "$GAME_APPID")"                     game_prefix_ok
    chk "$(t ck_lo)"                                       launch_opts_ok
  fi
  chk "$(t ck_mscl)"                                       mscl_installed
  chk "$(t ck_wmp "$GAME_DIR")"                            wmp_installed
  if [ "$GAME_SRC" != wine ]; then
    chk "$(t ck_short "${LA:+ ($LA)}")"                    test -n "$LA"
    chk "$(t ck_target)"                                   target_ok
    chk "$(t ck_start)"                                    start_ok
    chk "$(t ck_lopts)"                                    lopts_ok
  fi
  chk "$(t ck_dn_game)"                                    has_dotnet6 "$GAME_APPID"
  if [ "$GAME_SRC" != wine ] && [ -n "$LA" ]; then chk "$(t ck_dn_la)" has_dotnet6 "$LA"; fi
  chk "$(t ck_hosts)"                                      hosts_blocked
  chk "$(t ck_reg)"                                        reg_written
  [ "$GAME_SRC" = wine ] || chk "$(t ck_guid)"             guids_equal
  echo
  if [ "$GAME_SRC" != wine ]; then
    tool=$(steam_compat_tool "$GAME_APPID"); inf "$(t inf_pg "${tool:-$(t unset_val)}" "$PROTON_GAME") $(mark "$tool" "$(proton_id "$PROTON_GAME")")"
    if [ -n "$L_APPID" ]; then
      tool=$(steam_compat_tool "$L_APPID"); inf "$(t inf_pl "${tool:-$(t unset_val)}" "$PROTON_LAUNCHER") $(mark "$tool" "$(proton_id "$PROTON_LAUNCHER")")"
    fi
  fi
  dep_hints
  tn st_hint
}

# ================================================================== running inside a prefix
ensure_idle() {
  while wine_busy; do
    tw idle_warn
    busy_list | cut -c1-140 | sed 's/^/      /'
    if [ "$DRY" = 1 ]; then
      dry_note "$(t idle_dry)"
      return 0
    fi
    if yesno "$(t q_idle)" n; then
      kill_busy
    else
      tn idle_manual; pause
    fi
  done
}
ask_proton_version() {
  [ -n "$PV_ASKED" ] && return 0
  PV_ASKED=1
  tn pv_1
  tn pv_2; list_protons | sed 's/^/      /'
  tn pv_3 "$PROTON_INSTALL"
  local pv; read -e -r -p "  $(t pv_q)" pv || bye
  if [ -n "$pv" ]; then export PROTON_VERSION="$pv"; fi
}
run_in_prefix() {  # run_in_prefix APPID FILE
  need_runner || return 1
  if [ "$GAME_SRC" = wine ] && [ "$1" = "$GAME_APPID" ]; then run_in_wine "$2"; return; fi
  ask_proton_version
  ensure_idle
  pt_grant "$(dirname "$2")"
  if [ "$DRY" = 1 ]; then
    local pre=""; [ -n "${PROTON_VERSION:-}" ] && pre="PROTON_VERSION=$(printf '%q' "$PROTON_VERSION") "
    dry_note "$(t run_dry "$(basename "$2")" "$1")" "cd $(printf '%q' "$(dirname "$2")") && ${pre}${PTL[*]} --appid $1 $(printf '%q' "$2")"
    return 0
  fi
  tn run_now "$(basename "$2")" "$1"
  ( cd "$(dirname "$2")" && "${PTL[@]}" --appid "$1" "$2" 2>&1 | grep -v -E 'fixme|use_kernel_writewatch|^info:|^warn:|setupapi|xrandr|kerberos|ntlm|openxr' )
}

# ================================================================== game copy that is NOT from Steam
# Three ways to run the game: steam (Steam library), shortcut (non-Steam game added to Steam, own
# Proton prefix in compatdata/<appid>), wine (plain Wine prefix: Wine, Lutris, Bottles, Heroic...).
# In wine mode GAME_APPID is the token "wine" and the launcher shares the game prefix.
compat_for() {  # compatdata folder that holds (or will hold) the prefix of a shortcut
  local r d
  while IFS= read -r r; do
    d="$r/steamapps/compatdata"; [ -d "$d/$1/pfx" ] && { printf '%s' "$d"; return 0; }
  done < <(steam_roots)
  r=$(steam_roots | head -n1); [ -n "$r" ] || r="$HOME/.local/share/Steam"
  printf '%s/steamapps/compatdata' "$r"
}
detect_game_shortcut() {  # the non-Steam shortcut whose exe is THIS game folder's mysummercar.exe
  G_APPID=""; G_EXE=""; G_START=""; G_OPTS=""
  local r f a n e s o
  while IFS= read -r r; do
    for f in "$r"/userdata/*/config/shortcuts.vdf; do
      [ -f "$f" ] || continue
      while IFS=$'\037' read -r a n e s o; do
        [ -n "$a" ] || continue
        if [ "${e%/*}" = "${GAME_DIR%/}" ]; then G_APPID="$a"; G_EXE="$e"; G_START="$s"; G_OPTS="$o"; fi
      done < <(vdf shortcuts "$f" mysummercar.exe)
    done
  done < <(steam_roots)
  [ -n "$G_APPID" ]
}
adopt_game_shortcut() {
  detect_game_shortcut || return 1
  GAME_APPID="$G_APPID"; COMPAT=$(compat_for "$G_APPID")
}
nonsteam_roots() {
  local d
  for d in "${XDG_DATA_HOME:-$HOME/.local/share}/lutris" "${XDG_DATA_HOME:-$HOME/.local/share}/bottles" \
           "${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes" "$HOME/.wine/drive_c" "$HOME/Games" "$HOME/Wine" \
           "$HOME/.var/app/net.lutris.Lutris/data/lutris" "$HOME/.var/app/com.usebottles.bottles/data/bottles" \
           "$HOME/Downloads" "$HOME/Завантажене" "$HOME/Загрузки" "$HOME/Desktop" "$HOME/Documents" \
           /opt /mnt "/media/${USER:-x}" "/run/media/${USER:-x}"; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
}
find_nonsteam_games() {  # folders with mysummercar.exe outside Steam libraries
  {
    local r f d
    while IFS= read -r r; do   # games already added to Steam as non-Steam
      for f in "$r"/userdata/*/config/shortcuts.vdf; do
        [ -f "$f" ] && vdf shortcuts "$f" mysummercar.exe | awk -F'\037' '{print $3}'
      done
    done < <(steam_roots)
    grep -rhsiE '^[[:space:]]*exe:.*mysummercar\.exe' "$HOME/.config/lutris/games" \
         "$HOME/.var/app/net.lutris.Lutris/config/lutris/games" 2>/dev/null |
      sed -e 's/^[^:]*:[[:space:]]*//' -e "s/^[\"']//" -e "s/[\"']\$//"
    while IFS= read -r d; do
      find "$d" -maxdepth 7 \( -name steamapps -o -name .cache -o -name node_modules \) -prune -o -type f -iname mysummercar.exe -print 2>/dev/null
    done < <(nonsteam_roots | sort -u)
  } | while IFS= read -r p; do [ -f "$p" ] && dirname "$p"; done | grep -v '/steamapps/common/' | awk '!s[$0]++'
}
choose_default_dir() {  # choose_default_dir LIST HEADER_KEY -> DEF_DIR (the user confirms it with Enter)
  local list="$1" n i=0 line c
  DEF_DIR=""
  [ -n "$list" ] || { tn fnd_none; return 0; }
  n=$(printf '%s\n' "$list" | wc -l)
  if [ "$n" -eq 1 ]; then DEF_DIR="$list"; tn fnd_one "$list"; return 0; fi
  tn "$2"
  while IFS= read -r line; do i=$((i+1)); printf '      %d) %s\n' "$i" "$line"; done <<<"$list"
  read -r -p "  $(t fnd_pick 1)" c || bye
  c="${c:-1}"
  if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "$n" ]; then DEF_DIR=$(printf '%s\n' "$list" | sed -n "${c}p"); fi
}
setup_other_source() {  # a copy that is not in a Steam library: decides shortcut or wine
  local c
  GAME_PFX=""
  if detect_game_shortcut; then
    GAME_SRC=shortcut; GAME_APPID="$G_APPID"; COMPAT=$(compat_for "$G_APPID")
    to sc_found "$G_APPID" "$(pfx_dir "$G_APPID")"; return 0
  fi
  echo; tn how_head; note "  $(t how_1)"; note "  $(t how_2)"
  read -r -p "  $(t choice_prompt 2)" c || bye
  case "${c:-2}" in
    1) if [ "$DRY" != 1 ] && [ -z "$(steam_roots)" ]; then tw no_steam; return 1; fi
       GAME_SRC=shortcut; GAME_APPID=0000000001; COMPAT=$(compat_for 0000000001) ;;
    *) GAME_SRC=wine; GAME_APPID=wine
       setup_wine_prefix || { GAME_SRC=""; GAME_APPID=$STEAM_APPID; return 1; } ;;
  esac
}

# --- Wine prefix
find_prefix_of() {  # walks up from a folder to the Wine prefix that contains it
  local d="$1"
  while [ -n "$d" ] && [ "$d" != / ]; do
    [ -f "$d/system.reg" ] && [ -d "$d/drive_c" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}
wine_prefix_candidates() {
  local d f
  {
    for d in "$HOME/.wine" "${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes" "${XDG_DATA_HOME:-$HOME/.local/share}/bottles" \
             "${XDG_DATA_HOME:-$HOME/.local/share}/lutris" "$HOME/Games" "$HOME/Wine" \
             "$HOME/.var/app/net.lutris.Lutris/data/lutris" "$HOME/.var/app/com.usebottles.bottles/data/bottles"; do
      [ -d "$d" ] && find "$d" -maxdepth 6 \( -name steamapps -o -name .cache \) -prune -o -type f -name system.reg -print 2>/dev/null
    done
  } | while IFS= read -r f; do [ -d "$(dirname "$f")/drive_c" ] && dirname "$f"; done | awk '!s[$0]++'
}
setup_wine_prefix() {
  local p="$PFX_ARG" def cand
  [ -n "$p" ] || p=$(find_prefix_of "$GAME_DIR")
  if [ -n "$p" ] && [ -f "$p/system.reg" ]; then GAME_PFX="${p%/}"; to pfx_found "$GAME_PFX"; return 0; fi
  tn fnd_search
  choose_default_dir "$(wine_prefix_candidates)" pfx_cands; def="${DEF_DIR:-$p}"
  while :; do
    ask_path "$(t pfx_q)" "$def"
    [ "$REPLY_PATH" = q ] && return 1
    cand="${REPLY_PATH%/}"
    if [ ! -f "$cand/system.reg" ]; then
      tn pfx_bad "$cand"
      if [ "$DRY" = 1 ] && [ -n "$cand" ]; then tn pfx_dry_bad; else def=""; continue; fi
    fi
    GAME_PFX="$cand"; to pfx_found "$GAME_PFX"; return 0
  done
}

# --- Wine binary
set_wineserver() {
  WINESERVER_BIN="$(dirname "$WINE_BIN")/wineserver"
  [ -x "$WINESERVER_BIN" ] || WINESERVER_BIN=$(command -v wineserver 2>/dev/null || true)
}
detect_wine() {
  local w
  [ "${WINE_FAKE:-}" = 1 ] && return 0
  if [ -n "$WINE_BIN" ]; then
    [ -x "$WINE_BIN" ] || WINE_BIN=$(command -v "$WINE_BIN" 2>/dev/null || true)
    if [ -n "$WINE_BIN" ] && [ -x "$WINE_BIN" ]; then set_wineserver; return 0; fi
    WINE_BIN=""
  fi
  for w in wine wine64; do
    if have "$w"; then WINE_BIN=$(command -v "$w"); set_wineserver; return 0; fi
  done
  return 1
}
wine_runners() {  # Wine builds of Lutris / Bottles and Proton builds from Steam
  local r b
  for b in "${XDG_DATA_HOME:-$HOME/.local/share}"/lutris/runners/wine/*/bin/wine \
           "${XDG_DATA_HOME:-$HOME/.local/share}"/bottles/runners/*/bin/wine \
           "$HOME"/.var/app/net.lutris.Lutris/data/lutris/runners/wine/*/bin/wine \
           "$HOME"/.var/app/com.usebottles.bottles/data/bottles/runners/*/bin/wine; do
    [ -x "$b" ] && printf '%s\n' "$b"
  done
  while IFS= read -r r; do
    for b in "$r"/steamapps/common/Proton*/files/bin/wine "$r"/compatibilitytools.d/*/files/bin/wine; do
      [ -x "$b" ] && printf '%s\n' "$b"
    done
  done < <(steam_roots)
}
need_wine() {
  detect_wine && return 0
  local list n i=0 line c
  list=$(wine_runners)
  if [ -n "$list" ]; then
    tn wine_cands
    n=$(printf '%s\n' "$list" | wc -l)
    while IFS= read -r line; do i=$((i+1)); printf '      %d) %s\n' "$i" "$line"; done <<<"$list"
    read -r -p "  $(t wine_pick 1)" c || bye
    c="${c:-1}"
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "$n" ]; then
      WINE_BIN=$(printf '%s\n' "$list" | sed -n "${c}p"); set_wineserver; to wine_using "$WINE_BIN"; return 0
    fi
  fi
  tw need_wine_1
  tn need_pt_2; show "$(pm_hint wine)"
  tn need_wine_hint
  if [ "$DRY" = 1 ]; then
    dry_note "$(t need_wine_dry)"; WINE_FAKE=1; WINE_BIN=wine; WINESERVER_BIN=wineserver; return 0
  fi
  return 1
}
need_runner() { if [ "$GAME_SRC" = wine ]; then need_wine; else need_pt; fi; }
run_in_wine() {  # run_in_wine FILE : a Windows program inside the game's Wine prefix
  ensure_idle
  if [ "$DRY" = 1 ]; then
    dry_note "$(t run_dry "$(basename "$1")" "$GAME_PFX")" "cd $(printf '%q' "$(dirname "$1")") && WINEPREFIX=$(printf '%q' "$GAME_PFX") ${WINE_BIN:-wine} $(printf '%q' "$1")"
    return 0
  fi
  tn run_now "$(basename "$1")" "$GAME_PFX"
  ( cd "$(dirname "$1")" && WINEPREFIX="$GAME_PFX" WINEDEBUG=-all "$WINE_BIN" "$1" 2>&1 | grep -v -E 'fixme|use_kernel_writewatch|^info:|^warn:' )
}
wine_cmd() {  # wine_cmd EXE WITH_OVERRIDES(1|0) -> ready command line
  local ovr=""; [ "$2" = 1 ] && ovr=" $WINE_OPTS"
  printf 'cd %q && WINEPREFIX=%q%s %q %q' "$(dirname "$1")" "$GAME_PFX" "$ovr" "${WINE_BIN:-wine}" "$(basename "$1")"
}
write_wine_script() {  # write_wine_script FILE EXE WITH_OVERRIDES
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cd %q || exit 1\n' "$(dirname "$2")"
    printf 'export WINEPREFIX=%q\n' "$GAME_PFX"
    [ "$3" = 1 ] && printf 'export %s\n' "$WINE_OPTS"
    printf 'exec %q %q "$@"\n' "${WINE_BIN:-wine}" "$(basename "$2")"
  } > "$1" && chmod +x "$1"
}
make_wine_script() {  # make_wine_script FILE EXE WITH_OVERRIDES (asks first, never overwrites)
  if [ -e "$1" ]; then tn ws_script_have "$1"; return 0; fi
  yesno "$(t ws_script_q "$1")" y || return 0
  act "$(t act_script "$1")" write_wine_script "$1" "$2" "$3"
  [ "$DRY" = 1 ] || to ws_script_done "$1"
}

# --- steps for the non-Steam modes
verify_game_shortcut() {
  [ -n "$G_APPID" ] || return 0
  local e="$GAME_DIR/mysummercar.exe" tool
  if [ "$G_EXE" = "$e" ]; then to vf_target_ok "$G_EXE"; else tw vf_target_bad "$G_EXE" "$e"; fi
  if [ "${G_START%/}" = "${GAME_DIR%/}" ]; then to vf_start_ok; else tw vf_start_bad "$G_START" "$GAME_DIR/"; fi
  if launch_opts_ok; then to vf_opts_ok; else tw vf_opts_bad "$G_OPTS" "$GAME_OPTS"; fi
  tool=$(steam_compat_tool "$G_APPID")
  if [ -z "$tool" ]; then tw vf_proton_none "$PROTON_GAME"
  elif [ "$tool" = "$(proton_id "$PROTON_GAME")" ]; then to vf_proton "$tool" "$PROTON_GAME"
  else tw vf_proton "$tool" "$PROTON_GAME"; fi
  tn vf_flush
}
step_game_settings_shortcut() {
  local e="$GAME_DIR/mysummercar.exe"
  ts st_gsettings
  adopt_game_shortcut
  if [ "$DEMO" != 1 ] && [ -n "$G_APPID" ] && launch_opts_ok && game_prefix_ok; then to gs_already; verify_game_shortcut; return 0; fi
  if [ -z "$G_APPID" ]; then
    tn sc_1
    tn sc_2; show_copy "$e"
    tn sc_3; pause
  fi
  tn sc_4
  tn ch_target; show_copy "\"$e\""
  tn ch_start; show_copy "\"$GAME_DIR/\""
  tn gs_2 "$PROTON_GAME"; note "$(proton_state "$PROTON_GAME")"
  tn gs_3
  show_copy "$GAME_OPTS"
  tn vf_flush
  pause
  adopt_game_shortcut
  if [ "$DRY" = 1 ]; then
    [ -n "$G_APPID" ] || GAME_APPID=0000000001
    if game_prefix_ok; then to gs_pfx_found "$(pfx_dir "$GAME_APPID")"; else dry_note "$(t gs_dry_wait)"; fi
    return 0
  fi
  until adopt_game_shortcut && game_prefix_ok; do
    [ -n "$G_APPID" ] || tw gsc_nolink
    tn gs_wait
    pause
  done
  to gs_pfx_ok
  verify_game_shortcut
}
step_game_settings_wine() {
  local e="$GAME_DIR/mysummercar.exe"
  ts st_gsettings
  tn ws_intro
  tn ws_pfx "$GAME_PFX"
  tn ws_exe "$e"
  tn ws_arg; show_copy "$WINE_OPTS"
  tn ws_lutris; tn ws_bottles; tn ws_heroic
  tn ws_cmd; show_copy "$(wine_cmd "$e" 1)"
  make_wine_script "$GAME_DIR/start-msc.sh" "$e" 1
  if [ "$DRY" = 1 ]; then return 0; fi
  until game_prefix_ok; do tn ws_pfx_missing; pause; done
}
step_launcher_wine() {
  ts st_lwine
  local e; e=$(wmp_entry) || td no_entry
  tn lw_1
  tn lw_2; show_copy "$(wine_cmd "$e" 0)"
  tn lw_3
  make_wine_script "$GAME_DIR/start-wreckmp.sh" "$e" 0
  tn lw_4
}
wine_cheatsheet() {
  local e; detect_wine
  e=$(wmp_entry_guess)
  ts st_cheat_w
  tn ws_pfx "$GAME_PFX"; tn ws_exe "$GAME_DIR/mysummercar.exe"
  tn ws_arg; show "$WINE_OPTS"
  tn ws_lutris; tn ws_bottles; tn ws_heroic
  tn ws_cmd; show "$(wine_cmd "$GAME_DIR/mysummercar.exe" 1)"
  tn lw_2; show "$(wine_cmd "$e" 0)"
}
recap_wine() {  # recap_wine MODE
  tn rcw_1; show "$(wine_cmd "$GAME_DIR/mysummercar.exe" 1)"
  if [ "$1" != 1 ]; then
    tn rcw_2; show "$(wine_cmd "$(wmp_entry_guess)" 0)"
  fi
  tn rcw_3
  tn rcw_4
  echo
  tn rc_dont
  tn rc_more "$SELF" "$SELF"
}

# ================================================================== steps
choose_game_src() {  # sets SRC_KIND (steam|other); the default is what the search finds
  local c def=1 sl
  tn fnd_search
  sl=$(find_game_dirs)
  [ -z "$sl" ] && def=2
  echo; tn src_head
  note "  $(t src_1)"; note "  $(t src_2)"
  read -r -p "  $(t choice_prompt "$def")" c || bye
  case "${c:-$def}" in 2) SRC_KIND=other ;; *) SRC_KIND=steam ;; esac
}
step_game_dir() {  # asks until a valid folder is given; returns 1 if the user cancels (q)
  ts st_gamedir
  local def cand list
  if [ -z "$SRC_KIND" ] && [ -n "$GAME_DIR_ARG" ]; then
    case "$GAME_DIR_ARG" in */steamapps/common/*) SRC_KIND=steam ;; *) SRC_KIND=other ;; esac
  fi
  [ -n "$SRC_KIND" ] || choose_game_src
  tn fnd_search
  if [ "$SRC_KIND" = steam ]; then list=$(find_game_dirs); else list=$(find_nonsteam_games); fi
  choose_default_dir "$list" fnd_list; def="$DEF_DIR"
  if [ -n "$GAME_DIR_ARG" ]; then def="$GAME_DIR_ARG"; GAME_DIR_ARG=""; fi
  while :; do
    ask_path "$(t q_gamedir "$GAME_NAME")" "$def"
    if [ "$REPLY_PATH" = q ]; then return 1; fi
    cand="${REPLY_PATH%/}"
    if [ ! -f "$cand/mysummercar.exe" ]; then
      tn gamedir_nf "$cand"
      if [ "$DRY" = 1 ] && [ -n "$cand" ] && yesno "$(t gamedir_dryq)" y; then :; else def=""; continue; fi
    fi
    if [ "$SRC_KIND" = steam ]; then
      case "$cand" in
        */steamapps/common/*) LIB="${cand%/steamapps/common/*}" ;;
        *) if [ "$DRY" = 1 ]; then tw gamedir_dlib; LIB="$HOME/.local/share/Steam"; else tw gamedir_lib; def=""; continue; fi ;;
      esac
      GAME_DIR="$cand"; GAME_SRC=steam; GAME_APPID=$STEAM_APPID; GAME_PFX=""; COMPAT="$LIB/steamapps/compatdata"
      return 0
    fi
    GAME_DIR="$cand"
    setup_other_source || { GAME_DIR=""; def="$cand"; continue; }
    return 0
  done
}
need_game_dir() { [ -n "$GAME_DIR" ] || step_game_dir; }

step_game_settings() {
  case "$GAME_SRC" in
    wine)     step_game_settings_wine ;;
    shortcut) step_game_settings_shortcut ;;
    *)        step_game_settings_steam ;;
  esac
}
step_game_settings_steam() {
  ts st_gsettings
  if [ "$DEMO" != 1 ] && launch_opts_ok && game_prefix_ok; then to gs_already; return 0; fi
  local tool opts
  tool=$(steam_compat_tool "$GAME_APPID"); opts=$(steam_launch_opts "$GAME_APPID")
  if [ -n "$tool$opts" ]; then tn gs_now "${tool:-$(t unset_val)}" "${opts:-$(t none_val)}"; fi
  tn gs_1 "$GAME_NAME"
  tn gs_2 "$PROTON_GAME"; note "$(proton_state "$PROTON_GAME")"
  tn gs_3
  show_copy "$GAME_OPTS"
  pause
  if [ "$DRY" = 1 ]; then
    if game_prefix_ok; then to gs_pfx_found "$(pfx_dir "$GAME_APPID")"; else dry_note "$(t gs_dry_wait)"; fi
    return 0
  fi
  until game_prefix_ok; do
    tn gs_wait
    pause
  done
  to gs_pfx_ok
}

warn_native_leftovers() {
  local f found=""
  for f in "$GAME_DIR/mysummercar.x86_64" "$GAME_DIR/run.sh" "$GAME_DIR/libdoorstop.so"; do [ -e "$f" ] && found="$found$f"$'\n'; done
  for f in "$HOME"/.steam/*/compatibilitytools.d/msc* "$HOME"/.local/share/Steam/compatibilitytools.d/msc*; do [ -e "$f" ] && found="$found$f"$'\n'; done
  [ -z "$found" ] && return 0
  tw nl_warn
  printf '%s' "$found" | sed 's/^/      /'
  tn nl_1; tn nl_2
  pause
}

step_mscl() {
  ts st_mscl "$MSCL_VERSION"
  warn_native_leftovers
  if mscl_installed; then to mscl_have; return 0; fi
  mk_work
  local zip tmp inst
  tn mscl_manual; show "$URL_MSCLOADER"
  pause
  while :; do
    ask_path "$(t q_path_mscl)" "$(newest_match 'mscl|msc.?loader')"
    zip="$REPLY_PATH"
    [ -f "$zip" ] && break
    if [ "$DRY" = 1 ]; then tw file_nf_dry "$zip"; break; fi
    tw file_nf "$zip"
  done
  if [ "$DRY" = 1 ]; then
    tmp="$WORK/mscl.XXXXXX"; inst="$tmp/MSCLInstaller.exe"
    dry_note "$(t act_unzip "$zip" "$tmp")" "unzip -q -o $(printf '%q' "$zip") -d $tmp"
  else
    tmp=$(mktemp -d "$WORK/mscl.XXXXXX") || td mktemp_fail
    extract_zip "$zip" "$tmp" || { have_unzip || tw dep_miss unzip "$(pm_hint unzip)"; td unzip_fail; }
    inst=$(find "$tmp" -iname 'MSCLInstaller.exe' | head -n1)
    [ -n "$inst" ] || td no_installer
  fi
  while :; do
    tn mscl_open_1 "$([ "$GAME_SRC" = wine ] && printf %s "$GAME_PFX" || printf %s "$GAME_APPID")"
    tn mscl_open_2
    show "$(win_path "$GAME_DIR")"
    tn mscl_open_3
    run_in_prefix "$GAME_APPID" "$inst"
    pause
    if [ "$DRY" = 1 ]; then SIM_MSCL=1; fi
    mscl_installed && break
    tw mscl_missing
    yesno "$(t q_retry)" y || td mscl_need
  done
  case "$tmp" in "$WORK"/mscl.*) [ "$DRY" = 1 ] || rm -rf "$tmp" ;; esac
  to mscl_done "$([ "$DRY" = 1 ] && t dry_suffix)"
}

step_wmp() {
  ts st_wmp
  if ! mscl_present; then
    if [ "$DRY" = 1 ]; then tw wmp_need_dry; else td wmp_need; fi
  fi
  if wmp_installed; then to wmp_have "$GAME_DIR"; return 0; fi
  tn wmp_dl_1
  show "$LINK_WRECKMP"
  tn wmp_dl_2
  ask_path "$(t q_path_wmp)" "$(newest_match 'wreck')"
  local f="$REPLY_PATH" tmp src
  if [ ! -f "$f" ]; then
    if [ "$DRY" = 1 ]; then tw file_nf_dry "$f"; else td file_nf "$f"; fi
  fi
  [ -n "$f" ] || f="$HOME/Downloads/WreckMPsetup.exe"
  case "$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')" in
    *.zip)
      if [ "$DRY" = 1 ]; then
        dry_note "$(t act_unzip_wmp "$GAME_DIR")" "unzip -q -o $(printf '%q' "$f") -d <tmp> && cp -a <contents>/. $(printf '%q' "$GAME_DIR/WreckMP")/"
      else
        mkdir -p "$WORK"; tmp=$(mktemp -d "$WORK/wmp.XXXXXX")
        extract_zip "$f" "$tmp" || td unzip_wmp_fail
        src="$tmp"; set -- "$tmp"/*
        if [ $# -eq 1 ] && [ -d "$1" ]; then src="$1"; fi
        mkdir -p "$GAME_DIR/WreckMP" && cp -a "$src"/. "$GAME_DIR/WreckMP"/
        rm -rf "$tmp"
      fi ;;
    *.exe)
      tn wmp_exe_1 "$GAME_DIR"
      tn wmp_exe_2; show "$(win_path "$GAME_DIR")"
      run_in_prefix "$GAME_APPID" "$f"; pause ;;
    *) td bad_filetype ;;
  esac
  if [ "$DRY" = 1 ]; then SIM_WMP=1; fi
  wmp_installed || td wmp_verify "$GAME_DIR"
  to wmp_done "$([ "$DRY" = 1 ] && t dry_suffix)"
}

get_dotnet_installer() {
  [ -n "$DOTNET_EXE" ] && { [ -f "$DOTNET_EXE" ] || [ "$DRY" = 1 ]; } && return 0
  mk_work
  local out="$WORK/windowsdesktop-runtime-6-win-x64.exe"
  DOTNET_EXE=$(newest_match 'windowsdesktop-runtime-6.*x64')
  [ -n "$DOTNET_EXE" ] && return 0
  if [ -f "$out" ] && [ "$(wc -c < "$out")" -gt 30000000 ]; then DOTNET_EXE="$out"; return 0; fi
  if yesno "$(t dn_q_dl)" y; then
    if [ "$DRY" = 1 ]; then act "$(t act_dl_dn)" fetch "$URL_DOTNET" "$out"; DOTNET_EXE="$out"; return 0; fi
    if fetch "$URL_DOTNET" "$out" && [ "$(wc -c < "$out")" -gt 30000000 ]; then DOTNET_EXE="$out"; return 0; fi
    rm -f "$out"; tw dn_dl_fail
  fi
  tn dn_manual
  show "$LINK_DOTNET"
  ask_path "$(t dn_q_path)" ""
  if [ ! -f "$REPLY_PATH" ]; then
    [ "$DRY" = 1 ] || return 1
    tw file_nf_dry "$REPLY_PATH"
  fi
  DOTNET_EXE="$REPLY_PATH"
}
step_dotnet() {  # step_dotnet APPID game|launcher
  local id="$1" who; who=$(t "word_$2")
  ts st_dotnet "$who" "$id"
  if has_dotnet6 "$id"; then to dn_have; return 0; fi
  tn dn_note
  get_dotnet_installer || td dn_none
  while :; do
    run_in_prefix "$id" "$DOTNET_EXE"
    pause
    if [ "$DRY" = 1 ]; then if [ "$id" = "$GAME_APPID" ]; then SIM_DOTNET_GAME=1; else SIM_DOTNET_LA=1; fi; fi
    has_dotnet6 "$id" && break
    tw dn_missing "$id"
    yesno "$(t q_retry)" y || td dn_need
  done
  to dn_done "$id" "$([ "$DRY" = 1 ] && t dry_suffix)"
}

step_updater_in_game_prefix() {
  ts st_updater
  local e; e=$(wmp_entry) || return 0
  tn up_note "$GAME_APPID"
  yesno "$(t q_up)" n || return 0
  tn up_wait
  run_in_prefix "$GAME_APPID" "$e"; pause
}

step_shortcut() {
  ts st_shortcut
  local e; e=$(wmp_entry) || td no_entry
  tn sc_1
  tn sc_2; show_copy "$e"
  tn sc_3; pause
  tn sc_4
  tn sc_5; show_copy "\"$e\""; pause
  tn sc_6; show_copy "\"$(dirname "$e")/\""; pause
  tn sc_7; show_copy "$LAUNCHER_OPTS"
  tn sc_8; pause
  tn sc_9 "$PROTON_LAUNCHER"; note "$(proton_state "$PROTON_LAUNCHER")"; pause
}

verify_launcher_shortcut() {  # compares the shortcut Steam saved with the recommended values
  [ -n "$L_APPID" ] || return 0
  local e tool; e=$(wmp_entry_guess)
  if [ "$L_EXE" = "$e" ]; then to vf_target_ok "$L_EXE"; else tw vf_target_bad "$L_EXE" "$e"; fi
  if [ "${L_START%/}" = "$(dirname "$e")" ]; then to vf_start_ok; else tw vf_start_bad "$L_START" "$(dirname "$e")/"; fi
  if lopts_ok; then to vf_opts_ok; else tw vf_opts_bad "$L_OPTS" "$LAUNCHER_OPTS"; fi
  tool=$(steam_compat_tool "$L_APPID")
  if [ -z "$tool" ]; then tw vf_proton_none "$PROTON_LAUNCHER"
  elif [ "$tool" = "$(proton_id "$PROTON_LAUNCHER")" ]; then to vf_proton "$tool" "$PROTON_LAUNCHER"
  else tw vf_proton "$tool" "$PROTON_LAUNCHER"; fi
  tn vf_flush
}

step_launcher_first_start() {
  ts st_first
  tn fs_1; tn fs_2
  pause
  if detect_launcher_prefix; then to fs_found "$LA"; verify_launcher_shortcut; return 0; fi
  tw fs_notfound
  local cands id
  cands=$(ls -1t "$COMPAT" 2>/dev/null | grep -E '^[0-9]+$' | grep -v "^$GAME_APPID\$" | head -n 5)
  tn fs_cands
  for id in $cands; do printf '      %s   (%s)\n' "$id" "$(date -r "$COMPAT/$id" '+%F %T' 2>/dev/null)"; done
  read -e -r -i "$(printf '%s\n' "$cands" | head -n1)" -p "  $(t fs_q)" LA || bye
  if ! [[ "$LA" =~ ^[0-9]+$ ]] || [ ! -d "$COMPAT/$LA/pfx" ]; then
    if [ "$DRY" = 1 ]; then
      tw fs_dry_none "$LA"
      [[ "$LA" =~ ^[0-9]+$ ]] || LA=0000000000
    else
      td fs_nosuch "$LA"
    fi
  fi
}

block_patreon() {
  tn bp_1
  show "127.0.0.1 www.patreon.com patreon.com    ::1 www.patreon.com patreon.com"
  tn bp_2
  show "sudo sed -i '/patreon\\.com/d' /etc/hosts"
  tn bp_3
  yesno "$(t q_bp)" y || return 1
  if [ "$DRY" = 1 ]; then
    dry_note "$(t act_hosts)" "printf '%s\\n' '127.0.0.1 www.patreon.com patreon.com' '::1 www.patreon.com patreon.com' | sudo tee -a /etc/hosts"
    SIM_HOSTS=1; return 0
  fi
  local el=""
  if [ "$(id -u)" = 0 ]; then el=""
  elif have sudo; then el=sudo
  elif have doas; then el=doas
  elif have pkexec; then el=pkexec
  else tw bp_nosudo; return 1; fi
  if ! printf '%s\n' "127.0.0.1 www.patreon.com patreon.com" "::1 www.patreon.com patreon.com" | $el tee -a /etc/hosts >/dev/null; then tw bp_failed; return 1; fi
}
step_launcher_test() {
  ts st_ltest
  if ! hosts_blocked; then tn lt_pre; block_patreon || tn lt_skip; fi
  if [ "$GAME_SRC" = wine ]; then tn lt_1w; else tn lt_1; fi
  pause
  if ! yesno "$(t q_lt)" y; then
    if hosts_blocked; then
      tw lt_hosts "$GAME_DIR"
    else
      tn lt_crash
      if block_patreon; then tn lt_retry; pause; else tn lt_skip; fi
    fi
  fi
}

reg_content() {  # registry for the launcher (CRLF): game folder + install location, 64- and 32-bit views
  local w k
  w=$(win_path "$GAME_DIR" | sed 's#\\#\\\\#g')
  printf 'Windows Registry Editor Version 5.00\r\n\r\n'
  for k in 'Software' 'Software\Wow6432Node'; do
    printf '[HKEY_CURRENT_USER\\%s\\MaceeikoDevelopment\\WreckMP]\r\n' "$k"
    printf '"GameDirectory"="%s"\r\n\r\n' "$w"
    printf '[HKEY_LOCAL_MACHINE\\%s\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WreckMP]\r\n' "$k"
    printf '"DisplayIcon"="%s\\\\WreckMP\\\\Updater.exe"\r\n' "$w"
    printf '"DisplayName"="WreckMP"\r\n'
    printf '"InstallLocation"="%s\\\\WreckMP"\r\n' "$w"
    printf '"UninstallString"="%s\\\\WreckMP\\\\Uninstall.exe"\r\n\r\n' "$w"
  done
}
step_reg() {
  ts st_reg
  if reg_written; then to reg_have "$LA"; return 0; fi
  if have python3 && [ "$DRY" != 1 ]; then          # direct write: no protontricks, works with any Proton
    ensure_idle
    tn reg_direct "$LA"
    cp -a "$(pfx_dir "$LA")/user.reg" "$(pfx_dir "$LA")/user.reg.wizard-bak" 2>/dev/null
    cp -a "$(pfx_dir "$LA")/system.reg" "$(pfx_dir "$LA")/system.reg.wizard-bak" 2>/dev/null
    regpy wmp "$(pfx_dir "$LA")" "$(win_path_u "$(readlink -f "$GAME_DIR")")" >/dev/null
    if reg_written; then to reg_ok; return 0; fi
  fi
  need_runner || return 1; ensure_idle
  local f cmd
  f="$(pfx_dir "$LA")/drive_c/wmp-wizard.reg"   # inside the prefix (C:\): every Wine/Proton sees it
  if [ "$GAME_SRC" = wine ]; then
    cmd="WINEPREFIX=$(printf '%q' "$GAME_PFX") ${WINE_BIN:-wine} regedit /S 'C:\\wmp-wizard.reg'"
  else
    cmd="${PT[*]} -c 'wine regedit /S \"C:\\wmp-wizard.reg\"; \"\$WINESERVER\" -w' $LA"
  fi
  if [ "$DRY" = 1 ]; then
    dry_note "$(t act_reg_w "$f")"
    reg_content | tr -d '\r' | sed 's/^/            | /'
    dry_note "$(t act_reg_i "$LA")" "$cmd"
    SIM_REG=1; return 0
  fi
  [ -d "$(dirname "$f")" ] || { tw reg_bad; return 1; }
  reg_content > "$f" || { tw reg_bad; return 1; }
  tn reg_note "$f" "$LA"
  if [ "$GAME_SRC" = wine ]; then
    ( WINEPREFIX="$GAME_PFX" WINEDEBUG=-all "$WINE_BIN" regedit /S 'C:\wmp-wizard.reg'
      WINEPREFIX="$GAME_PFX" "${WINESERVER_BIN:-wineserver}" -w ) 2>&1 | grep -v -E 'fixme|use_kernel_writewatch|^info:|^warn:'
  else
    "${PT[@]}" -c 'wine regedit /S "C:\wmp-wizard.reg"; "$WINESERVER" -w' "$LA" 2>&1 | grep -v -E 'fixme|use_kernel_writewatch|^info:|^warn:|steam-runtime|ntsync'
  fi
  rm -f "$f"
  if reg_written; then to reg_ok; else tw reg_bad; fi
}

sync_guid() {  # game prefix MachineGuid := launcher prefix MachineGuid (as the author did)
  local reg_l reg_g src dst
  reg_l="$(pfx_dir "$LA")/system.reg"; reg_g="$(pfx_dir "$GAME_APPID")/system.reg"
  src=$(guid_of "$reg_l"); dst=$(guid_of "$reg_g")
  if [ "$DRY" = 1 ] && { [ -z "$src" ] || [ -z "$dst" ]; }; then
    dry_note "$(t guid_dry_nd)"; SIM_GUID=1; return 0
  fi
  [ -n "$src" ] || { tw guid_nol "$reg_l"; return 1; }
  [ -n "$dst" ] || { tw guid_nog "$reg_g"; return 1; }
  if [ "$src" = "$dst" ]; then to guid_same "$src"; return 0; fi
  tn guid_l "$src"; tn guid_g "$dst"
  tn guid_close
  pause; ensure_idle
  local bak="$reg_g.bak.$(date +%Y%m%d-%H%M%S)"
  if [ "$DRY" = 1 ]; then
    dry_note "$(t act_guid_bak "$bak")" "cp -a $(printf '%q' "$reg_g") $(printf '%q' "$bak")"
    dry_note "$(t act_guid_sed "$src")" "sed -i 's/\"MachineGuid\"=\"$dst\"/\"MachineGuid\"=\"$src\"/' $(printf '%q' "$reg_g")"
    SIM_GUID=1; return 0
  fi
  cp -a "$reg_g" "$bak" || { tw guid_bakfail; return 1; }
  sed -i "s/\"MachineGuid\"=\"$dst\"/\"MachineGuid\"=\"$src\"/" "$reg_g"
  if [ "$(guid_of "$reg_g")" = "$src" ]; then to guid_done "$bak"; else tw guid_fail "$bak"; return 1; fi
}
step_guid() {
  ts st_guid
  tn guid_intro
  sync_guid
}

# ================================================================== cheat sheet / warning / recap
steam_cheatsheet() {
  local DEMO=0 e tool opts
  if [ "$GAME_SRC" = wine ]; then wine_cheatsheet; return 0; fi
  ts st_cheat
  [ "$GAME_SRC" = shortcut ] && adopt_game_shortcut
  detect_launcher_prefix
  e=$(wmp_entry_guess)
  echo
  note "$(t ch_a "$GAME_NAME")"
  if [ "$GAME_SRC" = shortcut ]; then
    tn ch_b_file; show "$GAME_DIR/mysummercar.exe"
    tn ch_target; show "\"$GAME_DIR/mysummercar.exe\""
    tn ch_start; show "\"$GAME_DIR/\""
  fi
  note "$(t ch_compat "$PROTON_GAME")"; note "$(proton_state "$PROTON_GAME")"
  tool=$(steam_compat_tool "$GAME_APPID")
  note "$(t ch_now_p "${tool:-$(t unset_val)}") $(mark "$tool" "$(proton_id "$PROTON_GAME")")"
  tn ch_opts; show "$GAME_OPTS"
  if [ "$GAME_SRC" = shortcut ]; then opts="$G_OPTS"; else opts=$(steam_launch_opts "$GAME_APPID"); fi
  note "$(t ch_now_o "${opts:-$(t none_val)}") $(mark "$opts" "$GAME_OPTS")"
  echo
  note "$(t ch_b)"
  tn ch_b_file; show "$e"
  wmp_real || tn ch_b_guess
  tn ch_target; show "\"$e\""
  tn ch_start; show "\"$(dirname "$e")/\""
  tn ch_opts; show "$LAUNCHER_OPTS"
  tn ch_compat "$PROTON_LAUNCHER"; note "$(proton_state "$PROTON_LAUNCHER")"
  if [ -n "$L_APPID" ]; then
    tool=$(steam_compat_tool "$L_APPID")
    note "$(t ch_now_p "${tool:-$(t unset_val)}") $(mark "$tool" "$(proton_id "$PROTON_LAUNCHER")")"
    note "$(t ch_now_t "${L_EXE:-$(t none_val)}") $(mark "$L_EXE" "$e")"
    note "$(t ch_now_s "${L_START:-$(t none_val)}") $(mark "${L_START%/}" "$(dirname "$e")")"
    note "$(t ch_now_o "${L_OPTS:-$(t none_val)}") $(mark "$L_OPTS" "$LAUNCHER_OPTS")"
  fi
  echo
  note "$(t ch_c)"
  note "$(t ch_c1 "$PROTON_INSTALL")"
  echo
  tn ch_flush
  note "$(t ch_tune_hint "$SELF")"
  caps_warning
}

caps_warning() {
  local bar k l
  bar='  !!! ======================================================== !!!'
  printf '\n%s\n  !!!  %s\n' "$bar" "$(t caps_head)"
  for k in caps_1 caps_2 caps_3 caps_4; do
    echo '  !!!'
    if [ "$k" = caps_1 ]; then printf '%s\n' "$(t "$k" "$LAUNCHER_DIALOG")"; else printf '%s\n' "$(t "$k")"; fi |
      while IFS= read -r l; do printf '  !!!  %s\n' "$l"; done
  done
  printf '  !!!      bash %s --fix-guid\n' "$SELF"
  printf '%s\n\n' "$bar"
}

recap() {  # recap MODE
  ts st_done
  if [ "$GAME_SRC" = wine ]; then recap_wine "$1"; return 0; fi
  tn rc_steam
  note "  $(t rc_game "$GAME_NAME" "$PROTON_GAME" "$GAME_OPTS")"
  if [ "$1" != 1 ]; then note "  $(t rc_launcher "$PROTON_LAUNCHER" "$LAUNCHER_OPTS")"; fi
  echo
  tn rc_how
  if [ "$1" = 1 ]; then
    note "  $(t rc_1_1)"
    note "  $(t rc_1_2 "$MSCL_VERSION")"
  else
    note "  $(t rc_2_1)"
    note "  $(t rc_2_2)"
    note "     $(t rc_2_3 "$LAUNCHER_DIALOG")"
    note "  $(t rc_2_4)"
    note "     $(t rc_2_5)"
    note "  $(t rc_2_6 "$SELF")"
  fi
  echo
  tn rc_dont
  tn rc_more "$SELF" "$SELF"
}

dry_summary() {
  ts dry_sum_head
  if [ "${#DRY_LOG[@]}" -eq 0 ]; then
    tn dry_sum_none
  else
    tn dry_sum_n "${#DRY_LOG[@]}"
    local i=1 l
    for l in "${DRY_LOG[@]}"; do printf '    %2d. %s\n' "$i" "$l"; i=$((i+1)); done
  fi
  [ "$DEMO" = 1 ] && tn dry_sum_demo
  return 0
}

# ================================================================== PC tuning: hardware -> launch options
# Reads the hardware (READ ONLY: /sys, /proc, optional lspci / nvidia-smi, so it works on any
# distribution) and builds Steam Launch Options that fit THIS computer. Nothing here needs root.
HW_GPU_VENDOR=(); HW_GPU_NAME=(); HW_GPU_DRV=(); HW_GPU_BOOT=(); HW_GPU_VRAM=()
HW_BEST=-1; HW_HYBRID=0; HW_PROFILE=unknown; HW_CORES=0; HW_RAM_MB=0; HW_CPU=""
HW_SESSION=""; HW_DECK=0; HW_SANDBOX=0
TUNE_ENV=""; TUNE_PRE=""

hw_read() { [ -r "$1" ] && tr -d '\n' < "$1"; }   # first line of a sysfs file, empty if unreadable

hw_vendor_name() {  # PCI vendor id -> short key
  case "$1" in
    0x10de) echo nvidia ;;
    0x1002) echo amd ;;
    0x8086) echo intel ;;
    0x1af4|0x1234|0x15ad|0x80ee|0x1b36) echo vm ;;
    *)      echo other ;;
  esac
}
hw_pci_name() {  # hw_pci_name ADDR VENDOR_KEY DEVICE_ID -> a readable model name
  local n=""
  if have lspci; then
    n=$(lspci -s "$1" -mm 2>/dev/null | head -n1 | awk -F'"' '{print $6}')
    case "$n" in *\[*\]*) n=$(printf '%s' "$n" | sed 's/.*\[\(.*\)\].*/\1/') ;; esac
  fi
  if [ "$2" = nvidia ] && have nvidia-smi; then
    n=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
  fi
  [ -n "$n" ] || n="PCI device $3"
  printf '%s' "$n"
}
hw_detect() {
  HW_GPU_VENDOR=(); HW_GPU_NAME=(); HW_GPU_DRV=(); HW_GPU_BOOT=(); HW_GPU_VRAM=()
  local c dev cls v vk did addr drv boot vram
  for c in /sys/class/drm/card*; do
    [ -e "$c" ] || continue
    case "${c##*/}" in card[0-9]*-*) continue ;; esac     # skip connectors (card0-eDP-1)
    dev=$(readlink -f "$c/device" 2>/dev/null) || continue
    [ -d "$dev" ] || continue
    cls=$(hw_read "$dev/class"); case "$cls" in 0x03*) ;; *) continue ;; esac
    v=$(hw_read "$dev/vendor"); did=$(hw_read "$dev/device"); vk=$(hw_vendor_name "$v")
    addr="${dev##*/}"
    drv=""; [ -L "$dev/driver" ] && drv=$(basename "$(readlink -f "$dev/driver")")
    boot=$(hw_read "$dev/boot_vga"); boot="${boot:-0}"
    vram=0; if [ -r "$dev/mem_info_vram_total" ]; then vram=$(( $(hw_read "$dev/mem_info_vram_total") / 1048576 )); fi
    if [ "$vram" -eq 0 ] && [ "$vk" = nvidia ] && have nvidia-smi; then   # sysfs shows VRAM only for AMD
      vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -cd '0-9'); vram="${vram:-0}"
    fi
    HW_GPU_VENDOR+=("$vk"); HW_GPU_NAME+=("$(hw_pci_name "$addr" "$vk" "$did")")
    HW_GPU_DRV+=("${drv:-?}"); HW_GPU_BOOT+=("$boot"); HW_GPU_VRAM+=("$vram")
  done
  HW_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0)
  HW_RAM_MB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null); HW_RAM_MB="${HW_RAM_MB:-0}"
  HW_CPU=$(grep -m1 -iE '^(model name|hardware|cpu model)' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
  if [ -z "$HW_CPU" ] && have lscpu; then HW_CPU=$(lscpu 2>/dev/null | awk -F: '/Model name/{sub(/^[ \t]+/,"",$2); print $2; exit}'); fi
  HW_SESSION="${XDG_SESSION_TYPE:-unknown}"
  HW_DECK=0
  case "$(hw_read /sys/devices/virtual/dmi/id/product_name)" in Jupiter|Galileo) HW_DECK=1 ;; esac
  HW_SANDBOX=0
  case "$GAME_DIR $LIB $COMPAT" in *com.valvesoftware.Steam*|*/snap/steam/*) HW_SANDBOX=1 ;; esac
  hw_classify
}
hw_classify() {  # picks the GPU that should render the game and the profile name
  local n=${#HW_GPU_VENDOR[@]} i nv=-1 amd=-1 amdn=0 intel=0 vm=0 best=-1 bv=-1
  HW_BEST=-1; HW_HYBRID=0; HW_PROFILE=unknown
  [ "$n" -gt 0 ] || return 0
  for ((i=0; i<n; i++)); do
    case "${HW_GPU_VENDOR[$i]}" in
      nvidia) [ "$nv" -lt 0 ] && nv=$i ;;
      amd)    amdn=$((amdn+1)); if [ "${HW_GPU_VRAM[$i]}" -gt "$bv" ]; then bv="${HW_GPU_VRAM[$i]}"; amd=$i; fi ;;
      intel)  intel=$((intel+1)) ;;
      vm)     vm=$((vm+1)) ;;
    esac
  done
  if   [ "$nv" -ge 0 ]; then best=$nv
  elif [ "$amd" -ge 0 ] && { [ "$intel" -gt 0 ] || [ "$amdn" -gt 1 ]; }; then best=$amd
  elif [ "$amd" -ge 0 ]; then best=$amd
  else best=0; fi
  HW_BEST=$best
  [ "$n" -gt 1 ] && [ "$vm" -lt "$n" ] && HW_HYBRID=1
  if [ "$vm" -eq "$n" ]; then HW_PROFILE=vm
  elif [ "$HW_DECK" = 1 ]; then HW_PROFILE=deck; HW_HYBRID=0
  elif [ "${HW_GPU_VENDOR[$best]}" = nvidia ] && [ "${HW_GPU_DRV[$best]}" = nvidia ]; then HW_PROFILE=nvidia
  else HW_PROFILE=mesa; fi
}

tune_nv_short() {  # "NVIDIA GeForce GTX 1650" -> "GTX 1650" (DXVK matches a substring of the device name)
  printf '%s' "$1" | sed -e 's/^NVIDIA //' -e 's/^GeForce //' | tr -cd 'A-Za-z0-9 .-'
}
tune_build() {  # fills TUNE_ENV (variables) and TUNE_PRE (a prefix command) from the detected hardware
  local env="" short
  TUNE_ENV=""; TUNE_PRE=""
  case "$HW_PROFILE" in
    nvidia)
      env="__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
      if [ "$HW_HYBRID" = 1 ]; then
        env="__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only $env"
        short=$(tune_nv_short "${HW_GPU_NAME[$HW_BEST]}")
        [ -n "$short" ] && env="$env DXVK_FILTER_DEVICE_NAME=\"$short\""
      fi ;;
    mesa)
      env="MESA_SHADER_CACHE_MAX_SIZE=4G"
      [ "$HW_HYBRID" = 1 ] && env="DRI_PRIME=1 $env" ;;
  esac
  TUNE_ENV="WINEDLLOVERRIDES=\"winhttp=n,b\"${env:+ $env}"
  if [ "$HW_SANDBOX" = 0 ] && [ "$HW_PROFILE" != vm ] && have gamemoderun; then TUNE_PRE="gamemoderun "; fi
}
proton_state_any() {  # proton_state_any NAME...: installed if any of the names is
  local n
  for n in "$@"; do list_protons | grep -qxF "$n" && { t proton_ok "$n"; return 0; }; done
  t proton_missing "$1"
}
tune_script_path() { printf '%s/.msc-wizard/msc_launch.sh' "$GAME_DIR"; }
tune_game_opts() {  # the monolithic form: if the script is missing the game still starts
  printf '%s' "$TUNE_ENV bash -c 'S=\"$(tune_script_path)\"; if [ -x \"\$S\" ]; then exec \"\$S\" \"\$@\"; else exec \"\$@\"; fi' _ ${TUNE_PRE}%command%"
}
tune_launcher_opts() {  # writes the PID of the launcher into the flag file for the duration of its life
  printf '%s' "PROTON_USE_WINED3D=1 DOTNET_EnableWriteXorExecute=0 bash -c 'F=\"$GAME_DIR/.wmp_flag\"; echo \$\$ > \"\$F\"; trap \"rm -f \\\"\$F\\\"\" EXIT; \"\$@\"' _ %command%"
}

write_launch_script() {  # write_launch_script FILE : the switcher + launcher auto-close, game folder baked in
  local f="$1"
  mkdir -p "$(dirname "$f")" || return 1
  {
    printf '#!/usr/bin/env bash\n# Generated by msc-wizard %s. Safe to delete: the Launch Options fall back to starting the game as is.\n' "$VERSION"
    printf 'D=%q\n' "$GAME_DIR"
    cat <<'EOS'
FLAG="$D/.wmp_flag"
LOGDIR="$D/.msc-wizard"; LOG="$LOGDIR/msc.log"
CLOSE_AFTER="${MSC_CLOSE_AFTER:-5}"
log() { printf '%s %s\n' "$(date +%T)" "$*" >> "$LOG" 2>/dev/null; }
kids() { if command -v pgrep >/dev/null 2>&1; then pgrep -P "$1"; else ps -eo pid=,ppid= | awk -v p="$1" '$2==p{print $1}'; fi; }
kill_tree() { local c; for c in $(kids "$1"); do kill_tree "$c"; done; kill -TERM "$1" 2>/dev/null; }

# background helper: closes the WreckMP launcher a few seconds after the game started
if [ "${1:-}" = "__close" ]; then
  case "${2:-}" in ''|*[!0-9]*|0|1) exit 0 ;; esac      # never signal PID 0/1 (a process group / init)
  sleep "$CLOSE_AFTER"
  log "closing launcher, pid=$2"
  kill_tree "$2"
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -f '[W]reckMPLauncher\.exe|[U]pdater\.exe' 2>/dev/null
    sleep 3
    pkill -KILL -f '[W]reckMPLauncher\.exe|[U]pdater\.exe' 2>/dev/null
  fi
  log "launcher closed"
  exit 0
fi

mkdir -p "$LOGDIR" 2>/dev/null
log "start flag=$([ -f "$FLAG" ] && echo yes || echo no) env_wined3d=${PROTON_USE_WINED3D:-unset}"
unset PROTON_USE_WINED3D        # wined3d (OpenGL) is the usual cause of ~1 FPS; the game must use DXVK

if [ -f "$FLAG" ] && kill -0 "$(cat "$FLAG" 2>/dev/null)" 2>/dev/null; then
  # the WreckMP launcher is alive: multiplayer mode
  [ -f "$D/doorstop_config_wmp.bak" ] && cp "$D/doorstop_config_wmp.bak" "$D/doorstop_config.ini"
  export DOTNET_EnableWriteXorExecute=0
  LPID="$(cat "$FLAG")"
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup bash "$0" __close "$LPID" >/dev/null 2>&1 </dev/null &
  else
    nohup bash "$0" __close "$LPID" >/dev/null 2>&1 </dev/null &
  fi
  log "mode=wmp launcher_pid=$LPID"
else
  # normal start: MSCLoader only
  rm -f "$FLAG"
  [ -f "$D/doorstop_config_vanilla.ini" ] && cp "$D/doorstop_config_vanilla.ini" "$D/doorstop_config.ini"
  log "mode=vanilla"
fi

export WINEDLLOVERRIDES="winhttp=n,b"
exec "$@"
EOS
  } > "$f" && chmod +x "$f"
}

ds_target_re='^([[:space:]]*[Tt]arget[A-Za-z_]*[[:space:]]*=).*'
make_doorstop_variants() {  # creates doorstop_config_vanilla.ini / doorstop_config_wmp.bak if they are missing
  local ini="$GAME_DIR/doorstop_config.ini" van="$GAME_DIR/doorstop_config_vanilla.ini" wmp="$GAME_DIR/doorstop_config_wmp.bak"
  local line ml wp cr="" sep="/" v
  if [ -f "$van" ] && [ -f "$wmp" ]; then to tune_ds_have; return 0; fi
  if [ ! -f "$ini" ]; then tw tune_ds_noini; return 0; fi
  line=$(grep -m1 -E "$ds_target_re" "$ini") || { tw tune_ds_notarget; return 0; }
  case "$line" in *$'\r') cr=$'\r' ;; esac
  case "$line" in *\\*) sep='\' ;; esac
  ml=$(cd "$GAME_DIR" && find . -name 'MSCLoader.Preloader.dll' 2>/dev/null | head -n1); ml="${ml#./}"
  wp=$(cd "$GAME_DIR" && find . -name 'WreckMP.Preloader.dll' 2>/dev/null | head -n1); wp="${wp#./}"
  if [ -z "$ml" ] || [ -z "$wp" ]; then tw tune_ds_nodll "${ml:-MSCLoader.Preloader.dll: -}" "${wp:-WreckMP.Preloader.dll: -}"; return 0; fi
  if [ "$DRY" = 1 ]; then dry_note "$(t act_tune_ds)"; return 0; fi
  if [ ! -f "$van" ]; then
    v="${ml//\//$sep}"; v=$(printf '%s' "$v" | sed 's/[\\&|]/\\&/g')
    sed -E "s|$ds_target_re|\\1${v}${cr}|" "$ini" > "$van" && to tune_ds_made "$(basename "$van")"
  fi
  if [ ! -f "$wmp" ]; then
    v="${wp//\//$sep}"; v=$(printf '%s' "$v" | sed 's/[\\&|]/\\&/g')
    sed -E "s|$ds_target_re|\\1${v}${cr}|" "$ini" > "$wmp" && to tune_ds_made "$(basename "$wmp")"
  fi
  return 0
}

hw_report() {
  local i n=${#HW_GPU_VENDOR[@]}
  tn tune_hw_head
  tn tune_os "$(distro_name)" "$(detect_pm)"
  tn tune_cpu "${HW_CPU:-?}" "$HW_CORES"
  tn tune_ram "$((HW_RAM_MB / 1024))"
  tn tune_sess "$HW_SESSION"
  if [ "$n" -eq 0 ]; then tw tune_nogpu; fi
  for ((i=0; i<n; i++)); do
    tn tune_gpu "$i" "${HW_GPU_NAME[$i]}" "${HW_GPU_VENDOR[$i]}" "${HW_GPU_DRV[$i]}" "$([ "${HW_GPU_VRAM[$i]}" -gt 0 ] && echo "${HW_GPU_VRAM[$i]} MB" || echo '?')"
  done
  [ "$HW_DECK" = 1 ] && tn tune_deck
  if [ "$HW_SANDBOX" = 1 ]; then tn tune_sandbox; fi
  note "$(t "tune_prof_$HW_PROFILE")"
  if [ "$HW_HYBRID" = 1 ] && [ "$HW_BEST" -ge 0 ]; then tn tune_hybrid "${HW_GPU_NAME[$HW_BEST]}"; fi
  case "$HW_PROFILE" in vm|unknown) tw tune_soft ;; esac
  if [ "$HW_PROFILE" = mesa ]; then
    for ((i=0; i<n; i++)); do [ "${HW_GPU_VENDOR[$i]}" = nvidia ] && tw tune_nouveau; done
  fi
  [ "$HW_RAM_MB" -gt 0 ] && [ "$HW_RAM_MB" -lt 7000 ] && tw tune_lowram
  [ -z "$TUNE_PRE" ] && [ "$HW_SANDBOX" = 0 ] && [ "$HW_PROFILE" != vm ] && { tn tune_nogm; show "$(pm_hint gamemode)"; }
  return 0
}

steam_running() { ps -eo comm= 2>/dev/null | grep -qxE 'steam|steamwebhelper'; }
close_steam() {  # asks, then closes Steam and waits up to 30 s
  steam_running || return 0
  yesno "$(t lo_steam_on)" y || return 1
  tn lo_closing
  if have steam; then steam -shutdown >/dev/null 2>&1 & else pkill -TERM -x steam 2>/dev/null; fi
  local i; for i in $(seq 1 30); do steam_running || return 0; sleep 1; done
  return 1
}
apply_launch_options() {  # writes the tuned Launch Options into Steam (Steam must be closed); 0 = all done
  local r f res game_done=0 la_done=0 go lo
  go=$(tune_game_opts); lo=$(tune_launcher_opts)
  if [ "$DRY" = 1 ]; then dry_note "$(t lo_game_ok "localconfig.vdf")"; dry_note "$(t lo_la_ok "shortcuts.vdf")"; return 0; fi
  close_steam || { tw lo_steam_left; return 1; }
  [ "$GAME_SRC" = shortcut ] || detect_launcher_prefix >/dev/null 2>&1
  while IFS= read -r r; do
    for f in "$r"/userdata/*/config/localconfig.vdf; do
      [ -f "$f" ] && [ "$GAME_SRC" != shortcut ] || continue
      grep -q "\"$GAME_APPID\"" "$f" || continue
      cp -a "$f" "$f.wizard-bak"
      res=$(vdf setlaunch "$f" "$GAME_APPID" "$go")
      [ "$res" = ok ] && { to lo_game_ok "$f"; game_done=1; }
    done
    for f in "$r"/userdata/*/config/shortcuts.vdf; do
      [ -f "$f" ] || continue
      if [ "$GAME_SRC" = shortcut ] && [ -n "$G_APPID" ]; then
        cp -a "$f" "$f.wizard-bak"
        res=$(vdf setshortcut "$f" "$G_APPID" "$go"); [ "$res" = ok ] && { to lo_game_ok "$f"; game_done=1; }
      fi
      if [ -n "$L_APPID" ]; then
        [ -f "$f.wizard-bak" ] || cp -a "$f" "$f.wizard-bak"
        res=$(vdf setshortcut "$f" "$L_APPID" "$lo"); [ "$res" = ok ] && { to lo_la_ok "$f"; la_done=1; }
      fi
    done
  done < <(steam_roots)
  [ "$la_done" = 1 ] || tn lo_la_none
  [ "$game_done" = 1 ] && [ "$la_done" = 1 ]
}

step_tune() {
  ts st_tune
  case "$GAME_DIR" in *\'*|*\"*|*\$*|*\`*|*\\*) td tune_badpath "$GAME_DIR" ;; esac
  hw_detect; hw_report; tune_build
  local sp; sp=$(tune_script_path)
  echo
  if [ "$GAME_SRC" = wine ]; then
    tn tune_wine_1; show_copy "$TUNE_ENV"
    tn tune_wine_2
    return 0
  fi
  local write=1
  if [ "$DRY" != 1 ]; then
    tn tune_confirm_1 "$sp"
    if ! yesno "$(t tune_confirm_q)" y; then write=0; tn tune_skipped; fi
  fi
  if [ "$write" = 1 ]; then
    act "$(t act_tune_script "$sp")" write_launch_script "$sp"
    make_doorstop_variants
  fi
  if [ "$DRY" != 1 ] && [ "$write" = 1 ]; then
    { printf 'game:     %s\nlauncher: %s\n' "$(tune_game_opts)" "$(tune_launcher_opts)"; } > "$GAME_DIR/.msc-wizard/launch-options.txt" 2>/dev/null
  fi
  if [ "$write" = 1 ] && { [ "$DRY" = 1 ] || yesno "$(t lo_q)" y; }; then
    apply_launch_options && tn lo_manual
  fi
  echo
  local e; e=$(wmp_entry_guess)
  echo
  note "$(t tune_a "$GAME_NAME")"
  tn tune_proton "$PROTON_GAME"; note "  $(proton_state_any "Proton 9.0 (Beta)" "Proton 9.0")"
  tn tune_game_head "$GAME_NAME"; show_copy "$(tune_game_opts)"
  tn tune_ns_note
  tn ch_target; show "\"$GAME_DIR/mysummercar.exe\""
  tn ch_start;  show "\"$GAME_DIR/\""
  echo
  note "$(t tune_b)"
  tn ch_b_file; show "$e"
  wmp_real || tn ch_b_guess
  tn ch_target; show "\"$e\""
  tn ch_start;  show "\"$(dirname "$e")/\""
  tn tune_proton "$PROTON_LAUNCHER"; note "  $(proton_state "$PROTON_LAUNCHER")"
  tn tune_launcher_head; show_copy "$(tune_launcher_opts)"
  tn tune_install_proton "$PROTON_INSTALL"
  tn tune_steps
  tn tune_old
  tn tune_verify
  show "bash $SELF --gpu-check"
  tn tune_unverified
}
flow_tune() { step_tune; }

gpu_check() {  # inspects the RUNNING game: which renderer and which GPU it really uses (read only)
  ts st_gcheck
  local pid env nv
  pid=$(ps -eo pid=,args= 2>/dev/null | grep -iE '[m]ysummercar\.exe' | awk '{print $1}' | tail -n1)
  if [ -z "$pid" ]; then tw gc_nogame; return 0; fi
  tn gc_pid "$pid"
  if [ -r "/proc/$pid/environ" ]; then
    env=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
    tn gc_env
    printf '%s\n' "$env" | grep -E '^(PROTON_USE_WINED3D|__NV_PRIME_RENDER_OFFLOAD|__GLX_VENDOR_LIBRARY_NAME|__VK_LAYER_NV_optimus|DXVK_FILTER_DEVICE_NAME|DRI_PRIME|DOTNET_EnableWriteXorExecute|MESA_SHADER_CACHE_MAX_SIZE)=' | sed 's/^/      /'
    printf '%s\n' "$env" | grep -q '^PROTON_USE_WINED3D=1' && tw gc_wined3d
  else
    tw gc_noenv
  fi
  if [ -r "/proc/$pid/maps" ]; then
    if grep -qi 'dxvk' "/proc/$pid/maps" 2>/dev/null; then to gc_dxvk; fi
    if grep -qi 'wined3d' "/proc/$pid/maps" 2>/dev/null; then tw gc_wined3d_lib; fi
    if grep -qi 'libvulkan_lvp' "/proc/$pid/maps" 2>/dev/null; then tn gc_lvp; fi
  fi
  if have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
    nv=$(nvidia-smi 2>/dev/null | grep -i 'mysummercar')
    if [ -n "$nv" ]; then to gc_nv_yes; else tw gc_nv_no; fi
  fi
  return 0
}

# ================================================================== flows
flow_mscl()   { need_runner || return 1; step_game_settings; step_mscl; recap 1; }
flow_wreckmp_core() {   # WreckMP steps (the game settings step is done by the caller)
  step_wmp
  step_dotnet "$GAME_APPID" game
  if [ "$GAME_SRC" = wine ]; then
    step_launcher_wine; LA="$GAME_APPID"          # the launcher shares the game prefix
  else
    step_updater_in_game_prefix
    step_shortcut
    step_launcher_first_start
    step_dotnet "$LA" launcher
  fi
  step_reg
  step_launcher_test
  [ "$GAME_SRC" = wine ] || step_guid
  if [ "$GAME_SRC" != wine ]; then
    echo
    if [ "$DRY" = 1 ] || yesno "$(t ac_q)" y; then step_tune; fi
  fi
}
flow_wmp_only() { need_runner || return 1; step_game_settings; flow_wreckmp_core; recap 2; }
flow_all()      { need_runner || return 1; step_game_settings; step_mscl; flow_wreckmp_core; recap 3; }
flow_fixreg() {
  ts st_regfix
  if [ "$GAME_SRC" = wine ]; then
    [ -n "$GAME_PFX" ] && LA="$GAME_APPID" && step_reg
    return 0
  fi
  fix_wmp_registry
}
flow_fixguid() {
  if [ "$GAME_SRC" = wine ]; then tn guid_wine; return 0; fi
  [ "$GAME_SRC" = shortcut ] && adopt_game_shortcut
  ts st_regfix; fix_wmp_registry
  if ! detect_launcher_prefix; then
    if [ "$DRY" = 1 ]; then LA=0000000000; else td no_la; fi
  fi
  step_guid
}

# Actions run in a subshell, so that die() (exit) returns to the menu instead of ending the
# wizard. The few variables that must survive are saved to a file and loaded back.
save_state() {
  local v
  for v in GAME_DIR LIB COMPAT LA L_APPID L_NAME L_EXE L_START L_OPTS DOTNET_EXE PV_ASKED \
           SRC_KIND GAME_SRC GAME_PFX GAME_APPID WINE_BIN WINESERVER_BIN G_APPID G_EXE G_START G_OPTS \
           SIM_MSCL SIM_WMP SIM_DOTNET_GAME SIM_DOTNET_LA SIM_REG SIM_GUID SIM_HOSTS; do
    printf '%s=%q\n' "$v" "${!v-}"
  done > "$1"
  if [ -n "${PROTON_VERSION:-}" ]; then printf 'export PROTON_VERSION=%q\n' "$PROTON_VERSION" >> "$1"; fi
  if [ "${#DRY_LOG[@]}" -gt 0 ]; then { printf 'DRY_LOG=('; printf '%q ' "${DRY_LOG[@]}"; printf ')\n'; } >> "$1"; fi
}
run_action() {
  local sf rc; sf=$(mktemp "${TMPDIR:-/tmp}/msc-wizard-state.XXXXXX") || return 1
  ( trap 'save_state "$sf"' EXIT; "$@" )
  rc=$?
  # shellcheck disable=SC1090
  [ -s "$sf" ] && . "$sf"
  rm -f "$sf"
  return $rc
}
act_run() {  # act_run FLOW: ensure the game folder, run, show the dry-run summary / the warning
  need_game_dir || return 1
  run_action "$@"; local rc=$?
  if [ "$DRY" = 1 ]; then dry_summary; DRY_LOG=(); sim_reset; fi
  if [ $rc -eq 0 ]; then case "$1" in flow_wmp_only|flow_all) [ "$GAME_SRC" = wine ] || caps_warning ;; esac; fi
  return $rc
}

# ================================================================== docs
render_doc() {
  sed -e "s|@VERSION@|$VERSION|g" -e "s|@MSCL@|$MSCL_VERSION|g" \
      -e "s|@GAME_OPTS@|$GAME_OPTS|g" -e "s|@LAUNCHER_OPTS@|$LAUNCHER_OPTS|g" \
      -e "s|@PROTON_GAME@|$PROTON_GAME|g" -e "s|@PROTON_LAUNCHER@|$PROTON_LAUNCHER|g" \
      -e "s|@PROTON_INSTALL@|$PROTON_INSTALL|g" -e "s|@WORK@|$WORK|g" \
      -e "s|@LINK_WRECKMP@|$LINK_WRECKMP|g" -e "s|@APPID@|$STEAM_APPID|g" -e "s|@WINE_OPTS@|$WINE_OPTS|g" \
      -e "s|@DIALOG@|$LAUNCHER_DIALOG|g" -e "s|@SELF@|$SELF|g"
}
pager() { if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && have less; then less -R; else cat; fi; }
print_help()   { "doc_help_$UI"   | render_doc; }
print_readme() { "doc_readme_$UI" | render_doc | pager; }

doc_help_en() { cat <<'EOF'
msc-wizard.sh @VERSION@: MSCLoader and WreckMP installer wizard for My Summer Car (Linux, Steam + Proton)

Usage:  bash @SELF@ [option]

  (no option)      interactive: language -> run type (real / dry run) -> menu
  --dry-run        rehearsal: same questions, shows every path and command, changes NOTHING
  --status         show the state and check the setup (changes nothing)
  --steam-info     Steam cheat sheet: Proton versions, launch options, shortcut paths,
                   compared with what Steam currently has
  --tune           detect this PC's GPU/CPU/RAM and print Steam Launch Options that fit it
                   (right GPU on hybrid laptops, mode switch, launcher auto-close after 5 s)
  --gpu-check      while the game runs: shows which renderer (DXVK / wined3d) and GPU it really uses
  --fix-guid       repair after a Proton/Steam update or moving the game: launcher registry + MachineGuid
  --fix-reg        only fix the launcher's "register/registry not found" (game path in its registry)
  --nonsteam       the game is NOT from Steam (the wizard finds it by itself and asks how you launch it:
                   a Steam shortcut or plain Wine / Lutris / Bottles / Heroic); --steam = Steam copy
  --game-dir PATH  game folder (otherwise found automatically)
  --prefix PATH    Wine prefix of a non-Steam copy (otherwise found automatically)
  --wine PATH      wine binary to use (env MSC_WINE); otherwise system wine, then Lutris/Bottles/Proton builds
  --lang uk|en     interface language (skips the question); also env MSC_WIZARD_LANG=uk|en
  --readme         full manual: what it does, what it touches, what is NOT verified,
                   troubleshooting, how to undo
  -h, --help       this help
  -V, --version    print the version

Typical first run:
  bash @SELF@ --dry-run     # look at everything first
  bash @SELF@               # the real thing

Something went wrong?  Read "WHAT IS NOT VERIFIED" in:  bash @SELF@ --readme
EOF
}
doc_help_uk() { cat <<'EOF'
msc-wizard.sh @VERSION@: майстер встановлення MSCLoader і WreckMP для My Summer Car (Linux, Steam + Proton)

Використання:  bash @SELF@ [параметр]

  (без параметра)  інтерактивно: мова -> режим запуску (справжній / пробний) -> меню
  --dry-run        пробний запуск: ті самі запитання, показує всі шляхи й команди, НІЧОГО не змінює
  --status         показати стан і перевірити налаштування (нічого не змінює)
  --steam-info     шпаргалка Steam: версії Proton, параметри запуску, шляхи для ярлика,
                   порівняно з тим, що зараз стоїть у Steam
  --tune           визначити GPU/CPU/RAM цього ПК і дати параметри запуску Steam, що йому підходять
                   (потрібна відеокарта на гібридних ноутбуках, перемикач режимів, автозакриття лаунчера за 5 с)
  --gpu-check      поки гра працює: який рендерер (DXVK / wined3d) і яка відеокарта справді використовуються
  --fix-guid       полагодити після оновлення Proton/Steam чи переносу гри: реєстр лаунчера + MachineGuid
  --fix-reg        лише виправити «register/registry not found» у лаунчері (шлях до гри в його реєстрі)
  --nonsteam       гра НЕ зі Steam (майстер сам її знаходить і питає, як ти запускаєш:
                   ярлик у Steam або Wine / Lutris / Bottles / Heroic); --steam = копія зі Steam
  --game-dir ШЛЯХ  папка гри (інакше знаходиться автоматично)
  --prefix ШЛЯХ    Wine-prefix копії не зі Steam (інакше знаходиться автоматично)
  --wine ШЛЯХ      який wine використати (змінна MSC_WINE); інакше системний, потім збірки Lutris/Bottles/Proton
  --lang uk|en     мова інтерфейсу (пропускає питання); також змінна MSC_WIZARD_LANG=uk|en
  --readme         повний посібник: що робить, що чіпає, що НЕ ПЕРЕВІРЕНО,
                   усунення проблем, як відкотити
  -h, --help       ця довідка
  -V, --version    показати версію

Типовий перший запуск:
  bash @SELF@ --dry-run     # спочатку подивитись усе
  bash @SELF@               # справжній запуск

Щось пішло не так?  Прочитай "ЩО НЕ ПЕРЕВІРЕНО" у:  bash @SELF@ --readme
EOF
}

doc_readme_en() { cat <<'EOF'
msc-wizard.sh @VERSION@  -  MANUAL

WHAT IT DOES
  Walks you step by step through installing MSCLoader (the mod loader) and/or the WreckMP
  multiplayer for My Summer Car on Linux (Steam + Proton). It automates what can be automated
  (downloading MSCLoader and .NET 6, running the installers inside the right Proton prefix,
  a registry import, MachineGuid alignment) and tells you exactly what to type into Steam for
  the parts that scripts cannot set (Proton version, launch options, the non-Steam shortcut).
  Every step first checks whether it is already done, so you can stop with Ctrl+C and run it
  again. The interface is available in Ukrainian and English.

REQUIREMENTS
  bash 4.4+, Steam with My Summer Car installed (native, Flatpak or Snap Steam), protontricks
  (native or Flatpak), python3 (reads Steam's settings), curl or wget, unzip (or bsdtar/python3).
  WreckMP is downloaded by you from Nexus Mods (free account); the script cannot do that.

HOW TO USE
  bash @SELF@ --dry-run   rehearsal: shows every question, path and command, changes nothing
  bash @SELF@             the real thing: language -> run type -> menu
  In the menu you can change language, run type and game folder at any time (item 7).

MENU
  1  MSCLoader only          mods without multiplayer
  2  WreckMP only            MSCLoader must already be installed
  3  Everything              MSCLoader + WreckMP
  4  Status and checks       what is done, what is not, what Steam has saved
  5  Steam cheat sheet       Proton versions, launch options and paths to type into Steam
  6  Align MachineGuid       after a Proton/Steam update
  7  Settings                language, run type, game folder
  8  Help / README           this text
  9  Tune for this PC        hardware detection -> Launch Options for exactly this computer

TUNE FOR THIS PC  (item 9 / --tune, then --gpu-check)
  Reads the hardware only from /sys, /proc and, when present, lspci / nvidia-smi, so it needs no
  root and works on any distribution. It builds the Launch Options for THIS computer:
    NVIDIA + Intel/AMD laptop   __NV_PRIME_RENDER_OFFLOAD, __GLX_VENDOR_LIBRARY_NAME, __VK_LAYER_NV_optimus
                                and DXVK_FILTER_DEVICE_NAME with the card's short name
    AMD/Intel/nouveau + 2nd GPU DRI_PRIME=1 (Mesa picks the other GPU)
    single GPU / Steam Deck     no GPU variables; only shader-cache settings
    gamemoderun                 added if installed (not for Flatpak/Snap Steam)
  It also writes <game folder>/.msc-wizard/msc_launch.sh (switches doorstop between MSCLoader and
  WreckMP, unsets PROTON_USE_WINED3D for the game, closes the WreckMP launcher MSC_CLOSE_AFTER=5 s
  after the game starts) and, if missing, doorstop_config_vanilla.ini / doorstop_config_wmp.bak.
  The Launch Options are "monolithic": if the script is deleted, the game still starts.
  It also prints the Proton version to force for the game and for the launcher, and the Target /
  Start In values for both. Before writing anything it asks for confirmation.
  Variables are chosen conservatively for the hardware class; no FPS gain was measured.

STEAM SETTINGS (values from the author's working setup)
  Game "My Summer Car":
    Compatibility -> force      @PROTON_GAME@
    Launch Options              @GAME_OPTS@
  WreckMP launcher (add as a Non-Steam game):
    Target                      "<game folder>/WreckMP/Updater.exe"   (with the quotes)
    Start In                    "<game folder>/WreckMP/"              (with the quotes)
    Launch Options              @LAUNCHER_OPTS@
    Compatibility -> force      @PROTON_LAUNCHER@
  Installers (run through protontricks): @PROTON_INSTALL@
  "bash @SELF@ --steam-info" prints these with the real paths for your system and marks
  which ones already match what Steam has saved.

COPY OF THE GAME THAT IS NOT FROM STEAM
  The wizard asks which copy you have (Steam / not Steam). For a non-Steam copy it searches by itself:
  Steam non-Steam shortcuts, Lutris configs, Wine/Lutris/Bottles/Heroic folders, ~/Games, ~/Downloads,
  /opt, /mnt, /media. You confirm the path with Enter. Then there are two ways:
    1) Steam shortcut: the game is added to Steam as a "non-Steam game" (the wizard shows how); everything
       works like the Steam copy, with the Launch Options field of that shortcut (@GAME_OPTS@).
    2) Wine / Lutris / Bottles / Heroic / command line: the Wine prefix is found automatically (it is
       the folder with system.reg above the game, or a prefix found in the usual places). There are no
       Steam launch options, so the wizard gives the ARGUMENT (@WINE_OPTS@) and a ready
       command with your paths filled in, and can create start-msc.sh / start-wreckmp.sh in the game
       folder. The WreckMP launcher shares the prefix with the game, so MachineGuid needs no fixing.
       wine is taken from the system, or from Lutris/Bottles/Proton builds found on disk (--wine PATH).

SUPPORTED DISTRIBUTIONS
  Package hints for every missing tool (protontricks, wine, python3, curl, unzip) are given for: Arch
  family (Manjaro, CachyOS, EndeavourOS), Debian/Ubuntu family (Mint, Pop!_OS), Fedora/RHEL family,
  openSUSE, Void, Gentoo, Alpine, Solus, NixOS, and immutable systems (SteamOS/Steam Deck, Bazzite,
  Silverblue, Kinoite: Flatpak or distrobox). Steam is looked up in the native, Flatpak and Snap
  locations. Root commands use sudo, doas or pkexec. Alpine needs bash installed first.

WHAT THE SCRIPT TOUCHES
  - the game folder: only through the official installers (MSCLoader, WreckMP)
  - the Proton prefixes of the game and of the launcher: installers, .NET 6, one registry import
  - system.reg of the game prefix (MachineGuid): a backup system.reg.bak.<time> is made first
  - /etc/hosts: only if you answer yes; two patreon.com lines, via sudo
  - @WORK@: downloads and temporary files
  It only READS Steam's own files (shortcuts.vdf, localconfig.vdf, config.vdf) and never edits
  them. It never deletes your files (it asks before closing running game/Wine processes).

WHAT IS NOT VERIFIED  (where a mistake is most likely)
  Tested: bash syntax, the dry run, and full runs on a SIMULATED Steam tree with stub
  protontricks. Also checked on the real file (2026-11-15): the MSCLoader v@MSCL@ download URL works
  and the archive contains MSCLInstaller.exe. NOT tested: real Steam/Proton, the real game,
  WreckMP, Nexus Mods, the .NET download.
  Everything below comes from one author's working setup:
  1. Proton versions (@PROTON_GAME@ game, @PROTON_LAUNCHER@ launcher, @PROTON_INSTALL@ installers)
     are what the author used; other versions may or may not work.
  2. Running Updater.exe once in the game prefix through protontricks: not verified to be required,
     and it can fail; it is therefore OFF by default. The launcher runs fine from its Steam shortcut.
  3. Each variable in the launcher's Launch Options: not verified one by one.
  4. The registry import into the launcher prefix: not verified to be required.
  5. Multiplayer WITHOUT the launcher open: not verified (see the warning at the end).
  6. Choosing Proton for the installers relies on protontricks' PROTON_VERSION variable.
  7. The launcher prefix is found from shortcuts.vdf (the shortcut's appid = prefix folder
     name). If that fails the wizard asks you for the number.
  8. Steam writes shortcuts.vdf/localconfig.vdf/config.vdf on its own schedule (usually on
     exit), so "[ ]" next to a Steam setting may be stale: close Steam and run --status again.
  9. Flatpak protontricks may not see ~/.cache or ~/Downloads. If an installer file is not
     found:  flatpak override --user --filesystem=home com.github.Matoking.protontricks
 10. The .NET 6 download link (aka.ms) is Microsoft's official one, but .NET 6 is out of
     support; if the link stops working the wizard shows the page for a manual download.
 11. Non-Steam copy, Wine mode: NOT tested on a real system. The launcher sharing the game prefix,
     wine from Lutris/Bottles/Proton builds, and Flatpak Bottles prefixes (a host wine may not
     match the sandbox) are assumptions.
 12. Non-Steam copy, Steam shortcut: the shortcut is matched by the exe path of mysummercar.exe in
     shortcuts.vdf; the game's Proton prefix is compatdata/<appid>.
 13. Package names in the distribution hints can differ between releases.

TROUBLESHOOTING
  About 1 FPS in the menu, other GPU programs lag too (usually only in multiplayer mode)
      Run  bash @SELF@ --gpu-check  while the game runs. PROTON_USE_WINED3D=1 in the game, or no
      nvidia-smi entry on a hybrid laptop, is the cause; item 9 sets this up correctly.
  Launcher crashes at start (c0000005 in wininet after the Patreon cookie)
      Block patreon.com in /etc/hosts: the wizard offers it. Undo:
      sudo sed -i '/patreon\.com/d' /etc/hosts
  The launcher shows dots forever, after 5 minutes "@DIALOG@"
      Expected (it cannot see the game: another prefix). Press OK; the game is unaffected.
  Multiplayer broke after a Proton/Steam update:   bash @SELF@ --fix-guid
  "mysummercar.exe not found"
      The game must be in <library>/steamapps/common/My Summer Car of a Steam library.
  Leftovers of the native Linux MSCLoader (mysummercar.x86_64, run.sh, libdoorstop.so):
      Delete them and use "Verify integrity of game files" in Steam.
  Logs: <game folder>/WreckMP/startup_debug.log and conn.log; output_log.txt of the game.
  Reporting a bug: attach the output of  bash @SELF@ --status  and of  --dry-run.

HOW TO UNDO
  hosts line:      sudo sed -i '/patreon\.com/d' /etc/hosts
  MachineGuid:     with Steam, the game and the launcher closed, copy
                   <library>/steamapps/compatdata/@APPID@/pfx/system.reg.bak.<time> back over system.reg
  MSCLoader/WreckMP: delete what they added to the game folder (winhttp.dll,
                   doorstop_config.ini, mysummercar_Data/Managed/MSCLoader.dll, the WreckMP folder)
  Steam entries:   remove the non-Steam shortcut and clear the Launch Options
  Wizard cache:    rm -rf @WORK@
EOF
}
doc_readme_uk() { cat <<'EOF'
msc-wizard.sh @VERSION@  -  ПОСІБНИК

ЩО ВІН РОБИТЬ
  Крок за кроком веде через встановлення MSCLoader (завантажувач модів) та/або мультиплеєра
  WreckMP для My Summer Car на Linux (Steam + Proton). Автоматизує те, що можна (завантаження
  MSCLoader і .NET 6, запуск інсталяторів у правильному Proton-prefix, імпорт у реєстр,
  вирівнювання MachineGuid) і точно каже, що вписати в Steam там, де скрипт не може
  (версія Proton, параметри запуску, ярлик сторонньої гри). Кожен крок спершу перевіряє,
  чи він уже зроблений, тож можна зупинитись Ctrl+C і запустити знову.
  Інтерфейс українською та англійською.

ВИМОГИ
  bash 4.4+, Steam із встановленою My Summer Car (нативний, Flatpak або Snap), protontricks
  (нативний або Flatpak), python3 (читає налаштування Steam), curl або wget, unzip (або
  bsdtar/python3). WreckMP ти скачуєш сам з Nexus Mods (безкоштовний акаунт): скрипт цього не вміє.

ЯК КОРИСТУВАТИСЬ
  bash @SELF@ --dry-run   пробний запуск: показує всі запитання, шляхи й команди, нічого не змінює
  bash @SELF@             справжній запуск: мова -> режим запуску -> меню
  У меню мову, режим запуску і папку гри можна змінити будь-коли (пункт 7).

МЕНЮ
  1  Тільки MSCLoader        моди без мультиплеєра
  2  Тільки WreckMP          MSCLoader уже має стояти
  3  Усе                     MSCLoader + WreckMP
  4  Стан і перевірка        що зроблено, що ні, що збережено в Steam
  5  Шпаргалка Steam         версії Proton, параметри запуску й шляхи, які вписати в Steam
  6  Вирівняти MachineGuid   після оновлення Proton/Steam
  7  Налаштування            мова, режим запуску, папка гри
  8  Довідка / README        цей текст
  9  Оптимізація під ПК      визначення заліза -> параметри запуску саме для цього комп’ютера

ОПТИМІЗАЦІЯ ПІД ЦЕЙ ПК  (пункт 9 / --tune, потім --gpu-check)
  Читає залізо лише з /sys, /proc та (якщо є) lspci / nvidia-smi, тож не потребує root і працює на
  будь-якому дистрибутиві. Складає параметри запуску для САМЕ цього комп’ютера:
    ноутбук NVIDIA + Intel/AMD   __NV_PRIME_RENDER_OFFLOAD, __GLX_VENDOR_LIBRARY_NAME, __VK_LAYER_NV_optimus
                                 і DXVK_FILTER_DEVICE_NAME з коротким іменем карти
    AMD/Intel/nouveau + 2-й GPU  DRI_PRIME=1 (Mesa бере інший GPU)
    один GPU / Steam Deck        без змінних GPU; лише налаштування кешу шейдерів
    gamemoderun                  додається, якщо встановлений (не для Flatpak/Snap Steam)
  Також пише <папка гри>/.msc-wizard/msc_launch.sh (перемикає doorstop між MSCLoader і WreckMP,
  знімає PROTON_USE_WINED3D для гри, закриває лаунчер WreckMP через MSC_CLOSE_AFTER=5 с після
  старту гри) і, якщо їх немає, doorstop_config_vanilla.ini / doorstop_config_wmp.bak.
  Параметри "монолітні": якщо скрипт видалити, гра все одно запуститься.
  Також друкує версію Proton для гри й для лаунчера та значення Ціль / Почати в для обох.
  Перед записом файлів питає підтвердження.
  Змінні підібрані консервативно під клас заліза; приріст FPS не вимірювався.

НАЛАШТУВАННЯ STEAM (значення з робочої конфігурації автора)
  Гра "My Summer Car":
    Сумісність -> примусово     @PROTON_GAME@
    Параметри запуску           @GAME_OPTS@
  Лаунчер WreckMP (додати як стороннюю гру):
    Ціль (Target)               "<папка гри>/WreckMP/Updater.exe"   (з лапками)
    Почати в (Start In)         "<папка гри>/WreckMP/"              (з лапками)
    Параметри запуску           @LAUNCHER_OPTS@
    Сумісність -> примусово     @PROTON_LAUNCHER@
  Інсталятори (запускаються через protontricks): @PROTON_INSTALL@
  "bash @SELF@ --steam-info" друкує це зі справжніми шляхами для твоєї системи й
  позначає, що вже збігається з тим, що збережено в Steam.

КОПІЯ ГРИ НЕ ЗІ STEAM
  Майстер питає, яка в тебе копія (Steam / не Steam). Для копії не зі Steam він шукає сам: сторонні
  ярлики Steam, конфіги Lutris, теки Wine/Lutris/Bottles/Heroic, ~/Games, ~/Downloads, /opt, /mnt,
  /media. Шлях підтверджуєш Enter-ом. Далі є два шляхи:
    1) Ярлик у Steam: гра додається в Steam як "стороння" (майстер показує як); усе працює як для
       копії зі Steam, параметри запуску пишуться в цей ярлик (@GAME_OPTS@).
    2) Wine / Lutris / Bottles / Heroic / командний рядок: Wine-prefix знаходиться автоматично (це тека
       з system.reg над грою або prefix у типових місцях). Параметрів запуску Steam немає, тому майстер
       дає АРГУМЕНТ (@WINE_OPTS@) і готову команду з підставленими шляхами, а також може створити
       start-msc.sh / start-wreckmp.sh у теці гри. Лаунчер WreckMP ділить prefix з грою, тож
       MachineGuid виправляти не треба. wine береться системний або зі збірок Lutris/Bottles/Proton
       на диску (--wine ШЛЯХ).

ПІДТРИМУВАНІ ДИСТРИБУТИВИ
  Підказки з установки для кожного відсутнього інструмента (protontricks, wine, python3, curl, unzip):
  родина Arch (Manjaro, CachyOS, EndeavourOS), Debian/Ubuntu (Mint, Pop!_OS), Fedora/RHEL, openSUSE,
  Void, Gentoo, Alpine, Solus, NixOS та незмінні системи (SteamOS/Steam Deck, Bazzite, Silverblue,
  Kinoite: Flatpak або distrobox). Steam шукається в нативних, Flatpak і Snap місцях. Команди від
  root: sudo, doas або pkexec. Для Alpine спершу встанови bash.

ЩО ЧІПАЄ СКРИПТ
  - папку гри: лише через офіційні інсталятори (MSCLoader, WreckMP)
  - Proton-prefix-и гри й лаунчера: інсталятори, .NET 6, один імпорт у реєстр
  - system.reg prefix-а гри (MachineGuid): спершу робиться копія system.reg.bak.<час>
  - /etc/hosts: лише якщо ти погодишся; два рядки patreon.com, через sudo
  - @WORK@: завантаження й тимчасові файли
  Файли самого Steam (shortcuts.vdf, localconfig.vdf, config.vdf) він лише ЧИТАЄ і ніколи не
  редагує. Твої файли не видаляє (запущені процеси гри/Wine закриває лише з твого дозволу).

ЩО НЕ ПЕРЕВІРЕНО  (де найімовірніша помилка)
  Перевірено: синтаксис bash, пробний запуск і повні запуски на ІМІТОВАНОМУ дереві Steam із
  заглушками protontricks. Також перевірено на справжньому файлі (2026-11-15): посилання на
  MSCLoader v@MSCL@ працює, в архіві є MSCLInstaller.exe. НЕ перевірено: справжні Steam/Proton,
  справжню гру, WreckMP, Nexus, завантаження .NET.
  Усе нижче взято з робочої конфігурації одного автора:
  1. Версії Proton (@PROTON_GAME@ гра, @PROTON_LAUNCHER@ лаунчер, @PROTON_INSTALL@ інсталятори) :
     так було в автора; інші версії можуть працювати, а можуть і ні.
  2. Одноразовий запуск Updater.exe в prefix гри через protontricks: не перевірено, чи обов’язковий,
     і він може завершитись помилкою; тому за замовчуванням ВИМКНЕНО. Лаунчер нормально працює з ярлика Steam.
  3. Кожна змінна в параметрах запуску лаунчера: окремо не перевірялась.
  4. Імпорт у реєстр prefix-а лаунчера: не перевірено, чи обов’язковий.
  5. Мультиплеєр БЕЗ відкритого лаунчера: не перевірено (див. попередження в кінці).
  6. Вибір Proton для інсталяторів спирається на змінну PROTON_VERSION у protontricks.
  7. Prefix лаунчера знаходиться за shortcuts.vdf (appid ярлика = назва теки prefix-а).
     Якщо не вдалось, майстер попросить номер.
  8. Steam записує shortcuts.vdf/localconfig.vdf/config.vdf коли йому вигідно (зазвичай при
     виході), тому "[ ]" біля налаштування Steam може бути застарілим: закрий Steam і
     запусти --status знову.
  9. Flatpak-protontricks може не бачити ~/.cache чи ~/Downloads. Якщо файл інсталятора не
     знайдено:  flatpak override --user --filesystem=home com.github.Matoking.protontricks
 10. Посилання на .NET 6 (aka.ms) офіційне, але .NET 6 уже без підтримки Microsoft; якщо
     посилання перестане працювати, майстер покаже сторінку для ручного завантаження.
 11. Копія не зі Steam, Wine-режим: НЕ перевірено на справжній системі. Спільний prefix лаунчера й
     гри, wine зі збірок Lutris/Bottles/Proton і prefix-и Flatpak-Bottles (системний wine може не
     збігатися з пісочницею) це припущення.
 12. Копія не зі Steam, ярлик у Steam: ярлик знаходиться за шляхом mysummercar.exe у shortcuts.vdf;
     Proton-prefix гри це compatdata/<appid>.
 13. Назви пакетів у підказках можуть відрізнятися між випусками дистрибутивів.

УСУНЕННЯ ПРОБЛЕМ
  ~1 FPS у меню, лагають й інші програми з GPU (зазвичай лише в режимі мультиплеєра)
      Виконай  bash @SELF@ --gpu-check  поки гра працює. PROTON_USE_WINED3D=1 у грі або відсутність
      запису в nvidia-smi на гібридному ноутбуці це причина; пункт 9 налаштовує це правильно.
  Лаунчер вилітає на старті (c0000005 у wininet після Patreon cookie)
      Заблокуй patreon.com в /etc/hosts: майстер пропонує це сам. Скасувати:
      sudo sed -i '/patreon\.com/d' /etc/hosts
  Лаунчер показує крапки, через 5 хвилин "@DIALOG@"
      Очікувано (він не бачить гру: інший prefix). Натисни OK; гра не страждає.
  Мультиплеєр зламався після оновлення Proton/Steam:   bash @SELF@ --fix-guid
  "mysummercar.exe не знайдено"
      Гра має лежати в <бібліотека>/steamapps/common/My Summer Car бібліотеки Steam.
  Залишки нативного Linux-MSCLoader (mysummercar.x86_64, run.sh, libdoorstop.so):
      Видали їх і зроби "Перевірити цілісність файлів" у Steam.
  Логи: <папка гри>/WreckMP/startup_debug.log і conn.log; output_log.txt гри.
  Повідомляючи про помилку, додай вивід  bash @SELF@ --status  і  --dry-run.

ЯК ВІДКОТИТИ
  рядок у hosts:   sudo sed -i '/patreon\.com/d' /etc/hosts
  MachineGuid:     при закритих Steam, грі й лаунчері скопіюй
                   <бібліотека>/steamapps/compatdata/@APPID@/pfx/system.reg.bak.<час> поверх system.reg
  MSCLoader/WreckMP: видали те, що вони додали в папку гри (winhttp.dll,
                   doorstop_config.ini, mysummercar_Data/Managed/MSCLoader.dll, теку WreckMP)
  Записи Steam:    прибери ярлик сторонньої гри й очисти параметри запуску
  Кеш майстра:     rm -rf @WORK@
EOF
}

# ================================================================== interactive
choose_language() {
  local c def=1
  [ "$(detect_locale)" = en ] && def=2
  echo
  echo "  Мова / Language:"
  echo "    1) Українська"
  echo "    2) English"
  read -r -p "  [$def]: " c || bye
  c="${c:-$def}"
  set_lang "$c" || set_lang "$def"
}
set_dry_mode() {
  DRY=1
  echo
  tn dry_b1
  tn dry_b2; tn dry_b3; tn dry_b4
  if yesno "$(t dry_demo_q)" y; then DEMO=1; else DEMO=0; fi
  sim_reset; DRY_LOG=()
}
choose_run_type() {
  local c
  echo
  tn runtype_head
  note "  $(t runtype_1)"; note "  $(t runtype_2)"
  read -r -p "  $(t choice_prompt 1)" c || bye
  case "${c:-1}" in
    2|d|D|dry|dry-run) set_dry_mode ;;
    *) DRY=0; DEMO=0; sim_reset; DRY_LOG=(); tn real_banner ;;
  esac
}

settings_menu() {
  local c
  while :; do
    echo
    tn set_head
    note "  $(t set_1)"; note "  $(t set_2)"
    note "  $(t set_3 "${GAME_DIR:-$(t not_set)}")"; note "  $(t set_4)"; note "  $(t set_0)"
    read -r -p "  $(t choice_prompt 0)" c || bye
    case "${c:-0}" in
      1) choose_language ;;
      2) choose_run_type ;;
      3) GAME_DIR=""; step_game_dir ;;
      4) SRC_KIND=""; GAME_SRC=""; GAME_DIR=""; step_game_dir ;;
      0) return 0 ;;
      *) tw bad_choice "$c" ;;
    esac
  done
}

main_menu() {
  local c mode
  while :; do
    if [ "$DRY" = 1 ]; then mode=$(t mode_dry); else mode=$(t mode_real); fi
    echo
    note "$(t menu_state "$(t lang_name)" "$mode")"
    [ -n "$GAME_SRC" ] && note "$(t menu_src "$(t "src_name_$GAME_SRC")")"
    echo
    tn menu_head
    local k; for k in 1 2 3 4 5 6 7 8 9 0; do note "  $(t "menu_$k")"; done
    read -r -p "  $(t choice_prompt 3)" c || bye
    case "${c:-3}" in
      1) act_run flow_mscl ;;
      2) act_run flow_wmp_only ;;
      3) act_run flow_all ;;
      4) need_game_dir && show_status ;;
      5) need_game_dir && steam_cheatsheet ;;
      6) act_run flow_fixguid ;;
      7) settings_menu; continue ;;
      8) print_readme ;;
      9) act_run flow_tune ;;
      0|q|Q) return 0 ;;
      *) tw bad_choice "$c"; continue ;;
    esac
    echo; pause back_to_menu
  done
}

main() {
  trap 'echo; echo "  $(t interrupted)"; exit 130' INT
  local action="" arg
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -h|--help)    action=help ;;
      --readme)     action=readme ;;
      -V|--version) action=version ;;
      --status)     action=status ;;
      --fix-guid)   action=fixguid ;;
      --fix-reg|--fix-registry) action=fixreg ;;
      --steam-info) action=steaminfo ;;
      --tune)       action=tune ;;
      --gpu-check)  action=gpucheck ;;
      --dry-run)    DRY=1 ;;
      --steam)      SRC_KIND=steam ;;
      --nonsteam|--non-steam|--other) SRC_KIND=other ;;
      --game-dir)   shift; GAME_DIR_ARG="${1:-}" ;;
      --game-dir=*) GAME_DIR_ARG="${arg#--game-dir=}" ;;
      --prefix)     shift; PFX_ARG="${1:-}" ;;
      --prefix=*)   PFX_ARG="${arg#--prefix=}" ;;
      --wine)       shift; WINE_BIN="${1:-}" ;;
      --wine=*)     WINE_BIN="${arg#--wine=}" ;;
      --lang)       shift; set_lang "${1:-}" || { echo "Unknown language / Невідома мова: ${1:-}"; exit 2; } ;;
      --lang=*)     set_lang "${arg#--lang=}" || { echo "Unknown language / Невідома мова: ${arg#--lang=}"; exit 2; } ;;
      *) echo "Unknown option / Невідомий параметр: $arg"; echo "Help / Довідка: bash $SELF --help"; exit 2 ;;
    esac
    shift
  done
  [ -n "$UI" ] && { set_lang "$UI" || UI=""; }
  [ -z "$GAME_DIR_ARG" ] || GAME_DIR_ARG=$(clean_path "$GAME_DIR_ARG")
  [ -z "$PFX_ARG" ] || PFX_ARG=$(clean_path "$PFX_ARG")
  case "$action" in
    help|readme|version)
      [ -n "$UI" ] || UI=$(detect_locale)
      case "$action" in
        help)    print_help ;;
        readme)  print_readme ;;
        version) echo "msc-wizard.sh $VERSION" ;;
      esac
      exit 0 ;;
  esac

  [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; } || { echo "bash 4.4+ required / потрібен bash 4.4 або новіший."; exit 2; }
  [ -t 0 ] || { echo "Run the wizard in an interactive terminal / Запусти майстер в інтерактивному терміналі."; exit 2; }

  if [ -z "$UI" ]; then
    if [ -n "$action" ]; then UI=$(detect_locale); else choose_language; fi
  fi
  echo
  echo "$(t banner "$GAME_NAME" "$VERSION")"

  if [ "$DRY" = 1 ]; then set_dry_mode
  elif [ -z "$action" ]; then choose_run_type
  else tn real_banner; fi

  case "$action" in
    status)    need_game_dir || exit 1; show_status; exit 0 ;;
    steaminfo) need_game_dir || exit 1; steam_cheatsheet; exit 0 ;;
    gpucheck)  gpu_check; exit 0 ;;
    tune)      need_game_dir || exit 1; run_action flow_tune; rc=$?
               [ "$DRY" = 1 ] && dry_summary
               exit $rc ;;
    fixreg)    need_game_dir || exit 1; run_action flow_fixreg; rc=$?
               [ "$DRY" = 1 ] && dry_summary
               exit $rc ;;
    fixguid)   need_game_dir || exit 1; run_action flow_fixguid; rc=$?
               [ "$DRY" = 1 ] && dry_summary
               exit $rc ;;
  esac
  main_menu
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
