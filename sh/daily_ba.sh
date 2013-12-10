#!/bin/sh

fetch_mls.pl CA Dublin,Pleasanton,Livermore,San Ramon,Mountain House || { echo "fetch_mls failed. Exiting..."; exit 255; }

. ./make_csvs_ba.sh
