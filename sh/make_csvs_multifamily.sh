#!/bin/sh
set -xv

mysql -uroot -proot -e "select 'units','Price/Sqft','Price','Sqft','Built', 'Buildings', 'Beds/Unit', 'Rents/Unit', 'Added', 'Garage', 'url' INTO OUTFILE \"/tmp/multifamily-active-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.units 'Units', ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft, ph.built Built, ifnull(ph.buildings,'') Buildings, ifnull(ph.bed_units,'') 'Beds/Unit', ifnull(ph.unit_rents,'') 'Rents/Unit', replace(ph.added_to_site,',','') Added, ifnull(ph.garages, '') Garage, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active' and units is not NULL order by ph.units desc INTO OUTFILE \"/tmp/multifamily-active-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/multifamily-active-$$.1 /tmp/multifamily-active-$$.2 > /var/tmp/multifamily_active_$(date +"%Y%m%d").csv

#mpack -s "daily_$(date +"%Y%m%d").csv" /var/tmp/daily_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# make a separate list for short sale 

mysql -uroot -proot -e "select 'units','Price/Sqft','Price','Sqft','Built', 'Buildings', 'Beds/Unit', 'Rents/Unit', 'Added', 'Garage', 'url' INTO OUTFILE \"/tmp/multifamily-shortsale-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.units 'Units', ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft, ph.built Built, ifnull(ph.buildings,'') Buildings, ifnull(ph.bed_units,'') 'Beds/Unit', ifnull(ph.unit_rents,'') 'Rents/Unit', replace(ph.added_to_site,',','') Added, ifnull(ph.garages, '') Garage, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active Short Sale' and units is not NULL order by ph.units desc INTO OUTFILE \"/tmp/multifamily-shortsale-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/multifamily-shortsale-$$.1 /tmp/multifamily-shortsale-$$.2 > /var/tmp/multifamily_shortsale_$(date +"%Y%m%d").csv
