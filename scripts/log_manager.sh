#!/bin/bash
# =============================================================================
# log_manager.sh — работа с системными логами.
#
# Что делает:
#   - очищает старые логи в LOG_DIR (с учётом исключений);
#   - настраивает ротацию (сдвиг файлов, хранение ROTATE_COUNT копий);
#   - показывает список логов с размерами;
#   - открывает выбранный лог для просмотра.
#
# Настройки (в начале файла):
#   LOG_DIR       — каталог логов (по умолчанию /var/log)
#   MAX_SIZE      — порог размера для ротации (например, 50M)
#   ROTATE_COUNT  — сколько ротаций хранить
#   EXCLUDE_FILES — маски исключений (*.gz *.bz2 *.xz)
#
# Требования: bash; права root (запись в /var/log).
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

# Конфигурация
LOG_DIR="/var/log"              # Директория системных логов
MAX_SIZE="50M"                  # Максимальный размер лога
ROTATE_COUNT=7                  # Количество ротаций
EXCLUDE_FILES=("*.gz" "*.bz2" "*.xz")  # Исключаемые файлы

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    ui_err "Ошибка: Требуются права root (используйте sudo)"
    exit 1
fi

# Проверка директории логов
if [[ ! -d "$LOG_DIR" ]]; then
    ui_err "Ошибка: Директория $LOG_DIR не найдена"
    exit 1
fi

# Функция очистки логов
clean_logs() {
    local days
    printf '%s\n' "Введите количество дней для удаления логов (например, 30):"
    read -r days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        ui_err "Ошибка: Введите число"
        return 1
    fi

    ui_info "Удаление логов старше $days дней..."

    local -a find_args=("$LOG_DIR" -type f -name "*.log" -mtime "+$days" -not -path "*/journal/*")
    local pattern
    for pattern in "${EXCLUDE_FILES[@]}"; do
        find_args+=(-not -name "$pattern")
    done

    find "${find_args[@]}" -exec rm -fv {} \;
    ui_ok "Очистка завершена"
}

# Функция ротации логов
rotate_logs() {
    printf '%s\n' "Текущие настройки ротации: размер=$MAX_SIZE, ротаций=$ROTATE_COUNT"
    printf '%s\n' "Изменить настройки? (y/n)"
    local answer new_size new_count
    read -r answer
    if [[ "$answer" == "y" ]]; then
        printf '%s\n' "Новый максимальный размер (например, 50M, 500K):"
        read -r new_size
        printf '%s\n' "Новое количество ротаций:"
        read -r new_count
        if [[ "$new_count" =~ ^[0-9]+$ ]]; then
            MAX_SIZE="$new_size"
            ROTATE_COUNT="$new_count"
            ui_ok "Настройки обновлены"
        else
            ui_err "Ошибка: Неверное количество ротаций"
            return 1
        fi
    fi

    local -a find_args=("$LOG_DIR" -type f -name "*.log" -not -path "*/journal/*")
    local pattern
    for pattern in "${EXCLUDE_FILES[@]}"; do
        find_args+=(-not -name "$pattern")
    done

    local log_file file_size max_size_bytes i
    while IFS= read -r log_file; do
        if [[ -f "$log_file" ]]; then
            file_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null)
            max_size_bytes=$(numfmt --from=iec "$MAX_SIZE" 2>/dev/null)
            if [[ -n "$file_size" && -n "$max_size_bytes" && "$file_size" -gt "$max_size_bytes" ]]; then
                ui_info "Ротация: $log_file"
                for ((i = ROTATE_COUNT - 1; i >= 0; i--)); do
                    [[ -f "${log_file}.${i}" ]] && mv -f "${log_file}.${i}" "${log_file}.$((i + 1))"
                done
                mv -f "$log_file" "${log_file}.0"
                touch "$log_file"
                # Восстановление прав и владельца
                [[ -f "${log_file}.0" ]] && chown --reference="${log_file}.0" "$log_file" 2>/dev/null
                [[ -f "${log_file}.0" ]] && chmod --reference="${log_file}.0" "$log_file" 2>/dev/null
            fi
        fi
    done < <(find "${find_args[@]}")
}

# Функция вывода списка логов
list_logs() {
    printf '%s\n' "Список логов:"
    local -a find_args=("$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.[0-9]" \) -not -path "*/journal/*")
    local pattern
    for pattern in "${EXCLUDE_FILES[@]}"; do
        find_args+=(-not -name "$pattern")
    done

    # Сохраняем список логов в массив
    mapfile -t log_list < <(find "${find_args[@]}" | sort)
    if [[ ${#log_list[@]} -eq 0 ]]; then
        ui_warn "Логи не найдены"
        return 1
    fi
    local i size
    for i in "${!log_list[@]}"; do
        size=$(stat -c%s "${log_list[i]}" 2>/dev/null)
        size=$(numfmt --to=iec "$size" 2>/dev/null || printf '%s' "$size")
        printf '%3d) %s (%s)\n' "$((i + 1))" "${log_list[i]}" "$size"
    done
}

# Функция просмотра лога
view_log() {
    list_logs
    # Проверяем, есть ли логи
    if [[ ${#log_list[@]} -eq 0 ]]; then
        return 1
    fi
    printf '%s\n' "Введите номер лога (1-${#log_list[@]}):"
    local log_number
    read -r log_number
    if ! [[ "$log_number" =~ ^[0-9]+$ ]] || [[ "$log_number" -lt 1 || "$log_number" -gt ${#log_list[@]} ]]; then
        ui_err "Ошибка: Неверный номер лога"
        return 1
    fi
    local log_file="${log_list[$((log_number - 1))]}"

    if [[ ! -f "$log_file" || "$log_file" =~ \.(gz|bz2|xz)$ ]]; then
        ui_err "Ошибка: Файл $log_file не существует или сжат"
        return 1
    fi

    printf '%s\n' "Количество строк для просмотра (Enter — весь файл):"
    local lines
    read -r lines
    if [[ "$lines" =~ ^[0-9]+$ ]]; then
        tail -n "$lines" "$log_file"
    else
        cat "$log_file"
    fi
}

# Основной цикл
while true; do
    ui_title "УПРАВЛЕНИЕ СИСТЕМНЫМИ ЛОГАМИ"
    ui_item 1 "Очистить старые логи"
    ui_item 2 "Настроить ротацию"
    ui_item 3 "Список логов"
    ui_item 4 "Просмотреть лог"
    ui_item 0 "Выход"
    echo
    ui_ask 4
    read -r choice

    case "$choice" in
        1) clean_logs; ui_pause ;;
        2) rotate_logs; ui_pause ;;
        3) list_logs; ui_pause ;;
        4) view_log; ui_pause ;;
        0) clear 2>/dev/null || true; ui_ok "Выход"; exit 0 ;;
        *) ui_err "Неверный выбор" ;;
    esac
done
