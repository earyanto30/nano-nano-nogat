#!/usr/bin/env bash
#
# pg_backup.sh - PostgreSQL database backup script
#
# Usage:
#   ./pg_backup.sh --host <host:port> --database <db_name> --username <user> \
#                  --password <password> --retention <value><unit> --dump_path <path>
#
# Retention format:
#   <number>d  — days  (e.g. 7d = 7 days)
#   <number>h  — hours (e.g. 12h = 12 hours)
#
# Example:
#   ./pg_backup.sh --host 10.0.0.5:5432 --database myapp \
#                  --username backup_user --password s3cret \
#                  --retention 7d --dump_path /backups/myapp
#

set -euo pipefail

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
log_warn()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Required options:
  --host        <host:port>      PostgreSQL host and port (e.g. localhost:5432)
  --database    <db_name>        Database name to back up
  --username    <user>           PostgreSQL username
  --password    <password>       PostgreSQL password
  --retention   <value><unit>    Retention period (e.g. 7d for 7 days, 12h for 12 hours)
  --dump_path   <path>           Directory where dump files are stored

Optional:
  --format      <format>         pg_dump format: custom (default), plain, directory, tar
  -h, --help                     Show this help message
EOF
    exit 1
}

DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
RETENTION=""
DUMP_PATH=""
DUMP_FORMAT="custom"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            IFS=':' read -r DB_HOST DB_PORT <<< "$2"
            DB_PORT="${DB_PORT:-5432}"
            shift 2
            ;;
        --database)
            DB_NAME="$2"
            shift 2
            ;;
        --username)
            DB_USER="$2"
            shift 2
            ;;
        --password)
            DB_PASS="$2"
            shift 2
            ;;
        --retention)
            RETENTION="$2"
            shift 2
            ;;
        --dump_path)
            DUMP_PATH="$2"
            shift 2
            ;;
        --format)
            DUMP_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

MISSING=()
[[ -z "$DB_HOST"   ]] && MISSING+=("--host")
[[ -z "$DB_NAME"   ]] && MISSING+=("--database")
[[ -z "$DB_USER"   ]] && MISSING+=("--username")
[[ -z "$DB_PASS"   ]] && MISSING+=("--password")
[[ -z "$RETENTION" ]] && MISSING+=("--retention")
[[ -z "$DUMP_PATH" ]] && MISSING+=("--dump_path")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log_error "Missing required parameters: ${MISSING[*]}"
    usage
fi

parse_retention() {
    local value="${1}"
    local number="${value%[dhDH]}"
    local unit="${value: -1}"

    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        log_error "Invalid retention value: $value (expected format: <number>d or <number>h)"
        exit 1
    fi

    case "$unit" in
        d|D) echo $(( number * 24 * 60 )) ;;
        h|H) echo $(( number * 60 ))      ;;
        *)
            log_error "Invalid retention unit: '$unit' (use 'd' for days or 'h' for hours)"
            exit 1
            ;;
    esac
}

RETENTION_MINUTES=$(parse_retention "$RETENTION")
log_info "Retention period: $RETENTION ($RETENTION_MINUTES minutes)"

case "$DUMP_FORMAT" in
    custom)    DUMP_EXT="dump" ;;
    plain)     DUMP_EXT="sql"  ;;
    tar)       DUMP_EXT="tar"  ;;
    directory) DUMP_EXT="dir"  ;;
    *)
        log_error "Unsupported format: $DUMP_FORMAT"
        exit 1
        ;;
esac

if [[ ! -d "$DUMP_PATH" ]]; then
    log_info "Creating dump directory: $DUMP_PATH"
    mkdir -p "$DUMP_PATH"
fi

log_info "Checking database connectivity (host=$DB_HOST, port=$DB_PORT, database=$DB_NAME, user=$DB_USER)..."

export PGPASSWORD="$DB_PASS"

if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t 10 > /dev/null 2>&1; then
    log_error "Database is not available at $DB_HOST:$DB_PORT (database=$DB_NAME)"
    exit 1
fi

log_info "Database is available and accepting connections."

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DUMP_FILE="${DUMP_PATH}/${DB_NAME}_${TIMESTAMP}.${DUMP_EXT}"

log_info "Starting pg_dump (format=$DUMP_FORMAT)..."
log_info "Output: $DUMP_FILE"

DUMP_START=$(date +%s)

pg_dump \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -F "$DUMP_FORMAT" \
    -f "$DUMP_FILE" \
    --verbose 2>&1 | while IFS= read -r line; do
        log_info "  pg_dump: $line"
    done

DUMP_END=$(date +%s)
DUMP_DURATION=$(( DUMP_END - DUMP_START ))

if [[ "$DUMP_FORMAT" == "directory" ]]; then
    if [[ ! -d "$DUMP_FILE" ]]; then
        log_error "pg_dump failed — output directory was not created."
        exit 1
    fi
    DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
else
    if [[ ! -f "$DUMP_FILE" ]] || [[ ! -s "$DUMP_FILE" ]]; then
        log_error "pg_dump failed — output file is missing or empty."
        exit 1
    fi
    DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
fi

log_info "Dump completed successfully in ${DUMP_DURATION}s (size: $DUMP_SIZE)"

log_info "Checking for backups older than $RETENTION in $DUMP_PATH..."

OLD_FILES=()

if [[ "$DUMP_FORMAT" == "directory" ]]; then
    while IFS= read -r -d '' entry; do
        OLD_FILES+=("$entry")
    done < <(find "$DUMP_PATH" -maxdepth 1 -name "${DB_NAME}_*.${DUMP_EXT}" -type d -mmin +"$RETENTION_MINUTES" -print0 2>/dev/null)
else
    while IFS= read -r -d '' entry; do
        OLD_FILES+=("$entry")
    done < <(find "$DUMP_PATH" -maxdepth 1 -name "${DB_NAME}_*.${DUMP_EXT}" -type f -mmin +"$RETENTION_MINUTES" -print0 2>/dev/null)
fi

if [[ ${#OLD_FILES[@]} -eq 0 ]]; then
    log_info "No expired backups found. Nothing to clean up."
else
    log_info "Found ${#OLD_FILES[@]} expired backup(s):"
    for f in "${OLD_FILES[@]}"; do
        log_info "  - $(basename "$f")  (modified: $(stat -c '%y' "$f" 2>/dev/null || stat -f '%Sm' "$f" 2>/dev/null))"
    done

    log_info "Removing expired backups..."
    for f in "${OLD_FILES[@]}"; do
        if rm -rf "$f"; then
            log_info "  Removed: $(basename "$f")"
        else
            log_warn "  Failed to remove: $(basename "$f")"
        fi
    done
    log_info "Cleanup complete."
fi

unset PGPASSWORD
log_info "Backup process finished successfully."
log_info "  Database : $DB_NAME"
log_info "  Dump file: $DUMP_FILE"
log_info "  Size     : $DUMP_SIZE"
log_info "  Duration : ${DUMP_DURATION}s"
