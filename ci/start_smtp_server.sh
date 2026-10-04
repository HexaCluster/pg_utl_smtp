#!/bin/bash
#
# Start the test SMTP server used by the regression tests: plain SMTP on
# port 25 and SMTP over SSL/TLS on port 465 with a self-signed certificate
# generated in tmp_check/certs/. Requires the Python module aiosmtpd and
# root privileges (sudo is used when not run as root) to bind the ports.
#
set -eu

cd "$(dirname "$0")/.."
TMPDIR_CHECK="$PWD/tmp_check"
CERTDIR="$TMPDIR_CHECK/certs"
mkdir -p "$CERTDIR"

# Certificate of the test server and a CA that has not signed it
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
	-keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
	-subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
	-keyout "$CERTDIR/other_key.pem" -out "$CERTDIR/other_ca.pem" \
	-subj "/CN=other" 2>/dev/null

SUDO=
[ "$(id -u)" -ne 0 ] && SUDO=sudo

$SUDO nohup python3 test/smtp_test_server.py \
	--cert "$CERTDIR/cert.pem" --key "$CERTDIR/key.pem" \
	--maildir "$TMPDIR_CHECK/mails" > "$TMPDIR_CHECK/smtp_server.log" 2>&1 < /dev/null &

# Wait until both ports accept connections
for _ in $(seq 1 50); do
	if python3 -c "import socket; [socket.create_connection(('127.0.0.1', p), 1).close() for p in (25, 465)]" 2>/dev/null; then
		echo "Test SMTP server is listening on ports 25 and 465"
		exit 0
	fi
	sleep 0.2
done
echo "Test SMTP server failed to start:" >&2
cat "$TMPDIR_CHECK/smtp_server.log" >&2
exit 1
