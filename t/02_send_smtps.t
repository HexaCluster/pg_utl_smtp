use Test::Simple tests => 2;

$ENV{LANG}='C';

# SMTP over SSL/TLS (implicit TLS on port 465). The server certificate is
# verified using the CA file in SMTPS_CA_FILE (default: Debian/Ubuntu postfix
# snakeoil certificate) and must match the name given in SMTPS_HOST (default:
# the host FQDN).
my $ca = $ENV{SMTPS_CA_FILE} || '/etc/ssl/certs/ssl-cert-snakeoil.pem';
my $host = $ENV{SMTPS_HOST} || `hostname -f`;
chomp($host);

$ret = `psql -X -d regress_utl_smtp -v smtps_ca="$ca" -v smtps_host="$host" -f test/sql/send_smtps.sql > results/send_smtps.out 2>&1`;
ok( $? == 0, "test to send smtps");

$ret = `diff results/send_smtps.out test/expected/send_smtps.out 2>&1`;
ok( $? == 0, "diff for send smtps");
