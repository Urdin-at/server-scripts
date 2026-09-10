#!/bin/bash
# =============================================================================
# f2b.sh — управление fail2ban.
#
# Что делает:
#   - проверяет наличие и состояние fail2ban;
#   - устанавливает fail2ban подходящим пакетным менеджером (если нет);
#   - скачивает jail/filter/action-конфиги с вашего веб-сервера и раскладывает их;
#   - перезапускает сервис и показывает статистику по jail'ам.
#
# Настройки (в начале файла):
#   WEB_SERVER  — адрес сервера с конфигами. Стоит ЗАГЛУШКА https://example.com —
#                 замените на свой домен.
#   JAIL_PATH   — путь к каталогу jail-конфигов на сервере   (/scripts/fail2ban/jail)
#   FILTER_PATH — путь к каталогу filter-конфигов на сервере (/scripts/fail2ban/filter)
#
# Требования: bash, curl; права root; fail2ban (устанавливается по выбору).
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

# ─────────────── Конфигурация ───────────────
WEB_SERVER="https://example.com"      # ЗАГЛУШКА: адрес вашего веб-сервера
JAIL_PATH="/scripts/fail2ban/jail"    # Путь к jail конфигам на веб-сервере
FILTER_PATH="/scripts/fail2ban/filter" # Путь к filter конфигам на веб-сервере

# Функция для проверки наличия fail2ban
check_fail2ban() {
    command -v fail2ban-server &> /dev/null
}

# Функция для определения менеджера пакетов
detect_package_manager() {
    if command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v apt &> /dev/null; then
        echo "apt"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Функция проверки и установки curl
check_curl() {
    if ! command -v curl &> /dev/null; then
        ui_warn "curl не установлен. Устанавливаем..."
        local pkg_manager
        pkg_manager=$(detect_package_manager)

        case "$pkg_manager" in
            yum|dnf)
                "$pkg_manager" install -y curl
                ;;
            apt)
                apt update
                apt install -y curl
                ;;
            zypper)
                zypper install -y curl
                ;;
            pacman)
                pacman -Sy --noconfirm curl
                ;;
            *)
                ui_err "Не удалось определить менеджер пакетов. Установите curl вручную."
                return 1
                ;;
        esac

        local rc=$?
        if [[ $rc -eq 0 ]]; then
            ui_ok "curl успешно установлен"
        else
            ui_err "Ошибка при установке curl"
            return 1
        fi
    fi
    return 0
}

# Функция установки fail2ban для разных ОС
install_fail2ban() {
    ui_warn "Начинаем установку fail2ban..."

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        yum)
            ui_info "Обнаружен CentOS/RHEL. Устанавливаем EPEL и fail2ban..."
            yum install -y epel-release
            yum install -y fail2ban
            ;;
        dnf)
            ui_info "Обнаружен Fedora/RHEL 8+. Устанавливаем EPEL и fail2ban..."
            dnf install -y epel-release
            dnf install -y fail2ban
            ;;
        apt)
            ui_info "Обнаружен Debian/Ubuntu. Устанавливаем fail2ban..."
            apt update
            apt install -y fail2ban
            ;;
        zypper)
            ui_info "Обнаружен openSUSE. Устанавливаем fail2ban..."
            zypper install -y fail2ban
            ;;
        pacman)
            ui_info "Обнаружен Arch Linux. Устанавливаем fail2ban..."
            pacman -Sy --noconfirm fail2ban
            ;;
        *)
            ui_err "Не удалось определить менеджер пакетов. Установите fail2ban вручную."
            return 1
            ;;
    esac

    local rc=$?
    if [[ $rc -eq 0 ]]; then
        ui_ok "fail2ban успешно установлен"

        # Создание файла логов
        touch /var/log/fail2ban.log
        chmod 640 /var/log/fail2ban.log
        ui_ok "Файл логов создан: /var/log/fail2ban.log"

        # Запуск сервиса
        systemctl start fail2ban
        systemctl enable fail2ban
    else
        ui_err "Ошибка при установке fail2ban"
        return 1
    fi
}

# Функция проверки существования файла на сервере (curl)
check_file_exists() {
    local url="$1"
    curl -s --head --fail "$url" > /dev/null 2>&1
}

# Функция загрузки файла (curl)
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    local dest_dir

    printf ' Загружаем %s... ' "$description"

    # Создаем директорию назначения, если её нет
    dest_dir=$(dirname "$output")
    mkdir -p "$dest_dir"

    if curl -s --fail -o "$output" "$url" 2>/dev/null; then
        printf '%s\n' "${GREEN}✓${NC}"
        return 0
    else
        printf '%s\n' "${RED}✗${NC}"
        return 1
    fi
}

# Функция для получения списка файлов из HTML-листинга
parse_html_file_list() {
    local html_content="$1"

    # Ищем .conf и .local файлы в href ссылках
    printf '%s\n' "$html_content" | grep -o 'href="[^"]*\.\(conf\|local\)"' | \
        sed 's/href="//;s/"//g' | \
        grep -v '^\.\./$' | \
        grep -v '^/$' | \
        sort -u
}

