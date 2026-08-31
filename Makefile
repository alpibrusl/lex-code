.PHONY: install uninstall hooks

PREFIX ?= /usr/local
BINDIR  := $(PREFIX)/bin
SRCDIR  := $(PREFIX)/lib/lex-code

install:
	@echo "Installing lex-code to $(BINDIR)..."
	mkdir -p $(BINDIR) $(SRCDIR)
	cp -r src $(SRCDIR)/
	cp -r lex.toml $(SRCDIR)/
	@# Same invocation as bin/lex-code, with the installed layout's paths:
	@# `main --` so the first flag is not read as a function name, and the
	@# effect grant `lex check src/tui/main.lex` reports as required.
	@printf '#!/usr/bin/env sh\nset -e\nLEX_CODE_EFFECTS="$${LEX_CODE_EFFECTS:-approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,time}"\nexec lex run --allow-effects "$$LEX_CODE_EFFECTS" $(SRCDIR)/src/tui/main.lex main -- "$$@"\n' > $(BINDIR)/lex-code
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
