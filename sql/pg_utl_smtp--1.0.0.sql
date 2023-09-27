----
-- Script to create the base objects of the pg_utl_smtp extension
----

CREATE TYPE utl_smtp.connection AS (
	host              varchar(255),
	port              integer,
	tx_timeout        integer, 
	private_tcp_con   integer, -- utl_tcp.connection,
	private_state     integer
);

CREATE FUNCTION utl_smtp.open_connection (
	host                           IN  varchar,
	port                           IN  integer DEFAULT 25,
	tx_timeout                     IN  integer DEFAULT NULL,
	wallet_path                    IN  varchar DEFAULT NULL,
	wallet_password                IN  varchar DEFAULT NULL,
	secure_connection_before_smtp  IN  boolean DEFAULT FALSE,
	secure_host                    IN  varchar DEFAULT NULL
) RETURNS utl_smtp.connection
    LANGUAGE plperlu
    AS $code$

	use Net::SMTP;

	my ($host, $port, $tx_timeout, $wallet_path, $wallet_password, $secure_connection_before_smtp, $secure_host) = @_;

	my $ssl = ($secure_connection_before_smtp eq 'f') ? false : true;
	$tx_timeout ||= 3;
	$port ||= ($secure_connection_before_smtp) ? 465 : 25;

#	$_SHARED{ 'smtp' }{$$} = Net::SMTP->new(  $host,
#					Timeout => $tx_timeout,
#					Port => $port,
#					SSL => $ssl,
#					SendHello => false
#				);
	$_SHARED{ 'smtp' }{ $$ } = Net::SMTP->new(  $host,
					Timeout => $tx_timeout,
					Port => $port,
					SendHello => false
				);
	if (defined $_SHARED{ 'smtp' }{ $$ })
	{
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

CREATE PROCEDURE utl_smtp.ehlo (c INOUT utl_smtp.connection, domain IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $domain) = @_;

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->hello($domain);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.ehlo (c INOUT utl_smtp.connection, domain IN varchar)
    IS 'Performs the initial handshake with SMTP server using the EHLO command and return the reply of the command (see type utl_smtp.reply).';
REVOKE ALL ON PROCEDURE utl_smtp.ehlo FROM PUBLIC;

CREATE PROCEDURE utl_smtp.helo (c IN utl_smtp.connection, domain IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $domain) = @_;


	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->hello($domain);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.helo (c IN utl_smtp.connection, domain IN varchar)
    IS 'Performs the initial handshake with SMTP server using the HELO command and return the reply of the command (see type utl_smtp.reply).';
REVOKE ALL ON PROCEDURE utl_smtp.helo FROM PUBLIC;

CREATE PROCEDURE utl_smtp.mail (c IN utl_smtp.connection, sender IN varchar, parameters IN varchar DEFAULT NULL)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $sender, $parameters) = @_;

	if ($parameters) {
		elog(WARNING, "UTL_SMTP parameters are not supported by the mail() procedure, they will not be used: \"$parameters\"")
	}

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->mail($sender);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.mail (c IN utl_smtp.connection, sender IN varchar, parameters IN varchar)
    IS 'Initiate a mail transaction with the server. The destination is a mailbox.';
REVOKE ALL ON PROCEDURE utl_smtp.mail FROM PUBLIC;

CREATE PROCEDURE utl_smtp.rcpt (c IN utl_smtp.connection, recipient IN varchar, parameters IN varchar DEFAULT NULL)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $recipient, $parameters) = @_;

	if ($parameters) {
		elog(WARNING, "UTL_SMTP parameters are not supported by the rcpt() procedure, they will not be used: \"$parameters\"")
	}

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->recipient($recipient);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.rcpt (c IN utl_smtp.connection, recipient varchar, parameters varchar)
    IS 'Specifies the recipient of an e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.rcpt FROM PUBLIC;

CREATE PROCEDURE utl_smtp.quit (c IN utl_smtp.connection)
    LANGUAGE plperlu
    AS $code$
	my ($conn) = @_;

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->quit();
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.quit (c IN utl_smtp.connection)
    IS 'Terminates an SMTP session and disconnects from the server.';
REVOKE ALL ON PROCEDURE utl_smtp.quit FROM PUBLIC;

CREATE PROCEDURE utl_smtp.open_data (c IN utl_smtp.connection)
    LANGUAGE plperlu
    AS $code$
	my ($conn) = @_;

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->data();
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.open_data (c INOUT utl_smtp.connection)
    IS 'Sends the DATA command after which you can use write_data() and write_raw_data() to write a portion of the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.open_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.write_data (c IN utl_smtp.connection, data IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $data) = @_;

	chomp($data);
	$data .= "\n";

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->datasend($data);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.write_data (c IN utl_smtp.connection, data varchar)
    IS 'Writes a portion of the e-mail message. A repeat call to write_data() appends data to the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.write_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.write_raw_data (c IN utl_smtp.connection, data IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $data) = @_;

	chomp($data);
	$data .= "\n";

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->datasend($data);
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.write_raw_data (c IN utl_smtp.connection, data varchar)
    IS 'Writes a portion of the e-mail message. A repeat call to write_raw_data() appends data to the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.write_raw_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.close_data (c IN utl_smtp.connection)
    LANGUAGE plperlu
    AS $code$
	my ($conn) = @_;

	if (exists $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }) {
		$_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} }->dataend();
	} else {
		elog(ERROR, "no SMTP connection defined");
	}

$code$;
COMMENT ON PROCEDURE utl_smtp.close_data (c IN utl_smtp.connection)
    IS 'Sends the e-mail message by sending a single period at the beginning of a line.';
REVOKE ALL ON PROCEDURE utl_smtp.close_data FROM PUBLIC;

