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

----
-- Asynchronous mode (pg_utl_smtp.asynchronous = on)
--
-- When the setting is enabled at open_connection() time, the SMTP
-- dialog is not executed. Each message is buffered in the session
-- and, at close_data(), stored into utl_smtp.mail_queue and submitted
-- to pg_dbms_job as an asynchronous job that replays the SMTP dialog.
-- As dbms_job.submit() is transactional, a message is only sent if
-- the transaction that produced it commits.
----

CREATE TABLE utl_smtp.mail_queue (
	id            bigserial PRIMARY KEY, -- identifier of the queued message
	owner         name NOT NULL DEFAULT current_user, -- role that queued the message
	create_date   timestamp with time zone NOT NULL DEFAULT current_timestamp,
	host          varchar(255) NOT NULL, -- SMTP server
	port          integer NOT NULL,
	tx_timeout    integer NOT NULL,
	secure        boolean NOT NULL DEFAULT false, -- SSL/TLS connection (secure_connection_before_smtp)
	secure_host   varchar, -- name matched against the server certificate
	wallet_path   varchar, -- CA certificate file or directory
	helo_domain   varchar, -- domain given to HELO/EHLO, NULL if not called
	sender        varchar NOT NULL, -- MAIL FROM
	recipients    varchar[] NOT NULL, -- RCPT TO list
	data          text NOT NULL, -- message (headers + body) as written by write_data()
	status        text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'failed')),
	job_id        bigint, -- last pg_dbms_job job id used to send the message
	attempts      integer NOT NULL DEFAULT 0,
	last_attempt  timestamp with time zone,
	sent_date     timestamp with time zone,
	last_error    text
);
CREATE INDEX ON utl_smtp.mail_queue (status);
COMMENT ON TABLE utl_smtp.mail_queue
    IS 'Messages queued by UTL_SMTP in asynchronous mode and their sending status.';
ALTER TABLE utl_smtp.mail_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY utl_smtp_mail_queue_policy ON utl_smtp.mail_queue USING (owner = current_user);
REVOKE ALL ON utl_smtp.mail_queue FROM PUBLIC;
REVOKE ALL ON SEQUENCE utl_smtp.mail_queue_id_seq FROM PUBLIC;
SELECT pg_catalog.pg_extension_config_dump('utl_smtp.mail_queue', '');
SELECT pg_catalog.pg_extension_config_dump('utl_smtp.mail_queue_id_seq', '');

