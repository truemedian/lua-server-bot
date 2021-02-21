#!/bin/bash

export LUVI_VERSION=2.11.0
export LIT_VERSION=3.8.2

mkdir -p bin
mkdir -p logs

cd bin
# Install Luvi, Lit, and Luvit
if [ -e luvit ]; then
	echo "Reinstalling Luvi, Lit and Luvit"
	rm luvit luvi lit
fi

curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh

cd ..
# Install Dependencies
if [ -e deps ]; then
	echo "Reinstalling Dependencies"
	rm -r deps
fi

./bin/lit install
