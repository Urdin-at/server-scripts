#!/bin/bash
# =============================================================================
# soft.sh — установка базового набора программ.
#
# Что делает:
#   - определяет пакетный менеджер (apt / yum / dnf);
#   - обновляет список пакетов и ставит программы из списка PROGRAMS.
#
# Настройки:
#   PROGRAMS=(...) — список устанавливаемых программ (ниже в файле).
#   По умолчанию: curl, mc, ncdu, htop, bat, ripgrep, btop.
#
# Требования: bash; права root (установка пакетов), доступ в интернет/репозитории.
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

# Описание скрипта
ui_title "УСТАНОВКА ПРОГРАММ"
ui_info "Скрипт для установки программ на Linux системы"
ui_info "Скрипт автоматически определяет тип пакетного менеджера"
ui_info "(apt, yum или dnf) и устанавливает набор программ из списка."
ui_info "Список программ: curl, mc, ncdu, htop."
echo

# Список программ для установки
PROGRAMS=("curl" "mc" "ncdu" "htop" "bat" "ripgrep" "btop")

# Определение типа пакетного менеджера
if command -v apt &> /dev/null; then
    UPDATE_CMD=(apt update)
    INSTALL_CMD=(apt install -y)
elif command -v yum &> /dev/null; then
    UPDATE_CMD=(yum check-update)
    INSTALL_CMD=(yum install -y)
elif command -v dnf &> /dev/null; then
    UPDATE_CMD=(dnf check-update)
    INSTALL_CMD=(dnf install -y)
else
    ui_err "Не удалось определить пакетный менеджер. Поддерживаются только apt, yum и dnf."
    exit 1
fi

# Обновление списка пакетов
ui_info "Обновление списка пакетов..."
"${UPDATE_CMD[@]}"

# Установка программ из списка
for PROGRAM in "${PROGRAMS[@]}"; do
    ui_info "Установка $PROGRAM..."
    if "${INSTALL_CMD[@]}" "$PROGRAM"; then
        ui_ok "$PROGRAM успешно установлен."
    else
        ui_err "Ошибка при установке $PROGRAM."
    fi
done

echo
ui_ok "Установка завершена."