# Функция загрузки файлов из одной директории веб-сервера
download_directory() {
    local remote_url="$1"
    local local_dir="$2"
    local dir_name="$3"
    local html_content
    local file_list
    local count
    local file
    local file_url
    local local_file

    ui_info "Проверяем $dir_name ($remote_url/):"

    # Получаем HTML содержимое директории
    html_content=$(curl -s -L "$remote_url/")

    if [[ -z "$html_content" ]]; then
        ui_err " Не удалось получить содержимое директории"
        return 1
    fi

    # Парсим список .conf и .local файлов
    file_list=$(parse_html_file_list "$html_content")

    if [[ -z "$file_list" ]]; then
        ui_warn " Не найдено .conf или .local файлов в листинге"
        echo ""
        return 0
    fi

    count=0
    ui_ok " Найдены файлы:"

    for file in $file_list; do
        # Очищаем имя файла
        file=$(basename "$file")

        # Пропускаем служебные ссылки
        if [[ "$file" == ".." ]] || [[ "$file" == "." ]] || [[ "$file" == /* ]]; then
            continue
        fi

        # Проверяем расширение (.conf или .local)
        if [[ "$file" == *.conf ]] || [[ "$file" == *.local ]]; then
            file_url="$remote_url/$file"
            local_file="$local_dir/$file"

            if download_file "$file_url" "$local_file" "$file"; then
                count=$((count + 1))
                TOTAL_DOWNLOADED=$((TOTAL_DOWNLOADED + 1))
                DOWNLOAD_SUCCESS=true
            fi
        fi
    done

    if [[ $count -gt 0 ]]; then
        ui_ok " Загружено $count файлов в $local_dir"
    else
        ui_warn " Не найдено .conf или .local файлов"
    fi
    echo ""
}

# Функция скачивания всех конфигов с веб-сервера
download_all_configs() {
    ui_warn "Начинаем скачивание конфигурационных файлов с веб-сервера..."

    # Проверяем наличие curl
    if ! check_curl; then
        ui_err "curl не установлен. Прерывание."
        return 1
    fi

    # Проверяем доступность веб-сервера
    ui_info "Проверяем доступность веб-сервера $WEB_SERVER..."
    if ! curl -s --head --fail "$WEB_SERVER" > /dev/null 2>&1; then
        ui_err "Веб-сервер $WEB_SERVER недоступен"
        return 1
    fi
    ui_ok "Веб-сервер доступен"
    echo ""

    # Создаем директории если их нет
    mkdir -p /etc/fail2ban/jail.d
    mkdir -p /etc/fail2ban/filter.d
    mkdir -p /etc/fail2ban/action.d

    DOWNLOAD_SUCCESS=false
    TOTAL_DOWNLOADED=0

    # Загружаем jail.d конфиги
    download_directory "$WEB_SERVER$JAIL_PATH" "/etc/fail2ban/jail.d" "jail.d"

    # Загружаем filter.d конфиги
    download_directory "$WEB_SERVER$FILTER_PATH" "/etc/fail2ban/filter.d" "filter.d"

    # Загружаем action.d конфиги (если есть)
    download_directory "$WEB_SERVER/scripts/fail2ban/action" "/etc/fail2ban/action.d" "action.d"

    # Загружаем основные конфиги из корневой директории
    ui_info "Проверяем корневую директорию (/scripts/fail2ban/):"

    local root_html
    local root_files
    local count
    local file
    local file_url
    local local_file

    # Получаем HTML содержимое корневой директории
    root_html=$(curl -s -L "$WEB_SERVER/scripts/fail2ban/")

    if [[ -n "$root_html" ]]; then
        root_files=$(parse_html_file_list "$root_html")

        if [[ -n "$root_files" ]]; then
            count=0

            for file in $root_files; do
                file=$(basename "$file")

                if [[ "$file" == *.conf ]] || [[ "$file" == *.local ]]; then
                    # Пропускаем файлы из поддиректорий
                    if [[ "$file" == *"/"* ]]; then
                        continue
                    fi

                    file_url="$WEB_SERVER/scripts/fail2ban/$file"
                    local_file="/etc/fail2ban/$file"

                    if download_file "$file_url" "$local_file" "$file"; then
                        count=$((count + 1))
                        TOTAL_DOWNLOADED=$((TOTAL_DOWNLOADED + 1))
                        DOWNLOAD_SUCCESS=true
                    fi
                fi
            done

            if [[ $count -gt 0 ]]; then
                ui_ok " Загружено $count основных конфигов"
            fi
        else
            ui_warn " Не найдено .conf или .local файлов в корневой директории"
        fi
    else
        ui_warn " Не удалось получить содержимое корневой директории"
    fi

    echo ""
    if [[ "$DOWNLOAD_SUCCESS" == true ]]; then
        ui_ok "Загрузка конфигурационных файлов завершена успешно"
        ui_ok "Всего загружено файлов: $TOTAL_DOWNLOADED"

        # Устанавливаем правильные права
        chmod 644 /etc/fail2ban/jail.d/* 2>/dev/null
        chmod 644 /etc/fail2ban/filter.d/* 2>/dev/null
        chmod 644 /etc/fail2ban/action.d/* 2>/dev/null
        chmod 644 /etc/fail2ban/*.local 2>/dev/null
        chmod 644 /etc/fail2ban/*.conf 2>/dev/null

        ui_ok "Права доступа установлены"
    else
        ui_err "Не удалось загрузить ни одного конфигурационного файла"
        ui_warn "Убедитесь, что на сервере $WEB_SERVER включен листинг директорий и файлы существуют:"
        echo " $WEB_SERVER$JAIL_PATH/"
        echo " $WEB_SERVER$FILTER_PATH/"
        echo " $WEB_SERVER/scripts/fail2ban/"
        echo ""
        ui_warn "Для работы скрипта необходимо, чтобы на веб-сервере был включен листинг директорий."
        return 1
    fi
}

# Функция перезапуска сервиса
restart_fail2ban() {
    ui_warn "Перезапускаем fail2ban..."

    if systemctl restart fail2ban; then
        ui_ok "Сервис успешно перезапущен"
        sleep 2
        systemctl status fail2ban --no-pager
    else
        ui_err "Ошибка при перезапуске сервиса"
    fi
}

# Функция просмотра статистики
show_stats() {
    ui_title "СТАТИСТИКА FAIL2BAN"

    # Проверяем, запущен ли fail2ban
    if ! systemctl is-active --quiet fail2ban; then
        ui_err "fail2ban не запущен"
        return 1
    fi

    # Получаем список всех jail'ов
    local jails
    jails=$(fail2ban-client status | grep "Jail list" | cut -f2- | sed 's/,//g')

    if [[ -z "$jails" ]]; then
        ui_warn "Нет активных jail'ов"
    else
        ui_ok "Активные jail'ы: $jails"
        echo ""

        # Для каждого jail показываем статистику
        local jail
        for jail in $jails; do
            ui_info "--- Jail: $jail ---"
            fail2ban-client status "$jail" | grep -E "Status|Banned IP list|Total banned|Currently banned" | sed 's/^[ \t]*//'
            echo ""
        done
    fi

    # Показываем последние записи из лога
    ui_info "Последние 10 записей из /var/log/fail2ban.log:"
    if [[ -f /var/log/fail2ban.log ]]; then
        tail -10 /var/log/fail2ban.log
    else
        ui_err "Файл лога не найден"
    fi
}

# Функция отображения меню
show_menu() {
    local service_status

    ui_title "УПРАВЛЕНИЕ FAIL2BAN"

    # Проверка наличия fail2ban
    if check_fail2ban; then
        printf ' fail2ban: %s\n' "${GREEN}✓ Установлен${NC}"
        # Получаем статус сервиса и окрашиваем его
        service_status=$(systemctl is-active fail2ban)
        case "$service_status" in
            active)
                printf ' Сервис: %s\n' "${GREEN}активен${NC}"
                ;;
            inactive)
                printf ' Сервис: %s\n' "${RED}остановлен${NC}"
                ;;
            failed)
                printf ' Сервис: %s\n' "${RED}ошибка${NC}"
                ;;
            *)
                printf ' Сервис: %s\n' "$service_status"
                ;;
        esac
    else
        printf ' fail2ban: %s\n' "${RED}✗ Не установлен${NC}"
    fi

    echo ""
    ui_info "──────────────────────────────────────────────────────"
    ui_item 1 "Установить fail2ban"
    ui_item 2 "Скачать все конфиги с веб-сервера"
    ui_item 3 "Перезапустить сервис"
    ui_item 4 "Просмотр статистики"
    ui_item 0 "Выход"
    echo
    ui_ask 4
}

# Основной цикл программы
while true; do
    show_menu
    read -r choice

    case "$choice" in
        1)
            if check_fail2ban; then
                ui_warn "fail2ban уже установлен"
            else
                install_fail2ban
            fi
            ui_pause
            ;;
        2)
            if check_fail2ban; then
                download_all_configs
            else
                ui_err "fail2ban не установлен. Сначала установите fail2ban."
            fi
            ui_pause
            ;;
        3)
            if check_fail2ban; then
                restart_fail2ban
            else
                ui_err "fail2ban не установлен. Сначала установите fail2ban."
            fi
            ui_pause
            ;;
        4)
            if check_fail2ban; then
                show_stats
            else
                ui_err "fail2ban не установлен. Сначала установите fail2ban."
            fi
            ui_pause
            ;;
        0)
            ui_ok "Выход из программы. До свидания!"
            exit 0
            ;;
        *)
            ui_err "Неверный выбор. Пожалуйста, выберите 0-4."
            ;;
    esac
done
