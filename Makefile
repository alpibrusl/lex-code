.PHONY: install uninstall hooks

PREFIX ?= /usr/local
BINDIR  := $(PREFIX)/bin
SRCDIR  := $(PREFIX)/lib/lex-code

install:
	@echo "Installing lex-code to $(BINDIR)..."
	mkdir -p $(BINDIR) $(SRCDIR)
	cp -r src $(SRCDIR)/
	cp -r lex.toml $(SRCDIR)/
	@printf '#!/usr/bin/env sh\nexec lex run $(SRCDIR)/src/tui/main.lex "$$@"\n' > $(BINDIR)/lex-code
	chmod +x $(BINDIR)/lex-code
	@echo "Done. Run: lex-code [--provider <tag>] [--mode <mode>] [task]"

uninstall:
	rm -f $(BINDIR)/lex-code
	rm -rf $(SRCDIR)

hooks:
	mkdir -p .git/hooks
	cp .githooks/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "pre-commit hook installed — run 'make hooks' in each clone"
