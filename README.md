# pg_utl_smtp

PostgreSQL extension to add compatibility to Oracle UTL_SMTP package.

This extension uses `plperlu` stored procedures based on the `Net::SMTP` Perl module to provide the procedures of the UTL_SMTP package.

More information about the Oracle UTL_SMTP package can be found [here](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/UTL_SMTP.html)

* [Description](#description)
* [Installation](#installation)
* [Manage the extension](#manage-the-extension)
* [Procedures](#procedures)
  - [OPEN_CONNECTION](#open_connection)
  - [EHLO](#ehlo)
  - [HELO](#HELO)
  - [MAIL](#mail)
  - [RCPT](#rcpt)
  - [OPEN_DATA](#open_data)
  - [WRITE_DATA](#write_data)
  - [WRITE_RAW_DATA](#write_raw_data)
  - [CLOSE_DATA](#close_data)
  - [QUIT](#quit)
* [Asynchronous mode](#asynchronous-mode)
* [Example](#example)
* [Authors](#authors)
* [License](#license)

## [Description](#description)

This PostgreSQL extension provided compatibility with the UTL_SMTP Oracle package.
It implements the following routines:

* CLOSE_DATA: Closes the data session
* EHLO: Performs the initial handshake with SMTP server using the EHLO command
* HELO: Performs the initial handshake with SMTP server using the HELO command
* MAIL: Initiates an e-mail transaction with the server, the destination is a mailbox
* OPEN_CONNECTION: Opens a connection to an SMTP server
* OPEN_DATA: Sends the DATA command
* QUIT: Terminates an SMTP session and disconnects from the server
* RCPT: Specifies the recipient of an e-mail message
* WRITE_DATA: Writes a portion of the e-mail message
* WRITE_RAW_DATA: Writes a portion of the e-mail message with RAW data 

with some simplification.

* Only the procedures are implemented, not the functions
* The utl_tcp.crlf should be replaced by E`\r\n' or E'\n'
* The wallet_path parameter of the open_connection() function is not an Oracle wallet but a PEM file or a directory of CA certificates, wallet_password is not used.
* The secure_host parameter must be a host name, domain patterns like "*.example.com" are not supported.
* The UTL_SMTP.TRANSIENT_ERROR and UTL_SMTP.PERMANENT_ERROR exceptions are not implemented, an error returned by the SMTP server raises an error (SQLSTATE XX000) with the server reply code and message, for example `UTL_SMTP: RCPT <foo@example.com> failed: 550 5.1.1 user unknown`.

The following routines are not available yet:

* AUTH: Sends the AUTH command to authenticate to the SMTP server
* CLOSE_CONNECTION: Closes the SMTP connection, causing the current SMTP operation to terminate
* COMMAND: Performs a generic SMTP command
* COMMAND_REPLIES: Performs a generic SMTP command and retrieves multiple reply lines
* DATA: Sends the e-mail body
* HELP: Sends HELP command
* NOOP: NULL command
* RSET: Terminates the current e-mail transaction
* STARTTLS: Sends STARTTLS command to secure the SMTP connection using SSL/TLS
* VRFY: Verifies the validity of a destination e-mail address

## [Installation](#installation)

PostgreSQL >= 11 is required.

The Perl package Net::SMTP must be installed, as well as IO::Socket::SSL >= 2.007
to use SSL/TLS connections (`secure_connection_before_smtp => true`).
```
    sudo apt install libnet-smtp-ssl-perl libio-socket-ssl-perl
```
or
```
    sudo yum install perl-Net-SMTP-SSL perl-IO-Socket-SSL
```

To install the extension execute
```
    make
    sudo make install
```

The tests require a SMTP server listening on localhost port 25 and a
SMTP over SSL/TLS server (implicit TLS) on port 465. The simplest way is
to use the test SMTP server provided with the extension, it requires the
Python module aiosmtpd and must be run as root to bind ports 25 and 465:
```
    pip install aiosmtpd
    openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem \
        -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
    sudo python3 test/smtp_test_server.py --cert cert.pem --key key.pem
```
Accepted messages are written to directory /tmp/pg_utl_smtp_mails/. The
server refuses sender `badsender@...`, recipient `reject@...` and messages
containing `REJECTDATA`, these cases are used by `t/04_sync_errors.t`.

The following environment variables are used by the tests:

* SMTPS_CA_FILE: CA file used to verify the certificate of the server on port 465 (default: /etc/ssl/certs/ssl-cert-snakeoil.pem)
* SMTPS_HOST: name that must match the server certificate (default: output of `hostname -f`)
* SMTPS_OTHER_CA_FILE: CA file that has NOT signed the server certificate (default: /etc/ssl/certs/ca-certificates.crt)

With the test server above:
```
    export SMTPS_CA_FILE=$PWD/cert.pem SMTPS_HOST=localhost
```

A postfix server with a "Local only" configuration can be used for tests 01 to 03,
the smtps service must use implicit TLS in `/etc/postfix/master.cf`:
```
smtp      inet  n       -       y       -       -       smtpd
...
smtps     inet  n       -       y       -       -       smtpd
  -o smtpd_tls_wrappermode=yes
```

The asynchronous mode tests (`t/03_send_smtp_async.t`) also require the
[pg_dbms_job](https://github.com/MigOpsRepos/pg_dbms_job) extension >= 2.0
to be installed and its background worker attached to the test database,
in `postgresql.conf`:
```
shared_preload_libraries = 'pg_dbms_job'
pg_dbms_job.database = 'regress_utl_smtp'
pg_dbms_job.username = 'postgres'
```
The test database is not dropped between runs because terminating the
pg_dbms_job background worker would prevent it from being restarted.

Test of the extension can be run using:
```
    make installcheck
```
With postfix you may find the email sent into file /var/spool/mail/$USERNAME

## [Manage the extension](#manage-the-extension)

Each database that needs to use `pg_utl_smtp` must creates the extension as well
as the `plperlu` language.
```
    psql -d mydb -c "CREATE EXTENSION plperlu"
    psql -d mydb -c "CREATE EXTENSION pg_utl_smtp"
```

To upgrade to a new version execute:
```
    psql -d mydb -c 'ALTER EXTENSION pg_utl_smtp UPDATE TO "1.1.0"'
```

If you doesn't have the privileges to create an extension, you can just import
the extension file into the database, for example:

    psql -d mydb -c "CREATE SCHEMA utl_smtp;"
    psql -d mydb -f sql/pg_utl_smtp--1.1.0.sql

This is especially useful for database in DBaas cloud services.
To upgrade just import the extension upgrade files using psql.


## [Procedures](#procedures)

### [OPEN_CONNECTION](#open_connection)

This functions open a connection to an SMTP server.

Syntax:
```
UTL_SMTP.OPEN_CONNECTION (
   host                           IN  varchar, 
   port                           IN  integer DEFAULT 25, 
   tx_timeout                     IN  integer DEFAULT NULL,
   wallet_path                    IN  varchar DEFAULT NULL,
   wallet_password                IN  varchar DEFAULT NULL, 
   secure_connection_before_smtp  IN  boolean DEFAULT FALSE,
   secure_host                    IN  varchar DEFAULT NULL
) RETURN connection; 
```
Parameters:

- host: Name of the SMTP server host
- port: Port number on which SMTP server is listening (usually 25)
- tx_timeout: Maximum time, in seconds, to wait for a response from the SMTP server (NULL means default: 120) 
- wallet_path: PEM file containing the CA certificates, or directory of hashed PEM CA certificates (see `openssl rehash`), used to verify the SMTP server's certificate. An Oracle style `file:` prefix is accepted. If NULL the system default CA certificates are used. An error is raised if the path does not exist.
- wallet_password: Password to open the wallet. Not used.
- secure_connection_before_smtp: If TRUE, a secure connection with SSL/TLS is made before SMTP communication (implicit TLS, usually on port 465). The server certificate is always verified. If FALSE, no SSL/TLS is used.
- secure_host: The host name to be matched against the SMTP server's certificate when a secure connection is used. If NULL, the SMTP host name to connect to will be used. Domain patterns like "*.example.com" are not supported.

When the connection can not be established, including when the server
certificate can not be verified, a WARNING with the reason is emitted
and NULL is returned.

Returns a SMTP connection data type:
```
CREATE TYPE utl_smtp.connection AS (
        host              varchar(255),
        port              integer,
        tx_timeout        integer,
        private_tcp_con   integer, -- should be utl_tcp.connection but useless here
        private_state     integer
);
```

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  IF c.private_tcp_con IS NOT NULL THEN
    RAISE NOTICE 'Connection successful';
    ...
    CALL UTL_SMTP.QUIT(c);
  END IF;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Failed to send mail due to the following error: %', SQLERRM USING ERRCODE='08006';
END;
$$;
```

### [EHLO](#ehlo)

This procedure performs the initial handshake with SMTP server using the EHLO command. 

Syntax:
```
UTL_SMTP.EHLO (
   c       IN connection, 
   domain  IN varchar
);
```

Parameters:

- c: SMTP connection
- domain: Domain name of the local (sending) host. Used for identification purposes.

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.EHLO(c, 'darold.net');
  ...
END;
$$;
```

### [HELO](#helo)

This procedure performs the initial handshake with SMTP server using the HELO command. 

Syntax:
```
UTL_SMTP.HELO (
   c       IN connection, 
   domain  IN varchar
);
```

Parameters:

- c: SMTP connection
- domain: Domain name of the local (sending) host. Used for identification purposes.

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.HELO(c, 'darold.net');
  ...
END;
$$;
```

### [MAIL](#mail)

This procedure initiate a mail transaction with the server. The destination is a mailbox.

Syntax:
```
UTL_SMTP.MAIL (
   c           IN  connection, 
   sender      IN  varchar, 
   parameters  IN  varchar DEFAULT NULL
);
```

Parameters:

- c: SMTP connection
- sender: E-mail address of the user sending the message.
- parameters: Additional parameters to mail command as defined in Section 6 of [RFC1869]. It must follow the format of "XXX=XXX (XXX=XXX ....)". Not use.

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.MAIL(c, 'sender@example.com');
  ...
END;
$$;
```

### [RCPT](#rcpt)

This procedure specifies the recipient of an e-mail message.

Syntax:
```
UTL_SMTP.rcpt (
   c           IN  connection, 
   recipient   IN  varchar, 
   parameters  IN  varchar DEFAULT NULL
);
```

Parameters:

- c: SMTP connection
- recipient: E-mail address of the user to which the message is being sent.
- parameters: Additional parameters to mail command as defined in Section 6 of [RFC1869]. It must follow the format of "XXX=XXX (XXX=XXX ....)". Not use.

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.MAIL(c, 'sender@example.com');
  CALL UTL_SMTP.RCPT(c, 'to@example.com');
  ...
END;
$$;
```

### [OPEN_DATA](#opendata)

This procedure sends the DATA command after which you can use WRITE_DATA and WRITE_RAW_DATA to write a portion of the e-mail message. 

Syntax:
```
UTL_SMTP.OPEN_DATA (
   c     IN connection
);
```
Parameters:

- c: SMTP connection

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.MAIL(c, 'sender@example.com');
  CALL UTL_SMTP.RCPT(c, 'to@example.com');
  CALL UTL_SMTP.OPEN_DATA(c);
  ...
END;
$$;
```

### [WRITE_DATA](#write_data)

This procedure writes a portion of the e-mail message. A repeat call to WRITE_DATA appends data to the e-mail message. 

Syntax:
```
UTL_SMTP.WRITE_DATA (
   c     IN connection, 
   data  IN varchar
);
```
Parameters:

- c: SMTP connection
- data: Portion of the text of the message to be sent, including headers, in [RFC822] format

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.MAIL(c, 'sender@example.com');
  CALL UTL_SMTP.RCPT(c, 'to@example.com');
  CALL UTL_SMTP.OPEN_DATA(c);
  CALL UTL_SMTP.WRITE_DATA(c, 'From: "Gilles" <gilles@localhost>');
  CALL UTL_SMTP.WRITE_DATA(c, 'To: "Recipient" <gilles@localhost>');
  CALL UTL_SMTP.WRITE_DATA(c, 'Subject: Hello');
  CALL UTL_SMTP.WRITE_DATA(c, '');
  CALL UTL_SMTP.WRITE_DATA(c, 'Hello, world!');
  ...
END;
$$;
```

### [WRITE_RAW_DATA](#write_raw_data)

Same as the WRITE_DATA procedure.

### [CLOSE_DATA](#close_data)

This procedure ends the e-mail message by sending the sequence <CR><LF>.<CR><LF> (a single period at the beginning of a line). 

Syntax:
```
UTL_SMTP.CLOSE_DATA (
   c     IN connection
);
```
Parameters:

- c: SMTP connection

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.MAIL(c, 'sender@example.com');
  CALL UTL_SMTP.RCPT(c, 'to@example.com');
  CALL UTL_SMTP.OPEN_DATA(c);
  ...
  CALL UTL_SMTP.CLOSE_DATA(c);
  ...
END;
$$;
```

### [QUIT](#quit)

This proicedure terminates an SMTP session and disconnects from the server.

Syntax:
```
UTL_SMTP.QUIT (
   c     IN connection
);
```
Parameters:

- c: SMTP connection

Example:
```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  CALL UTL_SMTP.MAIL(c, 'sender@example.com');
  CALL UTL_SMTP.RCPT(c, 'to@example.com');
  CALL UTL_SMTP.OPEN_DATA(c);
  ...
  CALL UTL_SMTP.CLOSE_DATA(c);
  CALL UTL_SMTP.QUIT(c);
END;
$$;
```

## [Asynchronous mode](#asynchronous-mode)

By default the UTL_SMTP procedures talk to the SMTP server synchronously:
the calling session waits for the server and the message is sent even if
the transaction is rolled back afterward.

When the setting `pg_utl_smtp.asynchronous` is enabled, no SMTP connection
is made by the session. Each message is buffered and, when `CLOSE_DATA` is
called, it is stored into table `utl_smtp.mail_queue` and submitted as an
asynchronous job to [pg_dbms_job](https://github.com/MigOpsRepos/pg_dbms_job).
The pg_dbms_job background worker then replays the SMTP dialog.

```
SET pg_utl_smtp.asynchronous = on;   -- or in postgresql.conf, ALTER DATABASE/ROLE ... SET
```

The application code doesn't change. Behavior differences:

* The message is sent only if the transaction that called `CLOSE_DATA` commits.
* The mode is decided when `OPEN_CONNECTION` is called, changing the setting later has no effect on an open connection. The connection returned has `private_state = 1` in asynchronous mode.
* SMTP errors (refused recipient, unreachable server, ...) can not be reported to the caller. They are recorded in `utl_smtp.mail_queue` (`status = 'failed'`, `last_error`) and logged as a WARNING in the server log. The pg_dbms_job run history reports the job as successful in this case, `utl_smtp.mail_queue` is the reference for the sending status.
* Command order is checked at call time: `RCPT` before `MAIL`, `OPEN_DATA` without recipient or `WRITE_DATA` outside a DATA session raise an error.
* If a recipient is refused by the server the whole message fails, it is not sent to the other recipients.
* A message whose DATA session is not closed before `QUIT` is discarded with a WARNING.
* The SMTP connection is made with the same options as in synchronous mode, including SSL/TLS. The SSL/TLS settings are validated when `OPEN_CONNECTION` is called and stored with the message.

Requirements:

* pg_dbms_job must be installed in the database. With pg_dbms_job >= 2.0 the background worker processes the jobs of the database set in `pg_dbms_job.database` only, `OPEN_CONNECTION` raises an error if the current database is different.
* Jobs are executed with the role that queued the message, it needs the following privileges in addition to the pg_dbms_job ones:
```
GRANT USAGE ON SCHEMA utl_smtp TO app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA utl_smtp TO app;
GRANT SELECT, INSERT, UPDATE ON utl_smtp.mail_queue TO app;
GRANT USAGE ON SEQUENCE utl_smtp.mail_queue_id_seq TO app;
```

Row level security on `utl_smtp.mail_queue` restricts each role to the
messages it has queued. Columns of interest are `status` (`queued`, `sent`,
`failed`), `attempts`, `last_attempt`, `sent_date`, `last_error` and `job_id`.

pg_dbms_job does not retry a failed asynchronous job. A failed message can
be submitted again with:
```
SELECT utl_smtp.async_resend(id) FROM utl_smtp.mail_queue WHERE status = 'failed';
```

Table `utl_smtp.mail_queue` is not purged automatically, for example:
```
DELETE FROM utl_smtp.mail_queue WHERE status = 'sent' AND sent_date < now() - '30 days'::interval;
```

## [Example](#example)

```
DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost');
  IF c.private_tcp_con IS NOT NULL THEN
    CALL UTL_SMTP.HELO(c, 'darold.net');
    CALL UTL_SMTP.MAIL(c, 'gilles');
    CALL UTL_SMTP.RCPT(c, 'gilles@localhost');
    CALL UTL_SMTP.OPEN_DATA(c);
    CALL UTL_SMTP.WRITE_DATA(c, 'From: "Gilles" <gilles@localhost>');
    CALL UTL_SMTP.WRITE_DATA(c, 'To: "Recipient" <gilles@localhost>');
    CALL UTL_SMTP.WRITE_DATA(c, 'Subject: Hello');
    CALL UTL_SMTP.WRITE_DATA(c, '');
    CALL UTL_SMTP.WRITE_DATA(c, 'Hello, world!');
    CALL UTL_SMTP.CLOSE_DATA(c);
    CALL UTL_SMTP.QUIT(c);
  END IF;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Failed to send mail due to the following error: %', SQLERRM USING ERRCODE='08006';
END;
$$;

```

## [Authors](#authors)

- Gilles Darold

## [License](#license)

This extension is free software distributed under the PostgreSQL License.

    Copyright (c) 2023-2026 HexaCluster Corp.

