APP := ct_surefire

ERL = `which erl`
REBAR = `which rebar || echo "./rebar"`

CT_DIR=../../logs
OUTPUT_DIR=.

.PHONY: test

all:
	@$(REBAR) get-deps
	@$(REBAR) compile

clean: distclean depsclean docsclean testclean

compile:
	@$(REBAR) compile

deps:
	@$(REBAR) get-deps

# these commands do a far better job at cleaning than rebar's clean command
depsclean:
	@rm -Rf deps

# these commands do a far better job at cleaning than rebar's clean command
distclean:
	@rm -Rf ebin src/ct_suite_log_parser.erl

docs:
	@$(ERL) -noshell -run edoc_run application '$(APP)' '"."' '[]'

# these commands do a far better job at cleaning than rebar's clean command
docsclean:
	@rm -Rf doc

#simple but sufficient for now
test:
	@$(MAKE) xmlify CT_DIR=test/t001 OUTPUT_DIR=test

# these commands do a far better job at cleaning than rebar's clean command
testclean:
	@rm -Rf test/*.xml

# Add the following to the code path
#     ebin - self-explanatory
#     deps/*/ebin - when used as a stand-alone
#     ../*/ebin - when used as a rebar dependency
xmlify:
	@$(ERL) -noshell -pa ebin deps/*/ebin ../*/ebin -run ct_surefire generate_surefire_reports ${CT_DIR} ${OUTPUT_DIR} -s init stop
