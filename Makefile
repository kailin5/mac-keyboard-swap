PREFIX ?= /usr/local

.PHONY: test lint install uninstall

test:
	./test/run.sh

lint:
	shellcheck bin/kbswap test/run.sh test/stubs/hidutil

install:
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/bin/kbswap $(PREFIX)/bin/kbswap

uninstall:
	rm -f $(PREFIX)/bin/kbswap