CREATE FUNCTION utl_smtp.init_perl ()
    RETURNS void
    LANGUAGE plperlu
    AS $code$

	use Net::SMTP;

	return if (exists $_SHARED{ 'utl_smtp_check' });

	# Returns the IO::Socket::SSL options to use for a connection, die on
	# invalid settings. Used by open_connection() and async_send() so that
	# a queued message is sent with the same options as a synchronous one.
	$_SHARED{ 'utl_smtp_ssl_opts' } = sub {
		my ($secure, $secure_host, $wallet_path) = @_;

		return () if (!$secure);

		eval { require IO::Socket::SSL; IO::Socket::SSL->VERSION(2.007); 1; }
			or die "UTL_SMTP: SSL/TLS connection requires the Perl module IO::Socket::SSL >= 2.007\n";

		my %opt = ( SSL => 1 );
		$opt{SSL_verifycn_name} = $secure_host if (defined $secure_host && $secure_host ne '');
		if (defined $wallet_path && $wallet_path ne '') {
			(my $p = $wallet_path) =~ s/^file://i;
			if (-d $p) {
				$opt{SSL_ca_path} = $p;
			} elsif (-f $p) {
				$opt{SSL_ca_file} = $p;
			} else {
				die "UTL_SMTP: wallet_path \"$wallet_path\" is not a CA certificate file or directory\n";
			}
		}
		return %opt;
	};

	# Opens a SMTP connection, die with the reason on failure
	$_SHARED{ 'utl_smtp_connect' } = sub {
		my ($host, $port, $tx_timeout, %ssl) = @_;

		my $smtp = Net::SMTP->new( $host,
					Timeout => $tx_timeout,
					Port => $port,
					SendHello => 0,
					%ssl
				);
		if (!defined $smtp) {
			my $err = $@ || '';
			if ($ssl{SSL} && IO::Socket::SSL::errstr() && index($err, IO::Socket::SSL::errstr()) < 0) {
				$err .= ($err ? ': ' : '') . IO::Socket::SSL::errstr();
			}
			$err =~ s/\s+$//;
			die "can not open a SMTP connection to $host:$port" . ($err ? ": $err" : '') . "\n";
		}
		return $smtp;
	};

	# Checks the result of a SMTP command, die with the server reply on failure
	$_SHARED{ 'utl_smtp_check' } = sub {
		my ($smtp, $res, $cmd) = @_;

		return 1 if ($res);
		my $msg = $smtp->message() // '';
		$msg =~ s/\s+$//;
		$msg =~ s/\s*\n\s*/ /g;
		die "UTL_SMTP: $cmd failed: " . ($smtp->code() // '') . " $msg\n";
	};

$code$;
COMMENT ON FUNCTION utl_smtp.init_perl()
    IS 'Internal: defines the Perl helpers shared by the UTL_SMTP routines.';
REVOKE ALL ON FUNCTION utl_smtp.init_perl FROM PUBLIC;

CREATE FUNCTION utl_smtp.async_submit (mail_id IN bigint)
    RETURNS bigint
    LANGUAGE plpgsql
    AS $code$
DECLARE
	jid bigint;
BEGIN
	IF to_regprocedure('dbms_job.submit(text,timestamp with time zone,text,boolean)') IS NULL THEN
		RAISE EXCEPTION 'UTL_SMTP asynchronous mode requires the pg_dbms_job extension in database "%"', current_database();
	END IF;
	jid := dbms_job.submit(format('PERFORM utl_smtp.async_send(%s);', mail_id));
	UPDATE utl_smtp.mail_queue SET job_id = jid WHERE id = mail_id;
	RETURN jid;
END;
$code$;
COMMENT ON FUNCTION utl_smtp.async_submit(bigint)
    IS 'Internal: submit a pg_dbms_job asynchronous job to send a queued message. Returns the job id.';
REVOKE ALL ON FUNCTION utl_smtp.async_submit FROM PUBLIC;

CREATE FUNCTION utl_smtp.async_send (mail_id IN bigint)
    RETURNS boolean
    LANGUAGE plperlu
    AS $code$

	my ($mail_id) = @_;

	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });

	my $sel = spi_prepare('SELECT * FROM utl_smtp.mail_queue WHERE id = $1 AND status = $2 FOR UPDATE SKIP LOCKED', 'bigint', 'text');
	my $rv = spi_exec_prepared($sel, $mail_id, 'queued');
	spi_freeplan($sel);
	if ($rv->{processed} == 0) {
		elog(WARNING, "UTL_SMTP: queued message $mail_id not found, locked or not in queued state, skipping");
		return 0;
	}
	my $m = $rv->{rows}[0];

	my $smtp;
	my $err;
	eval {
		my $chk = $_SHARED{ 'utl_smtp_check' };
		my %ssl = $_SHARED{ 'utl_smtp_ssl_opts' }->($m->{secure} eq 't', $m->{secure_host}, $m->{wallet_path});
		$smtp = $_SHARED{ 'utl_smtp_connect' }->($m->{host}, $m->{port}, $m->{tx_timeout}, %ssl);

		$chk->($smtp, $smtp->hello($m->{helo_domain}), 'HELO') if (defined $m->{helo_domain});
		$chk->($smtp, $smtp->mail($m->{sender}), 'MAIL');
		foreach my $r (@{ $m->{recipients} }) {
			$chk->($smtp, $smtp->recipient($r), "RCPT <$r>");
		}
		$chk->($smtp, $smtp->data(), 'DATA');
		$chk->($smtp, $smtp->datasend($m->{data}), 'DATA (write)');
		$chk->($smtp, $smtp->dataend(), 'DATA (end)');
		1;
	} or do {
		$err = $@ || 'unknown error';
		$err =~ s/^UTL_SMTP: //;
		chomp($err);
	};
	$smtp->quit() if (defined $smtp);

	my $upd = spi_prepare(q{UPDATE utl_smtp.mail_queue
			SET status = $2, attempts = attempts + 1, last_attempt = clock_timestamp(),
			    sent_date = CASE WHEN $2 = 'sent' THEN clock_timestamp() END,
			    last_error = $3
			WHERE id = $1}, 'bigint', 'text', 'text');
	spi_exec_prepared($upd, $mail_id, (defined $err) ? 'failed' : 'sent', $err);
	spi_freeplan($upd);

	if (defined $err) {
		elog(WARNING, "UTL_SMTP: failed to send queued message $mail_id: $err");
		return 0;
	}
	return 1;
