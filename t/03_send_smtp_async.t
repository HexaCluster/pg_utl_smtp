use Test::Simple tests => 2;

$ENV{LANG}='C';

# Test of the asynchronous mode, requires pg_dbms_job loaded with
# pg_dbms_job.database = 'regress_utl_smtp' (see README)
my $ca = $ENV{SMTPS_CA_FILE} || "/etc/ssl/certs/ssl-cert-snakeoil.pem";
my $host = $ENV{SMTPS_HOST} || `hostname -f`;
chomp($host);

$ret = `psql -X -d regress_utl_smtp -v smtps_ca="$ca" -v smtps_host="$host" -f test/sql/send_smtp_async.sql > results/send_smtp_async.out 2>&1`;
ok( $? == 0, "test to send smtp in asynchronous mode");

$ret = `diff results/send_smtp_async.out test/expected/send_smtp_async.out 2>&1`;
ok( $? == 0, "diff for send smtp in asynchronous mode");
