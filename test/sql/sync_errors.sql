-- Synchronous mode: errors returned by the SMTP server are raised
\set VERBOSITY terse
SET pg_utl_smtp.asynchronous = off;

-- Sender refused
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'badsender@localhost');
END $$;

-- Recipient refused
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'reject@localhost');
END $$;

-- Message refused at the end of DATA
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'postgres@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'Subject: REJECTDATA');
  CALL utl_smtp.close_data(c);
END $$;

-- The error can be trapped and the connection closed, as with Oracle
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  BEGIN
    CALL utl_smtp.rcpt(c, 'reject@localhost');
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'trapped: %', SQLERRM;
  END;
  CALL utl_smtp.quit(c);
END $$;

-- The connection is released by QUIT
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.quit(c);
  CALL utl_smtp.quit(c);
END $$;

-- Nothing listening: warning and NULL connection
SELECT utl_smtp.open_connection('localhost', 2525) IS NULL AS no_connection;

-- Invalid wallet_path is an error
SELECT utl_smtp.open_connection('localhost', 465, NULL, '/nonexistent/ca.pem', NULL, true);

-- Server certificate not signed by the given CA: warning and NULL connection
SELECT utl_smtp.open_connection('localhost', 465, NULL, :'other_ca', NULL, true) IS NULL AS no_connection;

-- Server certificate does not match secure_host: warning and NULL connection
SELECT utl_smtp.open_connection('localhost', 465, NULL, :'smtps_ca', NULL, true, 'bad.example.org') IS NULL AS no_connection;
