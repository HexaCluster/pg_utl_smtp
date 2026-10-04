use Test::Simple tests => 4;

$ENV{LANG}='C';

# Cleanup garbage from previous regression test runs
`rm -rf results/ 2>/dev/null`;

`mkdir results 2>/dev/null`;

# The test database is not dropped between runs: the pg_dbms_job background
# worker stays connected to it and terminating it (DROP DATABASE ... WITH
# (FORCE)) makes it exit cleanly, so it is not restarted by the postmaster.
`psql -c "CREATE DATABASE regress_utl_smtp" > /dev/null 2>&1`;
$ret = `psql -d regress_utl_smtp -c "SELECT 1" > /dev/null 2>&1`;
ok( $? == 0, "Test regression database exists: regress_utl_smtp");

`psql -d regress_utl_smtp -c "DROP EXTENSION IF EXISTS pg_utl_smtp" > /dev/null 2>&1`;
`psql -d regress_utl_smtp -c "DROP EXTENSION IF EXISTS pg_dbms_job" > /dev/null 2>&1`;

$ret = `psql -d regress_utl_smtp -c "CREATE EXTENSION IF NOT EXISTS plperlu" > /dev/null 2>&1`;
ok( $? == 0, "Create extension plperl");

$ret = `psql -d regress_utl_smtp -c "CREATE EXTENSION pg_utl_smtp" > /dev/null 2>&1`;
ok( $? == 0, "Create extension pg_utl_smtp");

$ret = `psql -d regress_utl_smtp -c "CREATE EXTENSION pg_dbms_job" > /dev/null 2>&1`;
ok( $? == 0, "Create extension pg_dbms_job");
