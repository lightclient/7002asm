.PHONY: build geas checksums test clean

GEAS_VERSION ?= 0.3.3
GEAS         ?= bin/geas-$(GEAS_VERSION)

build: $(GEAS)
	mkdir -p bytecode

	# 2935
	mkdir -p bytecode/execution_hash
	$(GEAS) -a -no-nl -o bytecode/execution_hash/main.hex src/execution_hash/main.eas
	$(GEAS) -a -no-nl -o bytecode/execution_hash/ctor.hex src/execution_hash/ctor.eas

	# 4788
	mkdir -p bytecode/beacon_root
	$(GEAS) -a -no-nl -o bytecode/beacon_root/main.hex src/beacon_root/main.eas
	$(GEAS) -a -no-nl -o bytecode/beacon_root/ctor.hex src/beacon_root/ctor.eas

	# 7002
	mkdir -p bytecode/withdrawals
	$(GEAS) -a -no-nl -o bytecode/withdrawals/main.hex src/withdrawals/main.eas
	$(GEAS) -a -no-nl -o bytecode/withdrawals/ctor.hex src/withdrawals/ctor.eas

	# 7251
	mkdir -p bytecode/consolidations
	$(GEAS) -a -no-nl -o bytecode/consolidations/main.hex src/consolidations/main.eas
	$(GEAS) -a -no-nl -o bytecode/consolidations/ctor.hex src/consolidations/ctor.eas

	# 8282
	mkdir -p bytecode/builder_deposits
	$(GEAS) -a -no-nl -o bytecode/builder_deposits/main.hex src/builder_deposits/main.eas
	$(GEAS) -a -no-nl -o bytecode/builder_deposits/ctor.hex src/builder_deposits/ctor.eas
	mkdir -p bytecode/builder_exits
	$(GEAS) -a -no-nl -o bytecode/builder_exits/main.hex src/builder_exits/main.eas
	$(GEAS) -a -no-nl -o bytecode/builder_exits/ctor.hex src/builder_exits/ctor.eas

	# 8148
	mkdir -p bytecode/sweep_thresholds
	$(GEAS) -a -no-nl -o bytecode/sweep_thresholds/main.hex src/sweep_thresholds/main.eas
	$(GEAS) -a -no-nl -o bytecode/sweep_thresholds/ctor.hex src/sweep_thresholds/ctor.eas

	# 7997
	mkdir -p bytecode/factory
	$(GEAS) -a -no-nl -o bytecode/factory/main.hex src/factory/main.eas

	# test helper
	mkdir -p bytecode/fake_expo_test
	$(GEAS) -a -no-nl -o bytecode/fake_expo_test/main.hex src/common/fake_expo_test.eas

checksums: build
	shasum -a 256 -c checksums.txt

test: build checksums
	forge test -vvv

clean:
	rm -f "bin/geas-$(GEAS_VERSION)"
	rm -fr bytecode

ifeq ($(GEAS),bin/geas-$(GEAS_VERSION))
$(GEAS):
	mkdir -p bin
	env "GOBIN=$(CURDIR)/bin" go install github.com/fjl/geas/cmd/geas@v$(GEAS_VERSION)
	mv bin/geas "bin/geas-$(GEAS_VERSION)"
endif
