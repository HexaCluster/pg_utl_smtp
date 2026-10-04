#!/usr/bin/env python3
#
# SMTP server for the regression tests of pg_utl_smtp (requires aiosmtpd).
#
#   - plain SMTP on port 25 and SMTP over SSL/TLS (implicit TLS) on port 465
#   - refuses sender "badsender@...", recipient "reject@..." and messages
#     containing "REJECTDATA"
#   - accepted messages are written to the directory given with --maildir
#
# Usage (as root to bind ports 25 and 465):
#   openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem \
#       -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
#   python3 test/smtp_test_server.py --cert cert.pem --key key.pem
#   SMTPS_CA_FILE=$PWD/cert.pem SMTPS_HOST=localhost \
#       SMTPS_OTHER_CA_FILE=/etc/ssl/certs/ca-certificates.crt make installcheck
import argparse, os, signal, ssl, time
from aiosmtpd.controller import Controller

class Handler:
    def __init__(self, port, maildir):
        self.port, self.maildir = port, maildir
    async def handle_MAIL(self, server, session, envelope, address, mail_options):
        if address.startswith('badsender'):
            return '550 5.7.1 sender refused'
        envelope.mail_from = address
        return '250 OK'
    async def handle_RCPT(self, server, session, envelope, address, rcpt_options):
        if address.startswith('reject'):
            return '550 5.1.1 user unknown'
        envelope.rcpt_tos.append(address)
        return '250 OK'
    async def handle_DATA(self, server, session, envelope):
        body = envelope.content.decode('utf8', 'replace')
        if 'REJECTDATA' in body:
            return '554 5.6.0 message content rejected'
        with open(os.path.join(self.maildir, '%d.eml' % time.time_ns()), 'w') as f:
            f.write('X-Port: %d\nX-Env-From: %s\nX-Env-To: %s\n'
                    % (self.port, envelope.mail_from, ','.join(envelope.rcpt_tos)))
            f.write(body)
        return '250 OK'

p = argparse.ArgumentParser()
p.add_argument('--cert', required=True)
p.add_argument('--key', required=True)
p.add_argument('--maildir', default='/tmp/pg_utl_smtp_mails')
a = p.parse_args()
os.makedirs(a.maildir, exist_ok=True)
ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
ctx.load_cert_chain(a.cert, a.key)
servers = [Controller(Handler(25, a.maildir), hostname='127.0.0.1', port=25),
           Controller(Handler(465, a.maildir), hostname='127.0.0.1', port=465, ssl_context=ctx)]
for s in servers:
    s.start()
signal.pause()
