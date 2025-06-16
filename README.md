# pg_utl_smtp

PostgreSQL extension to add compatibility to Oracle UTL_SMTP package.

This extension uses `plperlu` stored procedures using Net::SMTP to provide the procedures of the UTL_SMTP package.

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
* The wallet_path and wallet_password of the open_connection() function are not used.
* The UTL_SMTP.TRANSIENT_ERROR and UTL_SMTP.PERMANENT_ERROR exceptions are not implemented

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

The Perl package Net::SMTP must be installed.
```
    sudo apt install libnet-smtp-ssl-perl
```
or
```
    sudo yum install perl-Net-SNMP
```

To install the extension execute
```
    make
    sudo make install
```

To be able to run the tests, postfix must be installed with a "Local only" configuration.
```
    sudo apt install postfix
```
You also need to configure postfix using the following settings in file `/etc/postfix/master.cf`
```
smtp      inet  n       -       y       -       -       smtpd
...
smtps     inet  n       -       y       -       -       smtpd
```
and to create a system user named gilles. If you want to use an existing system user you can
change the tests to use this username with command:
```
grep -rl gilles test/ | xargs -i perl -p -i -e 's/gilles/username/' {}
```

Test of the extension can be run using:
```
    make installcheck
```

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
    psql -d mydb -f sql/pg_utl_smtp--1.0.0.sql

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
- wallet_path: Directory path that contains the Oracle wallet for SSL/TLS. Not used.
- wallet_password: Password to open the wallet. Not used.
- secure_connection_before_smtp: If TRUE, a secure connection with SSL/TLS is made before SMTP communication. If FALSE, no connection is made.
- secure_host: The host name to be matched against the common name (CN) of the SMTP server's certificate when a secure connection is used. It can also be a domain name like "*.example.com".  If NULL, the SMTP host name to connect to will be used. 

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

    Copyright (c) 2023-2025 HexaCluster Corp.

