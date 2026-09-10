#!/bin/bash
# =============================================================================
# aliases.sh — управление алиасами оболочки.
#
# Что делает:
#   - показывает текущие алиасы;
#   - добавляет и удаляет алиасы в ~/.bashrc;
#   - ставит готовый набор алиасов (ll, cls, grep, hg, net, cat + update/install);
#   - включает применение алиасов для root.
#
# Настройки:
#   Состав готового набора задаётся в функции add_default_aliases (ассоциативный
#   массив default_aliases) — правьте список там. Отдельных путей нет: алиасы
#   пишутся в ~/.bashrc пользователя; для root — в /root/.bashrc и ~/.profile.
#
# Требования: bash; права root — только для пункта про root.
#
# Автор: Urdin-at <urdin@yandex.ru>
# Версия: 1.0
# =============================================================================

# shellcheck disable=SC1090,SC2016,SC2034
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

# Функция для отображения текущих алиасов
show_aliases() {
    ui_info "Текущие алиасы:"
    alias
}

# Функция для добавления нового алиаса
add_alias() {
    local alias_name alias_command

    ui_info "Введите имя нового алиаса:"
    read -r alias_name
    ui_info "Введите команду для алиаса:"
    read -r alias_command

    # Проверка на дублирование алиаса
    if alias "$alias_name" &>/dev/null; then
        ui_err "Ошибка: Алиас '$alias_name' уже существует."
        return
    fi

    # Добавляем алиас в ~/.bashrc
    printf '%s\n' "alias ${alias_name}='${alias_command}'" >> ~/.bashrc
    source ~/.bashrc  # Применяем изменения без перезагрузки
    ui_ok "Алиас '$alias_name' добавлен и применён."
}

# Функция для удаления алиаса
remove_alias() {
    local alias_list alias_name alias_number selected_alias confirm
    local count=1
    declare -A alias_map

    ui_info "Список алиасов:"
    alias_list=$(alias | awk -F'=' '{print $1}' | sed 's/alias //')  # Получаем список алиасов
    if [[ -z "$alias_list" ]]; then
        ui_warn "Алиасов не найдено."
        return
    fi

    # Выводим алиасы с номерами
    while IFS= read -r alias_name; do
        ui_item "$count" "$alias_name"
        alias_map["$count"]="$alias_name"
        ((count++))
    done <<< "$alias_list"

    ui_info "Введите номер алиаса для удаления:"
    read -r alias_number

    if [[ -z "${alias_map[$alias_number]:-}" ]]; then
        ui_err "Неверный номер алиаса."
        return
    fi

    selected_alias="${alias_map[$alias_number]}"
    ui_info "Вы выбрали алиас: $selected_alias"
    ui_info "Вы уверены, что хотите удалить его? (y/n)"
    read -r confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # Удаляем алиас из ~/.bashrc
        sed -i "/alias $selected_alias=/d" ~/.bashrc
        unalias "$selected_alias" 2>/dev/null  # Удаляем алиас из текущей сессии
        source ~/.bashrc  # Применяем изменения
        ui_ok "Алиас '$selected_alias' удалён."
    else
        ui_warn "Удаление отменено."
    fi
}

# Функция для добавления набора готовых алиасов
add_default_aliases() {
    local alias_name

    ui_info "Добавление набора готовых алиасов..."

    # Общие алиасы для всех систем
    declare -A default_aliases=(
        ["ll"]="ls -la"
        ["cls"]="clear"
        ["grep"]="grep --color=auto"
        ["hg"]="history | grep"
        ["net"]="netstat -lptun"
        ["cat"]="batcat --paging=never"
    )

    # Определение пакетного менеджера и добавление соответствующих алиасов
    if command -v apt &>/dev/null; then
        ui_info "Обнаружен пакетный менеджер APT."
        default_aliases["update"]="apt update && apt upgrade -y"
        default_aliases["install"]="apt install -y"
    elif command -v yum &>/dev/null; then
        ui_info "Обнаружен пакетный менеджер YUM."
        default_aliases["update"]="yum update -y"
        default_aliases["install"]="yum install -y"
    elif command -v dnf &>/dev/null; then
        ui_info "Обнаружен пакетный менеджер DNF."
        default_aliases["update"]="dnf update -y"
        default_aliases["install"]="dnf install -y"
    else
        ui_warn "Пакетный менеджер не обнаружен. Алиасы для update/install не добавлены."
    fi

    # Добавляем алиасы, если они ещё не существуют
    for alias_name in "${!default_aliases[@]}"; do
        if ! alias "$alias_name" &>/dev/null; then
            printf '%s\n' "alias ${alias_name}='${default_aliases[$alias_name]}'" >> ~/.bashrc
            ui_ok "Алиас '$alias_name' добавлен."
        else
            ui_warn "Алиас '$alias_name' уже существует, пропускаем."
        fi
    done

    source ~/.bashrc  # Применяем изменения без перезагрузки
    ui_ok "Готовые алиасы добавлены и применены."
}

# Функция для включения применения алиасов для root через ~/.profile
enable_root_aliases() {
    local root_profile required_content

    if [[ $EUID -ne 0 ]]; then
        ui_err "Эта функция требует прав root. Запустите скрипт от имени root."
        return
    fi

    root_profile="/root/.profile"
    required_content='
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi'

    # Проверяем, существует ли файл ~/.profile
    if [[ ! -f "$root_profile" ]]; then
        ui_warn "Файл $root_profile отсутствует. Создаём новый файл..."
        printf '%s\n' "$required_content" > "$root_profile"
        ui_ok "Файл $root_profile создан с необходимым содержимым."
        return
    fi

    # Проверяем, содержит ли файл нужное содержимое
    if grep -Fxq 'if [ "$BASH" ]; then' "$root_profile" &&
       grep -Fxq '  if [ -f ~/.bashrc ]; then' "$root_profile" &&
       grep -Fxq '    . ~/.bashrc' "$root_profile" &&
       grep -Fxq '  fi' "$root_profile" &&
       grep -Fxq 'fi' "$root_profile"; then
        ui_info "Файл $root_profile уже содержит необходимое содержимое."
    else
        ui_info "Добавляем необходимое содержимое в $root_profile..."
        printf '%s\n' "$required_content" >> "$root_profile"
        ui_ok "Содержимое добавлено в $root_profile."
    fi
}

# Основное меню
while true; do
    ui_title "УПРАВЛЕНИЕ АЛИАСАМИ"
    ui_item 1 "Просмотреть алиасы"
    ui_item 2 "Добавить новый алиас"
    ui_item 3 "Удалить алиас"
    ui_item 4 "Добавить набор готовых алиасов"
    ui_item 5 "Включить применение алиасов для root"
    ui_item 0 "Выход"
    echo
    ui_ask 5
    read -r choice

    case "$choice" in
        1)
            show_aliases
            ui_pause
            ;;
        2)
            add_alias
            ui_pause
            ;;
        3)
            remove_alias
            ui_pause
            ;;
        4)
            add_default_aliases
            ui_pause
            ;;
        5)
            enable_root_aliases
            ui_pause
            ;;
        0)
            ui_ok "Выход."
            break
            ;;
        *)
            ui_err "Неверный выбор. Попробуйте снова."
            ;;
    esac

done
