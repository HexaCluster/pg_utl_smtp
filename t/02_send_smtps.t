use Test::Simple tests => 2;

$ENV{LANG}='C';

# Test that utl_smtp request acquire lock

# Execute test for request/release
$ret = `psql -X -d regress_utl_smtp -f test/sql/send_smtps.sql > results/send_smtps.out 2>&1`;
ok( $? == 0, "test to send smtps");

$ret = `diff results/send_smtps.out test/expected/send_smtps.out 2>&1`;
ok( $? == 0, "diff for send smtps");

