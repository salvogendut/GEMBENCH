PYTHON ?= python3

EXAMPLE_SOURCE := examples/hello-dialog.json
EXAMPLE_OUTPUT := build/examples/hello-dialog.gbr

.PHONY: all check test example clean

all: check

check: test example

test:
	$(PYTHON) -m unittest discover -s tests -v

example: $(EXAMPLE_OUTPUT)

$(EXAMPLE_OUTPUT): $(EXAMPLE_SOURCE) tools/gbrc.py
	mkdir -p $(dir $@)
	$(PYTHON) tools/gbrc.py $< --output $@

clean:
	rm -rf build
