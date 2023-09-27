----
-- Script to create the base objects of the pg_utl_smtp extension
----
CREATE EXTENSION plperl;

CREATE SCHEMA utl_tcp;

CREATE TYPE utl_tcp.connection AS (
	remote_host    varchar(255),
	remote_port    integer,
	local_host     varchar(255),
	local_port     integer,
	charset        varchar(30),
	newline        varchar(2),
	tx_timeout     integer,
	private_sd     integer
);

-- FIXME:utl_tcp.open_connection and utl_tcp.close_connection instead of the utl_smp ones
-- portnet_export/schema/packages/edipck_mail/html_email_package.sql
-- FIXME: utl_smtp.transient_error or utl_smtp.permanent_error
-- portnet_export/schema/packages/edipck_mail/pr_envia_mail_package.sql

CREATE SCHEMA utl_smtp;

CREATE TYPE utl_smtp.connection AS (
	host              varchar(255),
	port              integer,
	tx_timeout        integer, 
	private_tcp_con   utl_tcp.connection,
	private_state     integer
);

CREATE TYPE utl_smtp.reply AS (
	code    integer,
	text    varchar(508)
);

CREATE TYPE utl_smtp.replies AS (replies utl_smtp.reply[]);

CREATE FUNCTION utl_tcp.open_connection (
	host                           IN  varchar,
	port                           IN  integer DEFAULT 25,
	tx_timeout                     IN  integer DEFAULT NULL,
	wallet_path                    IN  varchar DEFAULT NULL,
	wallet_password                IN  varchar DEFAULT NULL,
	secure_connection_before_smtp  IN  boolean DEFAULT FALSE,
	secure_host                    IN  varchar DEFAULT NULL
) RETURNS utl_tcp.connection
    LANGUAGE plperl
    AS $code$

	use Net::SMTP;

	my ($host, $port, $tx_timeout, $wallet_path, $wallet_password, $secure_connection_before_smtp, $secure_host) = @_;

	my $ssl = ($secure_connection_before_smtp eq 'f') ? false : true;
	$tx_timeout ||= 3;
	$port ||= ($secure_connection_before_smtp) ? 465 : 25;

	elog(WARNING, "Opening SMTP connection on $host port $port, SSL => $ssl"); 
#	$_SHARED{$$} = Net::SMTP->new(  $host,
#					Timeout => $tx_timeout,
#					Port => $port,
#					SSL => $ssl,
#					SendHello => false
#				);
	$_SHARED{$$} = Net::SMTP->new(  $host,
					Timeout => $tx_timeout,
					Port => $port,
					SendHello => false
				);
	if (defined $_SHARED{$$})
	{
		elog(WARNING, "SMTP connection opened with handle: $$"); 
		return {
				host => $host,
				port => $port,
				tx_timeout => $tx_timeout,
				private_tcp_con => $$,
				private_state => 0
			};
	}
	elog(WARNING, "can not open a SMTP connection"); 

	return undef;
$code$;
COMMENT ON FUNCTION utl_smtp.open_connection(varchar, integer, integer, varchar, varchar, boolean, varchar)
    IS 'Open a connection to an SMTP server. Returns the connection (see data type utl_smtp.connection).';
REVOKE ALL ON FUNCTION utl_smtp.open_connection FROM PUBLIC;

CREATE FUNCTION utl_smtp.open_connection (
	host                           IN  varchar,
	port                           IN  integer DEFAULT 25,
	tx_timeout                     IN  integer DEFAULT NULL,
	wallet_path                    IN  varchar DEFAULT NULL,
	wallet_password                IN  varchar DEFAULT NULL,
	secure_connection_before_smtp  IN  boolean DEFAULT FALSE,
	secure_host                    IN  varchar DEFAULT NULL
) RETURNS utl_smtp.connection
    LANGUAGE plpgsql
    AS $$
DECLARE
    l_connection    utl_smtp.connection;
    v_conn_tcp      utl_tcp.connection;
BEGIN
    v_conn_tcp := utl_tcp.open_connection(remote_host => host, remote_port => port, charset => 'AL32UTF8');

    l_connection.host            := v_conn_tcp.remote_host;
    l_connection.port            := v_conn_tcp.remote_port;
    l_connection.tx_timeout      := v_conn_tcp.tx_timeout;
    l_connection.private_state   := NULL;
    l_connection.private_tcp_con := v_conn_tcp;

	use Net::SMTP;

