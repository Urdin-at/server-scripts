#!/bin/bash
# =============================================================================
# sysinfo.sh — сводная информация о системе.
#
# Что делает:
#   - количество ядер CPU (nproc) и объём оперативной памяти;
#   - список подключённых дисков (lsblk, без loop-устройств);
#   - дистрибутив и его версия (/etc/os-release);
#   - тип пакетов (DEB/RPM).
#
# Настройки: не требуются. Скрипт только читает данные, ничего не меняет.
#
# Требования: bash; команды nproc, lsblk, awk; dpkg или rpm (по наличию).
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

ui_title "СИСТЕМНАЯ ИНФОРМАЦИЯ"

# Вывод количества ядер CPU
ui_info "Количество ядер CPU: $(nproc)"

# Вывод общего объема оперативной памяти
ui_info "Общий объем оперативной памяти: $(grep MemTotal /proc/meminfo | awk '{print $2/1024 " MB"}')"

# Вывод информации о подключенных дисках
ui_info "Подключенные диски:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop

# Вывод названия и версии дистрибутива
NAME=""
VERSION=""
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    ui_info "Название дистрибутива: $NAME"
    ui_info "Версия дистрибутива: $VERSION"
else
    ui_warn "Название и версия дистрибутива: Не удалось определить"
fi

# Вывод типа пакетов
if command -v dpkg &> /dev/null; then
    ui_info "Тип пакетов: DEB (Debian/Ubuntu)"
elif command -v rpm &> /dev/null; then
    ui_info "Тип пакетов: RPM (Red Hat/CentOS/Fedora)"
else
    ui_warn "Тип пакетов: Не удалось определить"
fi

