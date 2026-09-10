#!/bin/bash
# =============================================================================
# sshkeys.sh — управление авторизацией по SSH-ключам.
#
# Что делает:
#   - проверяет, работает ли вход по ключу (текущий пользователь и root);
#   - включает авторизацию по ключу (правит sshd_config, создаёт каталоги/ключи);
#   - выводит список зарегистрированных ключей;
#   - добавляет новый ключ (проверяет дубликаты).
#
# Настройки:
#   Вшитый ключ (пункт меню 6) — переменная embedded_key в функции
#   add_embedded_key(). По умолчанию там ЗАГЛУШКА
#   (REPLACE_WITH_YOUR_PUBLIC_KEY): впишите свой публичный ключ одной строкой,
#   иначе скрипт откажется добавлять его и подскажет, что заменить.
#   Пути стандартные: ~/.ssh/authorized_keys для пользователя и
#   /root/.ssh/authorized_keys для root — отдельных настроек не требуют.
#
# Требования: bash; права root для изменения настроек sshd и ключей root.
#
# Автор: Urdin-at <urdin@yandex.ru>
# Версия: 1.0
# =============================================================================

# shellcheck disable=SC2034
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

# Функция для проверки возможности доступа по SSH с авторизацией по ключу
check_ssh_key_auth() {
    local user=$1
    local ssh_dir="/home/$user/.ssh"
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    fi

    if [[ -f "$ssh_dir/authorized_keys" ]]; then
        ui_ok "Авторизация по ключу для пользователя $user включена."
    else
        ui_warn "Авторизация по ключу для пользователя $user отключена."
    fi
}

# Функция для включения авторизации по ключу
enable_ssh_key_auth() {
    local user=$1
    local ssh_dir="/home/$user/.ssh"
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    fi

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    touch "$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"
    chown -R "$user:$user" "$ssh_dir"
    ui_ok "Авторизация по ключу для пользователя $user включена."
}

# Функция для вывода списка зарегистрированных ключей
list_authorized_keys() {
    local user=$1
    local ssh_dir="/home/$user/.ssh"
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    fi

    if [[ -f "$ssh_dir/authorized_keys" ]]; then
        ui_info "Зарегистрированные ключи для пользователя $user:"
        cat "$ssh_dir/authorized_keys"
    else
        ui_warn "Нет зарегистрированных ключей для пользователя $user."
    fi
}

# Функция для проверки дублирования ключа
is_key_duplicate() {
    local user=$1
    local key=$2
    local ssh_dir="/home/$user/.ssh"
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    fi

    if [[ -f "$ssh_dir/authorized_keys" ]] && grep -Fxq "$key" "$ssh_dir/authorized_keys"; then
        return 0  # Ключ уже существует
    else
        return 1  # Ключ не найден
    fi
}

# Функция для добавления нового ключа
add_ssh_key() {
    local user=$1
    local ssh_dir="/home/$user/.ssh"
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    fi

    local ssh_key
    ui_info "Введите новый SSH-ключ:"
    read -r ssh_key

    if is_key_duplicate "$user" "$ssh_key"; then
        ui_err "Ошибка: Этот ключ уже добавлен для пользователя $user."
    else
        printf '%s\n' "$ssh_key" >> "$ssh_dir/authorized_keys"
        ui_ok "Ключ добавлен для пользователя $user."
    fi
}



# Функция для добавления ключа, вшитого в скрипт (см. «Настройки» в шапке)
add_embedded_key() {
    local user=$1
    local ssh_dir="/home/$user/.ssh"
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    fi

    # ЗАГЛУШКА: впишите сюда свой публичный SSH-ключ одной строкой
    # (содержимое файла ~/.ssh/id_ed25519.pub или аналогичного).
    local embedded_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI REPLACE_WITH_YOUR_PUBLIC_KEY your-name@example.com"

    if [[ "$embedded_key" == *REPLACE_WITH_YOUR_PUBLIC_KEY* ]]; then
        ui_err "Ключ не задан: впишите свой публичный ключ в переменную embedded_key"
        ui_info "Функция add_embedded_key(), строка с REPLACE_WITH_YOUR_PUBLIC_KEY"
        return 1
    fi

    if is_key_duplicate "$user" "$embedded_key"; then
        ui_err "Ошибка: Вшитый ключ уже добавлен для пользователя $user."
    else
        printf '%s\n' "$embedded_key" >> "$ssh_dir/authorized_keys"
        ui_ok "Вшитый ключ добавлен для пользователя $user."
    fi
}

# Основное меню
while true; do
    ui_title "УПРАВЛЕНИЕ SSH-КЛЮЧАМИ"
    ui_item 1 "Проверить возможность доступа по SSH с авторизацией по ключу"
    ui_item 2 "Включить авторизацию по ключу для обычного пользователя"
    ui_item 3 "Включить авторизацию по ключу для root пользователя"
    ui_item 4 "Вывести список зарегистрированных ключей"
    ui_item 5 "Добавить новый ключ"
    ui_item 6 "Добавить вшитый ключ (задан в настройках скрипта)"
    ui_item 0 "Выход"
    echo
    ui_ask 6
    read -r choice

    case "$choice" in
        1)
            check_ssh_key_auth "$(whoami)"
            check_ssh_key_auth "root"
            ui_pause
            ;;
        2)
            enable_ssh_key_auth "$(whoami)"
            ui_pause
            ;;
        3)
            enable_ssh_key_auth "root"
            ui_pause
            ;;
        4)
            list_authorized_keys "$(whoami)"
            list_authorized_keys "root"
            ui_pause
            ;;
        5)
            add_ssh_key "$(whoami)"
            ui_pause
            ;;
        6)
            add_embedded_key "$(whoami)"
            ui_pause
            ;;
        0)
            ui_ok "Выход из программы."
            break
            ;;
        *)
            ui_err "Неверный выбор. Попробуйте снова."
            ;;
    esac
done
