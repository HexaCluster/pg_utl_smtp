use Test::Simple tests => 3;

$ENV{LANG}='C';

# Test that utl_smtp request acquire lock

# Cleanup garbage from previous regression test runs
`rm -rf results/ 2>/dev/null`;

`mkdir results 2>/dev/null`;

# First drop the test database and users
`psql -c "DROP DATABASE regress_utl_smtp" 2>/dev/null`;

# Create the test database
$ret = `psql -c "CREATE DATABASE regress_utl_smtp"`;
ok( $? == 0, "Create test regression database: regress_utl_smtp");

$ret = `psql -d regress_utl_smtp -c "CREATE EXTENSION plperlu" > /dev/null 2>&1`;
ok( $? == 0, "Create extension plperl");

#$ret = `psql -c "ALTER DATABASE regress_utl_smtp SET plperl.on_init = 'use Net::SMTP;'"`;
#ok( $? == 0, "Alter test regression database: regress_utl_smtp");

$ret = `psql -d regress_utl_smtp -c "CREATE EXTENSION pg_utl_smtp" > /dev/null 2>&1`;
ok( $? == 0, "Create extension pg_utl_smtp");

