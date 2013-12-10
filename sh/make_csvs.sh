#!/bin/sh
set -xv

mysql -uroot -proot -e "select 'Price/Sqft','Price','Sqft','Days','Beds','Baths','Built', 'url' INTO OUTFILE \"/tmp/daily-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft,ph.beds Beds,ph.baths Baths, ph.built Built, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active' and ph.price<100000 and hashdump not like '%\"Property Type\":\"Single%' and added >= DATE_SUB(NOW(), INTERVAL 1 DAY) order by ph.built desc INTO OUTFILE \"/tmp/daily-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/daily-$$.1 /tmp/daily-$$.2 > /var/tmp/daily_$(date +"%Y%m%d").csv

mpack -s "daily_$(date +"%Y%m%d").csv" /var/tmp/daily_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# make a separate list for short sale 

mysql -uroot -proot -e "select 'Price/Sqft','Price','Sqft','Days','Beds','Baths','Built', 'url' INTO OUTFILE \"/tmp/short-sale-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft,ph.beds Beds,ph.baths Baths, ph.built Built, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active Short Sale' and ph.price<100000 and hashdump not like '%\"Property Type\":\"Single%' and added >= DATE_SUB(NOW(), INTERVAL 1 DAY) order by ph.built desc INTO OUTFILE \"/tmp/short-sale-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/short-sale-$$.1 /tmp/short-sale-$$.2 > /var/tmp/short_sale_$(date +"%Y%m%d").csv

mpack -s "short_sale_$(date +"%Y%m%d").csv" /var/tmp/short_sale_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# make a separate list for non-active-short and non-active sale 

mysql -uroot -proot -e "select 'Price/Sqft','Price','Sqft','Days','Beds','Baths','Built', 'url' INTO OUTFILE \"/tmp/other-sale-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft,ph.beds Beds,ph.baths Baths, ph.built Built, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status <> 'Active' and ph.status <> 'Active Short Sale' and ph.price<100000 and hashdump not like '%\"Property Type\":\"Single%' and added >= DATE_SUB(NOW(), INTERVAL 1 DAY) order by ph.built desc INTO OUTFILE \"/tmp/other-sale-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/other-sale-$$.1 /tmp/other-sale-$$.2 > /var/tmp/other_sale_$(date +"%Y%m%d").csv

mpack -s "other_sale_$(date +"%Y%m%d").csv" /var/tmp/other_sale_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# make a separate list for single family

# mysql -uroot -proot -e "select 'Price/Sqft','Price','Sqft','Days','Beds','Baths','Built', 'url' INTO OUTFILE \"/tmp/single_family_daily-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

# mysql -uroot -proot --column-names -e "select ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft,ph.beds Beds,ph.baths Baths, ph.built Built, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active' and ph.price<80000 and hashdump like '%\"Property Type\":\"Single%' and added >= DATE_SUB(NOW(), INTERVAL 1 DAY) order by ph.built INTO OUTFILE \"/tmp/single_family_daily-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

# cat /tmp/single_family_daily-$$.1 /tmp/single_family_daily-$$.2 > /var/tmp/single_family_daily_$(date +"%Y%m%d").csv

# mpack -s "single_family_daily_$(date +"%Y%m%d").csv" /var/tmp/single_family_daily_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# rm /tmp/daily-$$.*
