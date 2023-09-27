DO $$
DECLARE
  c UTL_SMTP.CONNECTION;
BEGIN
  c := UTL_SMTP.OPEN_CONNECTION('localhost', 465);
  IF c.private_tcp_con IS NOT NULL THEN
    RAISE NOTICE 'Connection successful';
    RAISE NOTICE 'HELO';
    CALL UTL_SMTP.HELO(c, 'example.com');
    RAISE NOTICE 'MAIL';
    CALL UTL_SMTP.MAIL(c, 'gilles');
    RAISE NOTICE 'RCPT';
    CALL UTL_SMTP.RCPT(c, CURRENT_USER || '@localhost');
    RAISE NOTICE 'OPEN_DATA';
    CALL UTL_SMTP.OPEN_DATA(c);
    RAISE NOTICE 'WRITE_DATA';
    CALL UTL_SMTP.WRITE_DATA(c, 'From: "Sender" <gilles@localhost>');
    CALL UTL_SMTP.WRITE_DATA(c, 'To: "Recipient" <gilles@localhost>');
    CALL UTL_SMTP.WRITE_DATA(c, 'Subject: Hello');
    CALL UTL_SMTP.WRITE_DATA(c, '');
    CALL UTL_SMTP.WRITE_DATA(c, 'Hello, world!');
    RAISE NOTICE 'CLOSE_DATA';
    CALL UTL_SMTP.CLOSE_DATA(c);
    RAISE NOTICE 'QUIT';
    CALL UTL_SMTP.QUIT(c);
  END IF;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Failed to send mail due to the following error: %', SQLERRM USING ERRCODE='08006';
END;
$$;