$code$;
COMMENT ON FUNCTION utl_smtp.async_send(bigint)
    IS 'Internal: executed by pg_dbms_job to replay the SMTP dialog of a queued message. Returns true when the message was accepted by the server.';
REVOKE ALL ON FUNCTION utl_smtp.async_send FROM PUBLIC;

CREATE FUNCTION utl_smtp.async_resend (mail_id IN bigint)
    RETURNS bigint
    LANGUAGE plpgsql
    AS $code$
BEGIN
	UPDATE utl_smtp.mail_queue SET status = 'queued' WHERE id = mail_id AND status = 'failed';
	IF NOT FOUND THEN
		RAISE EXCEPTION 'queued message % does not exist or is not in failed state', mail_id;
	END IF;
	RETURN utl_smtp.async_submit(mail_id);
END;
$code$;
COMMENT ON FUNCTION utl_smtp.async_resend(bigint)
    IS 'Submit again a message whose asynchronous sending has failed. Returns the new pg_dbms_job job id.';
REVOKE ALL ON FUNCTION utl_smtp.async_resend FROM PUBLIC;

----
-- UTL_SMTP routines
----

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

	my ($host, $port, $tx_timeout, $wallet_path, $wallet_password, $secure_connection_before_smtp, $secure_host) = @_;

	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });

	# boolean arguments are received as 't' or 'f'
	my $secure = (defined $secure_connection_before_smtp && $secure_connection_before_smtp eq 't') ? 1 : 0;
	$tx_timeout ||= 3;
	$port ||= ($secure) ? 465 : 25;

	# Validate the SSL/TLS settings, raise an error when they are invalid
	my %ssl = $_SHARED{ 'utl_smtp_ssl_opts' }->($secure, $secure_host, $wallet_path);

	# Asynchronous mode is decided once, when the connection is opened
	my $async = 0;
	my $rv = spi_exec_query("SELECT coalesce(nullif(current_setting('pg_utl_smtp.asynchronous', true), ''), 'off') AS v");
	my $setting = $rv->{rows}[0]{v};
	if ($setting =~ /^\s*(on|true|yes|1|t|y)\s*$/i) {
		$async = 1;
	} elsif ($setting !~ /^\s*(off|false|no|0|f|n)\s*$/i) {
		elog(ERROR, "invalid value for parameter \"pg_utl_smtp.asynchronous\": \"$setting\"");
	}

	if ($async)
	{
		$rv = spi_exec_query("SELECT to_regprocedure('dbms_job.submit(text,timestamp with time zone,text,boolean)') IS NOT NULL AS ok, current_setting('pg_dbms_job.database', true) AS jobdb, current_database() AS curdb");
		my $r = $rv->{rows}[0];
		if ($r->{ok} ne 't') {
			elog(ERROR, "UTL_SMTP asynchronous mode requires the pg_dbms_job extension in database \"$r->{curdb}\"");
		}
		# pg_dbms_job >= 2.0 background worker only processes jobs of one database
		if (defined $r->{jobdb} && $r->{jobdb} ne '' && $r->{jobdb} ne $r->{curdb}) {
			elog(ERROR, "UTL_SMTP asynchronous mode: pg_dbms_job.database is \"$r->{jobdb}\", queued messages of database \"$r->{curdb}\" would never be sent");
		}

		$_SHARED{ 'smtp_async' }{ $$ } = {
				host => $host,
				port => $port,
				tx_timeout => $tx_timeout,
				secure => $secure,
				secure_host => $secure_host,
				wallet_path => $wallet_path,
				helo_domain => undef,
				sender => undef,
				recipients => [],
				data => undef
		};
		return {
				host => $host,
				port => $port,
				tx_timeout => $tx_timeout,
				private_tcp_con => $$,
				private_state => 1
		};
	}

	delete $_SHARED{ 'smtp' }{ $$ };
	my $smtp = eval { $_SHARED{ 'utl_smtp_connect' }->($host, $port, $tx_timeout, %ssl) };
	if (!defined $smtp)
	{
		my $err = $@;
		chomp($err);
		elog(WARNING, $err);
		return undef;
	}
	$_SHARED{ 'smtp' }{ $$ } = $smtp;

	return {
			host => $host,
			port => $port,
			tx_timeout => $tx_timeout,
			private_tcp_con => $$,
			private_state => 0
		};
