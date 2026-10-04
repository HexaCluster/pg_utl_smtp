use Test::Simple tests => 2;

$ENV{LANG}='C';

# Errors of the SMTP server in synchronous mode. Requires a SMTP server on
# localhost:25 that refuses sender "badsender@localhost", recipient
# "reject@localhost" and messages containing "REJECTDATA", the SSL/TLS
# settings of t/02_send_smtps.t and a CA file that has not signed the
# server certificate in SMTPS_OTHER_CA_FILE.
my $ca = $ENV{SMTPS_CA_FILE} || '/etc/ssl/certs/ssl-cert-snakeoil.pem';
my $other = $ENV{SMTPS_OTHER_CA_FILE} || '/etc/ssl/certs/ca-certificates.crt';

$ret = `psql -X -d regress_utl_smtp -v smtps_ca="$ca" -v other_ca="$other" -f test/sql/sync_errors.sql > results/sync_errors.out 2>&1`;
ok( $? == 0, "test of SMTP errors in synchronous mode");

$ret = `diff results/sync_errors.out test/expected/sync_errors.out 2>&1`;
ok( $? == 0, "diff for SMTP errors in synchronous mode");
