.PHONY: all build test clean netlink-controller

BINARY_DIR := .
NETLINK_CTL := $(BINARY_DIR)/mitigator-ctl
NETLINK_SRC := ./src/cmd/netlink-controller/

all: build

build: netlink-controller

# Declared .PHONY above: the target name matches no file, but an earlier
# layout had a ./netlink-controller directory, which made make treat the
# target as up to date and skip the build silently.
netlink-controller:
	go build -o $(NETLINK_CTL) $(NETLINK_SRC)

# Netlink and namespace operations need CAP_NET_ADMIN, so the tests run as
# root. -E plus an explicit PATH keeps the user's Go toolchain and module
# cache visible under sudo.
test:
	sudo -E env "PATH=$(PATH)" go test -v $(NETLINK_SRC)

clean:
	rm -f $(NETLINK_CTL)
