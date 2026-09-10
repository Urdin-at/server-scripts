#!/bin/bash
# =============================================================================
# nano.sh — настройка редактора nano (~/.nanorc).
#
# Что делает:
#   1. показывает текущий ~/.nanorc;
#   2. применяет рекомендованный набор настроек (подсветка, табы, нумерация);
#   3. очищает ~/.nanorc (с автоматическим бэкапом).
#
# Настройки:
#   NANORC  — путь к конфигу (по умолчанию ~/.nanorc);
#   SETTINGS — список строк настроек в функции apply_settings — правьте там.
#
# Требования: bash, nano; бэкап создаётся рядом с файлом (.bak.ГГГГММДД-ЧЧММСС).
#
# Автор: Urdin-at <urdin@yandex.ru>
# Версия: 1.0
# =============================================================================
# ─────────────── Единое оформление (общий стиль) ───────────────
# shellcheck disable=SC2034  # единая палитра оформления (часть цветов используется в других скриптах набора)
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

NANORC="$HOME/.nanorc"
BACKUP="${NANORC}.bak.$(date +%Y%m%d-%H%M%S)"

# Набор настроек, которые будем предлагать добавить
read -r -d '' SETTINGS << 'EOF'
set trimblanks          # Удалять пробелы в конце строк при сохранении
set softwrap            # мягкий перенос длинных строк
set indicator           # Показывать вертикальный индикатор прокрутки справа
set atblanks            # ^J выравнивает только до пустой строки
set cutfromcursor       # ^K вырезает от курсора до конца строки
set constantshow        # всегда показывать позицию курсора
set minibar             # показывать мини-строку состояния
set autoindent          # сохранять отступ предыдущей строки
set mouse               # поддержка мыши в терминале
set tabstospaces        # превращать табуляцию в пробелы
set tabsize 4           # табуляция = 4 пробела
set positionlog         # Запоминать позицию курсора в каждом файле
set linenumbers         # показывать номера строк

# Подсветка синтаксиса для большинства языков
include "/usr/share/nano/*.nanorc"
EOF

# ──────────────────────────────────────────────────────────────────────────────
# Функции
# ──────────────────────────────────────────────────────────────────────────────

backup_if_exists() {
    if [[ -f "$NANORC" ]]; then
        ui_warn "Создаю резервную копию: $BACKUP"
        if ! cp -f "$NANORC" "$BACKUP"; then
            ui_err "Ошибка при создании резервной копии"
            exit 1
        fi
    fi
}

show_nanorc() {
    if [[ -f "$NANORC" ]]; then
        ui_info "Содержимое ~/.nanorc:"
        printf '%s\n' "───────────────────────────────────────────────"
        cat "$NANORC"
        printf '%s\n' "───────────────────────────────────────────────"
    else
        ui_warn "Файл ~/.nanorc ещё не существует"
    fi
}

apply_settings() {
    backup_if_exists

    # Добавляем настройки, если их ещё нет
    local added=0
    local line key

    # Разбиваем многострочный текст на строки и обрабатываем по одной
    while IFS= read -r line; do
        # Пропускаем пустые строки и комментарии без set/include
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue

        # Значение без комментария и хвостовых пробелов
        key="${line%%#*}"
        key="${key%"${key##*[![:space:]]}"}"

        # Проверяем, есть ли уже такая строка (игнорируя комментарий)
        if grep -Fxq "$key" "$NANORC" 2>/dev/null || grep -q "^${key}[[:space:]]" "$NANORC" 2>/dev/null; then
            continue
        fi

        printf '%s\n' "$line" >> "$NANORC"
        added=$((added + 1))
        ui_ok "Добавлено: $line"
    done <<< "$SETTINGS"

    if ((added == 0)); then
        ui_warn "Все указанные настройки уже присутствуют"
    else
        ui_ok "Добавлено ${added} новых настроек"
        ui_info "Файл обновлён: $NANORC"
        ui_warn "Резервная копия: $BACKUP"
    fi
}

clear_nanorc() {
    if [[ ! -f "$NANORC" ]]; then
        ui_warn "Файл ~/.nanorc не существует — очищать нечего"
        return
    fi

    ui_err "ВНИМАНИЕ! Это действие удалит текущий ~/.nanorc"
    printf '%s' "${YELLOW}Вы уверены? [y/N]: ${NC}"
    local confirm
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        backup_if_exists
        : > "$NANORC"
        ui_ok "Файл ~/.nanorc очищен"
        ui_warn "Создана резервная копия: $BACKUP"
    else
        ui_warn "Операция отменена"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Главное меню
# ──────────────────────────────────────────────────────────────────────────────

while true; do
    ui_title "НАСТРОЙКА ~/.nanorc"
    ui_item 1 "Показать текущий ~/.nanorc"
    ui_item 2 "Внести рекомендованный набор настроек"
    ui_item 3 "Очистить ~/.nanorc (с резервной копией)"
    ui_item 0 "Выход"
    echo
    ui_ask 3
    read -r choice

    case "$choice" in
        1) show_nanorc; ui_pause ;;
        2) apply_settings; ui_pause ;;
        3) clear_nanorc; ui_pause ;;
        0) ui_ok "Выход"; exit 0 ;;
        *) ui_err "Неверный выбор" ;;
    esac

done
