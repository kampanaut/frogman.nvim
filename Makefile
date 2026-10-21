NVIM ?= nvim
RUN = tmp=$$(mktemp -d) && \
	XDG_CONFIG_HOME=$$tmp/config XDG_DATA_HOME=$$tmp/data XDG_STATE_HOME=$$tmp/state XDG_CACHE_HOME=$$tmp/cache \
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run(dofile('scripts/test_opts.lua'))"; \
	status=$$?; rm -rf $$tmp; exit $$status

.PHONY: test test-target test-all test-file deps

# Intended and today's behaviour: should all pass.
test: deps
	@export CDV_TAGS=char,today; $(RUN)

# Decided behaviour not built yet: fails until each fix lands.
test-target: deps
	@export CDV_TAGS=target; $(RUN)

test-all: deps
	@export CDV_TAGS=char,today,target; $(RUN)

# One file, every tag: make test-file FILE=tests/test_restores.lua
test-file: deps
	@export CDV_TAGS=$${CDV_TAGS:-char,today,target} CDV_FILE=$(FILE); $(RUN)

deps: deps/mini.test

deps/mini.test:
	@mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.test $@
