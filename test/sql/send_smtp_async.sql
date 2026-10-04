-- Asynchronous mode: messages are queued and sent by pg_dbms_job
\set VERBOSITY terse
TRUNCATE utl_smtp.mail_queue RESTART IDENTITY;

-- Invalid value for the setting
SET pg_utl_smtp.asynchronous = 'maybe';
DO $$ DECLARE c utl_smtp.connection; BEGIN c := utl_smtp.open_connection('localhost'); END $$;

SET pg_utl_smtp.asynchronous = true;

-- 1) A message produced in a rolled back transaction is never sent
BEGIN;
DO $$
DECLARE
  c utl_smtp.connection;
BEGIN
  c := utl_smtp.open_connection('localhost');
  RAISE NOTICE 'private_state = %', c.private_state;
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'postgres@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'Subject: rolled back');
  CALL utl_smtp.write_data(c, '');
  CALL utl_smtp.write_data(c, 'Must never be sent');
  CALL utl_smtp.close_data(c);
  CALL utl_smtp.quit(c);
END;
$$;
SELECT count(*) AS queued_in_xact FROM utl_smtp.mail_queue;
ROLLBACK;
SELECT count(*) AS queued_after_rollback FROM utl_smtp.mail_queue;

-- 2) Two messages on the same connection, one of them to a rejected recipient
DO $$
DECLARE
  c utl_smtp.connection;
BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, CURRENT_USER || '@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'From: "Sender" <postgres@localhost>');
  CALL utl_smtp.write_data(c, 'To: "Recipient" <postgres@localhost>');
  CALL utl_smtp.write_data(c, 'Subject: Hello async');
  CALL utl_smtp.write_data(c, '');
  CALL utl_smtp.write_data(c, 'Hello, asynchronous world!');
  CALL utl_smtp.write_data(c, '.leading dot line');
  CALL utl_smtp.close_data(c);
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'reject@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'Subject: Rejected');
  CALL utl_smtp.close_data(c);
  CALL utl_smtp.quit(c);
END;
$$;
SELECT id > 0 AS has_id, sender, recipients, status, job_id IS NOT NULL AS has_job FROM utl_smtp.mail_queue ORDER BY id;

-- Wait for pg_dbms_job to process the queue (max 30s)
DO $$
BEGIN
  FOR i IN 1..300 LOOP
    EXIT WHEN NOT EXISTS (SELECT 1 FROM utl_smtp.mail_queue WHERE status = 'queued');
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;
SELECT recipients, status, attempts, sent_date IS NOT NULL AS has_sent_date, last_error FROM utl_smtp.mail_queue ORDER BY id;

-- 2b) A message sent over SSL/TLS, the SSL options are stored with the message
SELECT set_config('regress.smtps_ca', :'smtps_ca', false) IS NOT NULL AS ok,
       set_config('regress.smtps_host', :'smtps_host', false) IS NOT NULL AS ok;
DO $$
DECLARE
  c utl_smtp.connection;
BEGIN
  c := utl_smtp.open_connection('localhost', 465, NULL, current_setting('regress.smtps_ca'), NULL, true, current_setting('regress.smtps_host'));
  CALL utl_smtp.ehlo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'postgres@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'Subject: Hello async over TLS');
  CALL utl_smtp.close_data(c);
  CALL utl_smtp.quit(c);
END;
$$;
DO $$
BEGIN
  FOR i IN 1..300 LOOP
    EXIT WHEN NOT EXISTS (SELECT 1 FROM utl_smtp.mail_queue WHERE status = 'queued');
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;
SELECT port, secure, wallet_path = current_setting('regress.smtps_ca') AS same_ca, status, last_error FROM utl_smtp.mail_queue WHERE secure;

-- 3) Resend a failed message: still rejected, attempts is incremented
SELECT utl_smtp.async_resend(id) > 0 AS resubmitted FROM utl_smtp.mail_queue WHERE status = 'failed';
DO $$
BEGIN
  FOR i IN 1..300 LOOP
    EXIT WHEN NOT EXISTS (SELECT 1 FROM utl_smtp.mail_queue WHERE status = 'queued');
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;
SELECT recipients, status, attempts FROM utl_smtp.mail_queue WHERE status = 'failed';
-- A sent message can not be resent
SELECT utl_smtp.async_resend(id) FROM utl_smtp.mail_queue WHERE status = 'sent' ORDER BY id LIMIT 1;

-- 4) Protocol errors are detected at call time in asynchronous mode
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.rcpt(c, 'postgres@localhost');
END $$;
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.open_data(c);
END $$;
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.write_data(c, 'no DATA session');
END $$;
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'postgres@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'never closed');
  CALL utl_smtp.quit(c);
END $$;

-- 5) Back to synchronous mode: nothing is queued
SET pg_utl_smtp.asynchronous = off;
DO $$ DECLARE c utl_smtp.connection; BEGIN
  c := utl_smtp.open_connection('localhost');
  RAISE NOTICE 'private_state = %', c.private_state;
  CALL utl_smtp.helo(c, 'example.com');
  CALL utl_smtp.mail(c, 'postgres');
  CALL utl_smtp.rcpt(c, 'postgres@localhost');
  CALL utl_smtp.open_data(c);
  CALL utl_smtp.write_data(c, 'Subject: sync again');
  CALL utl_smtp.close_data(c);
  CALL utl_smtp.quit(c);
END $$;
SELECT count(*) AS queued FROM utl_smtp.mail_queue;
