#!/bin/bash
# =============================================================================
# monitoring.sh — быстрый мониторинг состояния системы.
#
# Что делает (пункты меню):
#   1. загрузка CPU (top -bn1);
#   2. использование памяти (free -h);
#   3. использование диска (df -h);
#   4. сетевые адреса (ip addr);
#   5. топ процессов по CPU (ps aux).
#
# Настройки: не требуются. Только чтение, система не изменяется.
#
# Требования: bash; команды top, free, df, ip, ps.
#
# Автор: Urdin-at <urdin@yandex.ru>
# Версия: 1.0
# =============================================================================
# ─────────────── Единое оформление (общий стиль) ───────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
# shellcheck disable=SC2034  # BLUE входит в единую палитру всех скриптов
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

# Функция для отображения использования CPU
show_cpu() {
    ui_title "ИСПОЛЬЗОВАНИЕ CPU"
    top -bn1 | head -n 3
    ui_pause
}

# Функция для отображения использования памяти
show_memory() {
    ui_title "ИСПОЛЬЗОВАНИЕ ПАМЯТИ"
    free -h
    ui_pause
}

# Функция для отображения использования диска
show_disk() {
    ui_title "ИСПОЛЬЗОВАНИЕ ДИСКА"
    df -h
    ui_pause
}

# Функция для отображения сетевой информации
show_network() {
    ui_title "СЕТЕВАЯ ИНФОРМАЦИЯ"
    ip addr show | grep inet
    ui_pause
}

# Функция для отображения запущенных процессов
show_processes() {
    ui_title "ЗАПУЩЕННЫЕ ПРОЦЕССЫ"
    ps aux --sort=-%cpu | head -n 10
    ui_pause
}

# Основной цикл
while true; do
    ui_title "СИСТЕМА МОНИТОРИНГА"
    ui_item 1 "Использование CPU"
    ui_item 2 "Использование памяти"
    ui_item 3 "Использование диска"
    ui_item 4 "Сетевая информация"
    ui_item 5 "Запущенные процессы"
    ui_item 0 "Выход"
    echo
    ui_ask 5
    read -r choice

    case "$choice" in
        1) show_cpu ;;
        2) show_memory ;;
        3) show_disk ;;
        4) show_network ;;
        5) show_processes ;;
        0)
            clear 2>/dev/null || true
            ui_ok "Выход из программы..."
            exit 0
            ;;
        *)
            ui_err "Неверный выбор"
            sleep 1
            ;;
    esac
done
