#!/bin/bash
# =============================================================================
# mysql_backup.sh — мастер резервного копирования MySQL.
#
# Что делает:
#   - проверяет, требует ли root MySQL пароль;
#   - показывает список баз и даёт выбрать нужные;
#   - спрашивает каталог хранения копий, расписание (ежедневно / еженедельно /
#     ежемесячно / произвольный cron) и количество хранимых копий;
#   - создаёт скрипт бэкапа с логированием и ставит задание в cron.
#
# Настройки:
#   LOG_FILE — журнал работы (по умолчанию /var/log/mysql_backup.log).
#   Остальные параметры задаются в диалоге и фиксируются в созданном скрипте.
#
# Требования: bash; mysql/mysqldump; права на запись в каталог копий и crontab.
#
# Автор: Urdin-at <urdin@yandex.ru>
# Версия: 1.0
# =============================================================================
# ─────────────── Единое оформление (общий стиль) ───────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
# shellcheck disable=SC2034  # цвет зарезервирован для расширения оформления
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

# Путь к лог-файлу
LOG_FILE="/var/log/mysql_backup.log"

# Функция для логирования
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Функция для обработки ошибок
error() {
    local message="$1"
    log "ОШИБКА: $message"
    exit 1
}

# Логирование начала работы скрипта
log "Запуск скрипта резервного копирования MySQL."

# Проверка необходимости пароля для пользователя root
ui_title "Резервное копирование MySQL"
log "Проверка необходимости пароля для пользователя root..."
if mysql -u root -e "SHOW DATABASES;" > /dev/null 2>&1; then
    log "Пароль для пользователя root не требуется."
    # shellcheck disable=SC2034  # переменная сохранена для обратной совместимости
    MYSQL_PASSWORD=""
else
    printf '%s\n' "${GREEN}Введите пароль для пользователя root MySQL:${NC}"
    read -rs MYSQL_ROOT_PASSWORD
    export MYSQL_ROOT_PASSWORD
    log "Пароль для пользователя root получен."
fi

# Получение списка доступных баз данных
log "Получение списка баз данных..."
databases=$(mysql -u root "${MYSQL_ROOT_PASSWORD:+-p"$MYSQL_ROOT_PASSWORD"}" -e "SHOW DATABASES;" 2>> "$LOG_FILE" | grep -Ev "(Database|information_schema|performance_schema|mysql)")

# Проверка, удалось ли получить список баз данных
if [[ -z "$databases" ]]; then
    error "Не удалось получить список баз данных. Проверьте подключение к MySQL."
fi

# Вывод списка баз данных
ui_title "Выбор баз данных"
printf '%s\n' "${BOLD}Доступные базы данных:${NC}"
i=1
while IFS= read -r db; do
    ui_item "$i" "$db"
    i=$((i + 1))
done <<< "$databases"

# Запрос выбора баз данных для бэкапа
printf '%s' "${GREEN}Введите номера баз данных для бэкапа через пробел: ${NC}"
read -r selected_indices
read -ra selected_array <<< "$selected_indices"

# Преобразование выбранных индексов в названия баз данных
selected_databases=""
for index in "${selected_array[@]}"; do
    db=$(sed -n "${index}p" <<< "$databases")
    if [[ -z "$db" ]]; then
        error "Неверный номер базы данных: $index"
    fi
    selected_databases="$selected_databases $db"
done

# Запрос пути для хранения резервных копий
ui_title "Путь для резервных копий"
printf '%s' "${GREEN}Введите путь для хранения резервных копий: ${NC}"
read -r backup_path

# Создание директории, если она не существует
if [[ ! -d "$backup_path" ]]; then
    log "Создание директории для резервных копий: $backup_path"
    mkdir -p "$backup_path" || error "Не удалось создать директорию $backup_path"
fi

# Удобный диалог выбора периодичности бекапа
ui_title "Периодичность бекапа"
ui_item 1 "Ежедневно (в 2:00)"
ui_item 2 "Еженедельно (в 2:00 по воскресеньям)"
ui_item 3 "Ежемесячно (в 2:00 первого числа месяца)"
ui_item 4 "Вручную (указать свой cron-формат)"
ui_ask 4
read -r cron_choice

case "$cron_choice" in
    1)
        cron_schedule="0 2 * * *"
        ;;
    2)
        cron_schedule="0 2 * * 0"
        ;;
    3)
        cron_schedule="0 2 1 * *"
        ;;
    4)
        printf '%s\n' "${GREEN}Введите cron-формат вручную (например, '0 2 * * *' для ежедневного бекапа в 2:00):${NC}"
        read -r cron_schedule
        ;;
    *)
        ui_warn "Неверный выбор. Используется значение по умолчанию: ежедневно в 2:00."
        log "Неверный выбор. Используется значение по умолчанию: ежедневно в 2:00."
        cron_schedule="0 2 * * *"
        ;;
esac

# Запрос количества хранимых копий
ui_title "Количество хранимых копий"
printf '%s' "${GREEN}Введите количество хранимых копий: ${NC}"
read -r backup_count

# Проверка, что введено корректное число
if ! [[ "$backup_count" =~ ^[0-9]+$ ]]; then
    error "Количество копий должно быть числом."
fi

# Создание нового скрипта для бекапа
backup_script="$backup_path/mysql_backup.sh"

cat <<EOF > "$backup_script"
#!/bin/bash

# Параметры
databases="$selected_databases"
backup_path="$backup_path"
backup_count="$backup_count"
LOG_FILE="$LOG_FILE"

# Функция для логирования
log() {
    local message="\$1"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$message" | tee -a "\$LOG_FILE"
}

# Функция для обработки ошибок
error() {
    local message="\$1"
    log "ОШИБКА: \$message"
    exit 1
}

# Логирование начала бекапа
log "Начало резервного копирования баз данных: \$databases"

# Создание резервной копии
date=\$(date +"%Y%m%d")
for db in \$databases; do
    backup_file="\$backup_path/\$date_\$db.sql"
    log "Создание бэкапа базы данных \$db в файл \$backup_file"
    mysqldump -u root ${MYSQL_ROOT_PASSWORD:+-p"$MYSQL_ROOT_PASSWORD"} \$db > "\$backup_file" 2>> "\$LOG_FILE"
    if [ \$? -eq 0 ]; then
        log "Бэкап базы данных \$db успешно создан: \$backup_file"
    else
        error "Не удалось создать бэкап базы данных \$db"
    fi
done

# Удаление старых копий
log "Удаление старых резервных копий (оставляем последние \$backup_count)"
find "\$backup_path" -name "*.sql" -type f | sort -r | sed -n "\$backup_count,\\\$!p" | xargs rm -f >> "\$LOG_FILE" 2>&1

log "Резервное копирование завершено."
EOF

# Установка прав на выполнение скрипта
chmod +x "$backup_script" || error "Не удалось установить права на выполнение скрипта $backup_script"

# Добавление задания в cron (если оно еще не существует)
if ! crontab -l | grep -q "$backup_script"; then
    (crontab -l; echo "$cron_schedule $backup_script") | crontab -
    log "Задание добавлено в cron: $cron_schedule $backup_script"
else
    log "Задание уже существует в cron. Дублирование не произведено."
fi

log "Скрипт для бекапа создан: $backup_script"
log "Завершение работы скрипта."
