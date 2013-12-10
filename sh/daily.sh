#!/bin/sh

fetch_mls_zip.pl || { echo "fetch_mls failed. Exiting..."; exit 255; }

. ./make_csvs.sh
