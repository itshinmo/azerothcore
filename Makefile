SHELL := /bin/bash
JOBS := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
PREFIX := $(CURDIR)/env/dist
VERIFY_BUILD := build-verify

.PHONY: help doctor configure configure-verify build install test verify-docs verify-sql verify-cpp verify-smoke verify-full start stop restart status logs console backup dbadmin clean

help:
	@printf '%s\n' \
	  'make doctor           check environment' \
	  'make build            configure if needed, build, install' \
	  'make test             build the test target and run unit tests' \
	  'make verify-docs      markdown link check' \
	  'make verify-sql       SQL lint; test-realm apply when configured' \
	  'make verify-cpp       C++ lint, -Werror build, unit tests' \
	  'make verify-smoke     start, health-check, stop' \
	  'make verify-full      all tiers' \
	  'make start|stop|restart|status|logs|console' \
	  'make backup           dump the three databases' \
	  'make dbadmin          start the database GUI (phase 3)'

doctor:
	@bash tools/dev/doctor.sh

configure:
	cmake -S . -B build \
	  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
	  -DSCRIPTS=static -DMODULES=static \
	  -DCMAKE_INSTALL_PREFIX="$(PREFIX)"

configure-verify:
	cmake -S . -B $(VERIFY_BUILD) \
	  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
	  -DSCRIPTS=static -DMODULES=static \
	  -DBUILD_TESTING=ON \
	  -DCMAKE_CXX_FLAGS=-Werror \
	  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	  -DCMAKE_INSTALL_PREFIX="$(PREFIX)"

build:
	@if [ ! -f build/CMakeCache.txt ]; then $(MAKE) configure; fi
	cmake --build build -j$(JOBS)
	cmake --install build

install: build

test:
	@if [ ! -f $(VERIFY_BUILD)/CMakeCache.txt ]; then $(MAKE) configure-verify; fi
	cmake --build $(VERIFY_BUILD) -j$(JOBS)
	./$(VERIFY_BUILD)/src/test/unit_tests

verify-docs:
	@bash tools/dev/verify.sh docs

verify-sql:
	@bash tools/dev/verify.sh sql

verify-cpp:
	@bash tools/dev/verify.sh cpp

verify-smoke:
	@bash tools/dev/verify.sh smoke

verify-full:
	@bash tools/dev/verify.sh full

start:
	@bash tools/dev/server.sh start

stop:
	@bash tools/dev/server.sh stop

restart:
	@bash tools/dev/server.sh restart

status:
	@bash tools/dev/server.sh status

logs:
	@bash tools/dev/server.sh logs

console:
	@bash tools/dev/server.sh console worldserver

backup:
	@bash tools/dev/backup.sh

dbadmin:
	@if [ -f tools/dbadmin/package.json ]; then \
	  cd tools/dbadmin && npm start; \
	else \
	  printf '%s\n' 'database GUI is phase 3; see runbook/operation/dbadmin.md'; \
	  exit 1; \
	fi

clean:
	rm -rf build $(VERIFY_BUILD)
