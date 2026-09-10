#!/bin/bash
# =============================================================================
# scr.sh — загрузчик набора серверных скриптов (меню + загрузка по HTTP).
#
# Что делает:
#   1. скачивает список скриптов с сервера (index.txt, формат «файл - описание»);
#   2. показывает интерактивное меню;
#   3. скачивает выбранный скрипт во временный файл, выполняет и удаляет его,
#      затем возвращает в меню; выход — пункт 0 (с очисткой экрана).
#
# Настройки (единственная, ниже в файле):
#   SERVER_URL — адрес каталога со скриптами. По умолчанию стоит ЗАГЛУШКА
#                https://example.com/scripts — замените на адрес своего сервера.
#                Ожидаемая раскладка:
#                  <SERVER_URL>/index.txt    — список «имя_файла - описание»
#                  <SERVER_URL>/<имя_файла>  — сами скрипты
#
# Требования: bash, curl (загрузчик сам предложит установить curl при отсутствии).
#
# Автор: Urdin-at <urdin@yandex.ru>
# Версия: 1.0
# =============================================================================
# ─────────────── Единое оформление (общий стиль) ───────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

ui_title() {
    clear 2>/dev/null || true
    printf '%s\n' "${CYAN}══════════════════════════════════════════════════════${NC}"
    printf '%s\n' "${BOLD}${YELLOW}  $*${NC}"
    printf '%s\n' "${CYAN}══════════════════════════════════════════════════════${NC}"
}

ui_item()  { printf ' %s\n' "${GREEN}$1)${NC} $2"; }
ui_ask()   { printf '%s' "${GREEN}Выберите пункт [0-$1]: ${NC}"; }
ui_pause() { printf '\n%s' "${YELLOW}Нажмите Enter для продолжения...${NC}"; read -r _ || true; }
ui_ok()    { printf '%s\n' "${GREEN}$*${NC}"; }
ui_err()   { printf '%s\n' "${RED}$*${NC}"; }
ui_warn()  { printf '%s\n' "${YELLOW}$*${NC}"; }
ui_info()  { printf '%s\n' "${CYAN}$*${NC}"; }
# ───────────────────────────────────────────────────────────────

# ЗАГЛУШКА: замените на адрес своего сервера (каталог со скриптами и index.txt)
SERVER_URL="https://example.com/scripts"

# Функция для вывода приветствия
show_intro() {
    ui_title "СКРИПТ ДЛЯ УПРАВЛЕНИЯ УДАЛЁННЫМИ СКРИПТАМИ"
    ui_item 1 "Просматривать список доступных скриптов с удалённого сервера"
    ui_item 2 "Загружать и выполнять выбранные скрипты"
    printf '\n%s\n' "${BOLD}Сервер:${NC} ${BLUE}${SERVER_URL}${NC}"
    printf '\n%s\n' "${BOLD}Для изменения сервера отредактируйте переменную SERVER_URL в начале скрипта${NC}"
    ui_pause
}

