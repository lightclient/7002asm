#!/bin/bash

if ! command -v go &> /dev/null
then
  echo "Go is not installed. Please install Go and try again."
  exit 1
fi

if ! test -x bin/nick &> /dev/null
then
  echo "nick could not be found, installing..."
  env "GOBIN=$PWD/bin" go install github.com/lightclient/nick@latest
  if [ $? -ne 0 ]; then
    echo "Failed to install nick."
    exit 1
  fi
fi

default_score=5
score=${2:-$default_score}
gaslimit=1300000

case $1 in
  beaconroot|b|4788)
    echo "searching for beacon root deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/beacon_root/ctor.hex)" --prefix=0xbeac02 --suffix=0x0000
    ;;
  withdrawals|wxs|7002)
    echo "searching for withdrawals deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/withdrawals/ctor.hex)" --prefix=0x0000 --suffix=0xaaaa
    ;;
  consolidations|cxs|7251)
    echo "searching for consolidations deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/consolidations/ctor.hex)" --prefix=0x0000 --suffix=0xbbbb
    ;;
  exechash|e|2935)
    echo "searching for execution hash deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/execution_hash/ctor.hex)" --prefix=0x0000 --suffix=0xcccc
    ;;
  builder_deposits)
    echo "searching for builder_deposits deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/builder_deposits/ctor.hex)" --prefix=0x8282 --suffix=0xdddd --gaslimit=$gaslimit
    ;;
  builder_exits)
    echo "searching for builder_exits deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/builder_exits/ctor.hex)" --prefix=0x8282 --suffix=0xeeee --gaslimit=$gaslimit
    ;;
  sweep_thresholds|sts|8148)
    echo "searching for sweep threshold deployment data "
    bin/nick search --score=$score --initcode="0x$(cat bytecode/sweep_thresholds/ctor.hex)" --prefix=0x0000 --suffix=0xffff
    ;;
  *)
    echo "Invalid option. Usage: $0 {withdrawals|consolidations|exechash|beaconroot|builder_deposits|builder_exits|sweep_thresholds}"
    ;;
esac