#	$_SHARED{$$} = Net::SMTP->new(  $host,
#					Timeout => $tx_timeout,
#					Port => $port,
#					SSL => $ssl,
#					SendHello => false
#				);

    RETURN l_connection;
END
$$;
COMMENT ON FUNCTION utl_smtp.open_connection(varchar, integer, integer, varchar, varchar, boolean, varchar)
    IS 'Open a connection to an SMTP server. Returns the connection (see data type utl_smtp.connection).';
REVOKE ALL ON FUNCTION utl_smtp.open_connection FROM PUBLIC;


CREATE PROCEDURE utl_smtp.ehlo (c INOUT utl_smtp.connection, domain IN varchar)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->hello($_[1]);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.ehlo (c INOUT utl_smtp.connection, domain IN varchar)
    IS 'Performs the initial handshake with SMTP server using the EHLO command and return the reply of the command (see type utl_smtp.reply).';
REVOKE ALL ON PROCEDURE utl_smtp.ehlo FROM PUBLIC;

CREATE PROCEDURE utl_smtp.helo (c INOUT utl_smtp.connection, domain IN varchar)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->hello($_[1]);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.helo (c INOUT utl_smtp.connection, domain IN varchar)
    IS 'Performs the initial handshake with SMTP server using the HELO command and return the reply of the command (see type utl_smtp.reply).';
REVOKE ALL ON PROCEDURE utl_smtp.helo FROM PUBLIC;

CREATE PROCEDURE utl_smtp.mail (c INOUT utl_smtp.connection, sender IN varchar, parameters IN varchar DEFAULT NULL)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->mail($_[1], $_[2]);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.mail (c INOUT utl_smtp.connection, sender IN varchar, parameters IN varchar)
    IS 'Initiate a mail transaction with the server. The destination is a mailbox.';
REVOKE ALL ON PROCEDURE utl_smtp.mail FROM PUBLIC;

CREATE PROCEDURE utl_smtp.rcpt (c INOUT utl_smtp.connection, recipient IN varchar, parameters IN varchar DEFAULT NULL)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->recipient($_[1], $_[2]);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.rcpt (c INOUT utl_smtp.connection, recipient varchar, parameters varchar)
    IS 'Specifies the recipient of an e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.rcpt FROM PUBLIC;

CREATE PROCEDURE utl_smtp.quit (c INOUT utl_smtp.connection)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->quit();
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.quit (c INOUT utl_smtp.connection)
    IS 'Terminates an SMTP session and disconnects from the server.';
REVOKE ALL ON PROCEDURE utl_smtp.quit FROM PUBLIC;

CREATE PROCEDURE utl_smtp.open_data (c INOUT utl_smtp.connection)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->data();
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.open_data (c INOUT utl_smtp.connection)
    IS 'Sends the DATA command after which you can use write_data() and write_raw_data() to write a portion of the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.open_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.write_data (c INOUT utl_smtp.connection, data IN varchar)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->datasend($_[1]);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.write_data (c INOUT utl_smtp.connection, data varchar)
    IS 'Writes a portion of the e-mail message. A repeat call to write_data() appends data to the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.write_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.write_raw_data (c INOUT utl_smtp.connection, data IN varchar)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->datasend($_[1]);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.write_raw_data (c INOUT utl_smtp.connection, data varchar)
    IS 'Writes a portion of the e-mail message. A repeat call to write_raw_data() appends data to the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.write_raw_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.close_data (c INOUT utl_smtp.connection)
    LANGUAGE plperl
    AS $code$

	if (defined $_SHARED{$$}) {
		$_SHARED{$$}->dataend();
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.close_data (c INOUT utl_smtp.connection)
    IS 'Sends the e-mail message by sending the sequence <CR><LF>.<CR><LF> (a single period at the beginning of a line) and return the reply of the command (see type utl_smtp.reply). In cases where there are multiple replies, the last reply is returned.';
REVOKE ALL ON PROCEDURE utl_smtp.close_data FROM PUBLIC;