# Функция для установки curl
install_curl() {
    local package_manager=""
    local -a update_cmd=()
    local -a install_cmd=()

    # Определяем менеджер пакетов
    if command -v apt &> /dev/null; then
        package_manager="apt"
        update_cmd=(apt update)
        install_cmd=(apt install -y curl)
    elif command -v yum &> /dev/null; then
        package_manager="yum"
        install_cmd=(yum install -y curl)
    elif command -v dnf &> /dev/null; then
        package_manager="dnf"
        install_cmd=(dnf install -y curl)
    elif command -v brew &> /dev/null; then
        package_manager="brew"
        install_cmd=(brew install curl)
    else
        ui_err "Не удалось определить менеджер пакетов."
        ui_err "Пожалуйста, установите curl вручную."
        exit 1
    fi

    printf '%s\n' "${BOLD}Обнаружен менеджер пакетов:${NC} $package_manager"
    ui_warn "Для работы скрипта необходимо установить curl."

    # Проверяем, есть ли права root
    if [[ "$(id -u)" -eq 0 ]]; then
        ui_ok "У вас есть права root. Устанавливаем curl..."
        if [[ ${#update_cmd[@]} -gt 0 ]]; then
            "${update_cmd[@]}"
        fi
        "${install_cmd[@]}"
    else
        ui_warn "Для установки требуются права администратора."
        printf '%s' "${YELLOW}Хотите попробовать установить curl с помощью sudo? (y/N) ${NC}"
        read -r answer
        if [[ "$answer" =~ ^[Yy] ]]; then
            ui_ok "Установка curl с помощью sudo..."
            if [[ ${#update_cmd[@]} -gt 0 ]]; then
                sudo "${update_cmd[@]}"
            fi
            sudo "${install_cmd[@]}"
        else
            ui_err "Установка curl отменена."
            exit 1
        fi
    fi

    # Проверяем успешность установки
    if ! command -v curl &> /dev/null; then
        ui_err "Не удалось установить curl. Пожалуйста, установите его вручную."
        exit 1
    fi

    ui_ok "Утилита curl успешно установлена!"
    sleep 1
}

# Функция для проверки curl
check_curl() {
    if ! command -v curl &> /dev/null; then
        ui_err "Утилита curl не установлена."
        install_curl
    fi
}

# Основной код скрипта
show_intro
check_curl

# Основной цикл меню
while true; do
    # Загрузка списка скриптов
    INDEX_FILE=$(mktemp)
    if ! curl -s "$SERVER_URL/index.txt" -o "$INDEX_FILE"; then
        ui_err "ОШИБКА: Не удалось загрузить список скриптов."
        ui_err "Проверьте подключение к интернету и доступность сервера: $SERVER_URL"
        rm -f "$INDEX_FILE"
        sleep 3
        continue
    fi

    # Проверка, что файл не пустой
    if [[ ! -s "$INDEX_FILE" ]]; then
        ui_err "ОШИБКА: Файл со списком скриптов пуст или недоступен."
        ui_err "Проверьте наличие файла index.txt на сервере: $SERVER_URL/index.txt"
        rm -f "$INDEX_FILE"
        sleep 3
        continue
    fi

    # Отображение меню
    mapfile -t scripts < "$INDEX_FILE"
    total=${#scripts[@]}

    ui_title "ДОСТУПНЫЕ СКРИПТЫ"
    printf '%s\n' "${BOLD}Сервер:${NC} ${BLUE}${SERVER_URL}${NC}"
    printf '\n'

    for i in "${!scripts[@]}"; do
        script_name=${scripts[$i]%% - *}
        script_desc=""
        if [[ ${scripts[$i]} == *" - "* ]]; then
            script_desc=${scripts[$i]#* - }
        fi
        if [[ -n "$script_desc" ]]; then
            ui_item "$((i + 1))" "${BOLD}${script_name}${NC} - ${script_desc}"
        else
            ui_item "$((i + 1))" "${BOLD}${scripts[$i]}${NC}"
        fi
    done

    printf '\n'
    ui_item 0 "Выход"
    printf '\n'

    # Запрос выбора
    ui_ask "$total"
    read -r choice

    # Проверка выбора
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice > total )); then
        ui_err "Неверный ввод. Пожалуйста, введите число от 0 до $total."
        sleep 2
        continue
    fi

    # Выход
    if (( choice == 0 )); then
        ui_warn "Завершение работы..."
        clear 2>/dev/null || true
        exit 0
    fi

    # Получаем имя скрипта
    selected_script=${scripts[$((choice - 1))]%% - *}

    # Загрузка и выполнение скрипта
    SCRIPT_FILE=$(mktemp)

    ui_info "Загрузка скрипта '$selected_script' с сервера $SERVER_URL..."

    if ! curl -s "$SERVER_URL/$selected_script" -o "$SCRIPT_FILE"; then
        ui_err "ОШИБКА: Не удалось загрузить скрипт '$selected_script'"
        ui_err "Проверьте наличие файла на сервере: $SERVER_URL/$selected_script"
        sleep 2
        rm -f "$SCRIPT_FILE" "$INDEX_FILE"
        continue
    fi

    # Выполнение
    printf '\n'
    ui_title "Выполнение скрипта: $selected_script"

    # Делаем скрипт исполняемым
    chmod +x "$SCRIPT_FILE"

    # Выполняем скрипт
    bash "$SCRIPT_FILE"

    # Пауза, чтобы прочитать вывод выполненного скрипта
    ui_pause

    # Очистка
    rm -f "$INDEX_FILE" "$SCRIPT_FILE"
done
