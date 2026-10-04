#!/bin/bash
#
# Run the regression tests in a temporary PostgreSQL instance with the
# pg_dbms_job background worker loaded. pg_dbms_job and pg_utl_smtp must be
# installed and the test SMTP server started (ci/start_smtp_server.sh).
#
# Environment: PG_CONFIG (default: pg_config), PGPORT (default: 55432)
#
set -u

cd "$(dirname "$0")/.." || exit 1
PG_CONFIG=${PG_CONFIG:-pg_config}
BINDIR=$("$PG_CONFIG" --bindir)
export PATH="$BINDIR:$PATH"

TMPDIR_CHECK="$PWD/tmp_check"
DATADIR="$TMPDIR_CHECK/data"
PGLOG="$TMPDIR_CHECK/postgresql.log"

# Connection used by psql in the tests. They are also inherited by the
# postmaster: the pg_dbms_job background worker opens its LISTEN libpq
# connection with the default connection parameters.
export PGHOST=/tmp PGPORT=${PGPORT:-55432} PGUSER=postgres
export PGDATABASE=postgres

# SSL/TLS settings of the tests, see ci/start_smtp_server.sh
export SMTPS_CA_FILE=${SMTPS_CA_FILE:-$TMPDIR_CHECK/certs/cert.pem}
export SMTPS_OTHER_CA_FILE=${SMTPS_OTHER_CA_FILE:-$TMPDIR_CHECK/certs/other_ca.pem}
export SMTPS_HOST=${SMTPS_HOST:-localhost}

mkdir -p "$TMPDIR_CHECK"
rm -rf "$DATADIR"
initdb -D "$DATADIR" -U postgres -A trust > "$TMPDIR_CHECK/initdb.log" 2>&1 || {
	cat "$TMPDIR_CHECK/initdb.log"; exit 1; }

cat >> "$DATADIR/postgresql.conf" <<EOC
port = $PGPORT
unix_socket_directories = '$PGHOST'
listen_addresses = ''
shared_preload_libraries = 'pg_dbms_job'
pg_dbms_job.database = 'regress_utl_smtp'
pg_dbms_job.username = 'postgres'
pg_dbms_job.job_queue_interval = 1
EOC

pg_ctl -D "$DATADIR" -l "$PGLOG" -w start > /dev/null || { cat "$PGLOG"; exit 1; }
trap 'pg_ctl -D "$DATADIR" -m fast -w stop > /dev/null' EXIT

psql -Atc "SELECT version()"

make installcheck PG_CONFIG="$PG_CONFIG"
rc=$?

if [ $rc -ne 0 ]; then
	for f in test/expected/*.out; do
		r="results/$(basename "$f")"
		[ -f "$r" ] && ! cmp -s "$f" "$r" && diff -u "$f" "$r"
	done
	echo "===== PostgreSQL log (last 100 lines)"
	tail -n 100 "$PGLOG"
	echo "===== SMTP server log"
	cat "$TMPDIR_CHECK/smtp_server.log" 2>/dev/null
fi
exit $rc
