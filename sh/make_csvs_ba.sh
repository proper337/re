#!/bin/sh

mysql -uroot -proot -e "select 'Price/Sqft','Price','Sqft','Days','Beds','Baths','Built', 'url' INTO OUTFILE \"/tmp/daily-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft,ph.dos Days,ph.beds Beds,ph.baths Baths, ph.built Built, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active' and (zip=94568 or zip=94566 or zip=94588 or zip=94550 or zip=94551 or zip=95391 or zip=94582 or zip=94583) and ph.price<250000 and ph.dos<=30 and hashdump not like '%\"Property Type\":\"Single%' and added >= DATE_SUB(NOW(), INTERVAL 64 DAY) order by ph.built desc INTO OUTFILE \"/tmp/daily-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/daily-$$.1 /tmp/daily-$$.2 > /var/tmp/ba_daily_$(date +"%Y%m%d").csv

mpack -s "ba_daily_$(date +"%Y%m%d").csv" /var/tmp/ba_daily_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# make a separate list for single family

mysql -uroot -proot -e "select 'Price/Sqft','Price','Sqft','Days','Beds','Baths','Built', 'url' INTO OUTFILE \"/tmp/single_family_daily-$$.1\" FIELDS TERMINATED BY ',' ENCLOSED BY '\"'LINES TERMINATED BY '\n'"

mysql -uroot -proot --column-names -e "select ph.ppsqft 'Price/Sqft',ph.price 'Price',ph.sqft Sqft,ph.dos Days,ph.beds Beds,ph.baths Baths, ph.built Built, CONCAT('=HYPERLINK(\"', ph.url,'\")') url from price_history ph where ph.status='Active' and (zip=94568 or zip=94566 or zip=94588 or zip=94550 or zip=94551 or zip=95391 or zip=94582 or zip=94583) and ph.price<250000 and ph.dos<=30 and hashdump like '%\"Property Type\":\"Single%' and added >= DATE_SUB(NOW(), INTERVAL 64 DAY) order by ph.dos INTO OUTFILE \"/tmp/single_family_daily-$$.2\" FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';" re

cat /tmp/single_family_daily-$$.1 /tmp/single_family_daily-$$.2 > /var/tmp/ba_single_family_daily_$(date +"%Y%m%d").csv

mpack -s "ba_single_family_daily_$(date +"%Y%m%d").csv" /var/tmp/ba_single_family_daily_$(date +"%Y%m%d").csv k_ram_chandran@yahoo.com

# rm /tmp/daily-$$.*