$code$;
COMMENT ON FUNCTION utl_smtp.open_connection(varchar, integer, integer, varchar, varchar, boolean, varchar)
    IS 'Open a connection to an SMTP server. Returns the connection (see data type utl_smtp.connection). With pg_utl_smtp.asynchronous enabled no connection is made, messages are queued and sent by pg_dbms_job.';
REVOKE ALL ON FUNCTION utl_smtp.open_connection FROM PUBLIC;

CREATE PROCEDURE utl_smtp.ehlo (c IN utl_smtp.connection, domain IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $domain) = @_;

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		$s->{helo_domain} = $domain;
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->hello($domain), 'EHLO');

$code$;
COMMENT ON PROCEDURE utl_smtp.ehlo (c IN utl_smtp.connection, domain IN varchar)
    IS 'Performs the initial handshake with SMTP server using the EHLO command and return the reply of the command (see type utl_smtp.reply).';
REVOKE ALL ON PROCEDURE utl_smtp.ehlo FROM PUBLIC;

CREATE PROCEDURE utl_smtp.helo (c IN utl_smtp.connection, domain IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $domain) = @_;

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		$s->{helo_domain} = $domain;
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->hello($domain), 'HELO');

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

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(ERROR, "UTL_SMTP: MAIL called while a DATA session is open") if (defined $s->{data});
		$s->{sender} = $sender;
		$s->{recipients} = [];
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->mail($sender), 'MAIL');

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

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(ERROR, "UTL_SMTP: RCPT called before MAIL") if (!defined $s->{sender});
		elog(ERROR, "UTL_SMTP: RCPT called while a DATA session is open") if (defined $s->{data});
		push(@{ $s->{recipients} }, $recipient);
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->recipient($recipient), "RCPT <$recipient>");

$code$;
COMMENT ON PROCEDURE utl_smtp.rcpt (c IN utl_smtp.connection, recipient varchar, parameters varchar)
    IS 'Specifies the recipient of an e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.rcpt FROM PUBLIC;

CREATE PROCEDURE utl_smtp.quit (c IN utl_smtp.connection)
    LANGUAGE plperlu
    AS $code$
	my ($conn) = @_;

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(WARNING, "UTL_SMTP: QUIT called with an open DATA session, the message is discarded") if (defined $s->{data});
		delete $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} };
		return;
	}

	my $smtp = delete $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->quit(), 'QUIT');

$code$;
COMMENT ON PROCEDURE utl_smtp.quit (c IN utl_smtp.connection)
    IS 'Terminates an SMTP session and disconnects from the server.';
REVOKE ALL ON PROCEDURE utl_smtp.quit FROM PUBLIC;

