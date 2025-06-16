EXTENSION  = pg_utl_smtp
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
		sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

PGFILEDESC = "pg_utl_smtp - Propose Oracle UTL_SMTP compatibility for PostgreSQL"

PG_CONFIG = pg_config
PG10 = $(shell $(PG_CONFIG) --version | egrep " 8\.| 9\." > /dev/null && echo no || echo yes)

ifeq ($(PG10),yes)
DOCS = $(wildcard README*)
MODULES =

DATA = $(wildcard updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
else
$(error Minimum version of PostgreSQL required is 10)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

installcheck:
	$(PROVE)