CREATE PROCEDURE utl_smtp.open_data (c IN utl_smtp.connection)
    LANGUAGE plperlu
    AS $code$
	my ($conn) = @_;

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(ERROR, "UTL_SMTP: OPEN_DATA called before MAIL") if (!defined $s->{sender});
		elog(ERROR, "UTL_SMTP: OPEN_DATA called without any RCPT") if (!scalar @{ $s->{recipients} });
		elog(ERROR, "UTL_SMTP: a DATA session is already open") if (defined $s->{data});
		$s->{data} = '';
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->data(), 'DATA');

$code$;
COMMENT ON PROCEDURE utl_smtp.open_data (c IN utl_smtp.connection)
    IS 'Sends the DATA command after which you can use write_data() and write_raw_data() to write a portion of the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.open_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.write_data (c IN utl_smtp.connection, data IN varchar)
    LANGUAGE plperlu
    AS $code$
	my ($conn, $data) = @_;

	chomp($data);
	$data .= "\n";

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(ERROR, "UTL_SMTP: WRITE_DATA called before OPEN_DATA") if (!defined $s->{data});
		$s->{data} .= $data;
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->datasend($data), 'DATA (write)');

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

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(ERROR, "UTL_SMTP: WRITE_RAW_DATA called before OPEN_DATA") if (!defined $s->{data});
		$s->{data} .= $data;
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->datasend($data), 'DATA (write)');

$code$;
COMMENT ON PROCEDURE utl_smtp.write_raw_data (c IN utl_smtp.connection, data varchar)
    IS 'Writes a portion of the e-mail message. A repeat call to write_raw_data() appends data to the e-mail message.';
REVOKE ALL ON PROCEDURE utl_smtp.write_raw_data FROM PUBLIC;

CREATE PROCEDURE utl_smtp.close_data (c IN utl_smtp.connection)
    LANGUAGE plperlu
    AS $code$
	my ($conn) = @_;

	if (($conn->{'private_state'} // 0) == 1) {
		my $s = $_SHARED{ 'smtp_async' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
		elog(ERROR, "UTL_SMTP: CLOSE_DATA called before OPEN_DATA") if (!defined $s->{data});

		my $ins = spi_prepare(q{INSERT INTO utl_smtp.mail_queue
				(host, port, tx_timeout, secure, secure_host, wallet_path, helo_domain, sender, recipients, data)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id},
				'varchar', 'integer', 'integer', 'boolean', 'varchar', 'varchar', 'varchar', 'varchar', 'varchar[]', 'text');
		my $rv = spi_exec_prepared($ins, $s->{host}, $s->{port}, $s->{tx_timeout},
				($s->{secure}) ? 't' : 'f', $s->{secure_host}, $s->{wallet_path},
				$s->{helo_domain}, $s->{sender}, $s->{recipients}, $s->{data});
		spi_freeplan($ins);
		my $id = $rv->{rows}[0]{id};

		my $sub = spi_prepare('SELECT utl_smtp.async_submit($1) AS job', 'bigint');
		$rv = spi_exec_prepared($sub, $id);
		spi_freeplan($sub);
		elog(DEBUG1, "UTL_SMTP: message $id queued, pg_dbms_job job $rv->{rows}[0]{job}");

		# Ready for a new mail transaction on the same connection
		$s->{sender} = undef;
		$s->{recipients} = [];
		$s->{data} = undef;
		return;
	}

	my $smtp = $_SHARED{ 'smtp' }{ $conn->{'private_tcp_con'} } or elog(ERROR, "no SMTP connection defined");
	spi_exec_query('SELECT utl_smtp.init_perl()') if (!exists $_SHARED{ 'utl_smtp_check' });
	$_SHARED{ 'utl_smtp_check' }->($smtp, $smtp->dataend(), 'DATA (end)');

$code$;
COMMENT ON PROCEDURE utl_smtp.close_data (c IN utl_smtp.connection)
    IS 'Sends the e-mail message by sending a single period at the beginning of a line. In asynchronous mode the message is queued and sent by pg_dbms_job after commit.';
REVOKE ALL ON PROCEDURE utl_smtp.close_data FROM PUBLIC;
