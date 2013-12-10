#!/usr/bin/perl

use strict;

sub usage();

usage() if (scalar(@ARGV) < 4);

my $purchase_price = $ARGV[0];
my $rent = $ARGV[1];
my $hoa  = $ARGV[2];
my $insurance = $ARGV[3];
my $repairs_percent = $ARGV[4];
my $property_tax_percent = $ARGV[5];

if (!defined ($repairs_percent)) {
    $repairs_percent = 10;
}
if (!defined ($property_tax_percent)) {
    $property_tax_percent = 1.1;
}

# my $rent_receipts = ($rent * 11); # 1 month un-occupied
# my $less_hoa = $rent_receipts - ($hoa * 12);
# my $less_insurance = $less_hoa - $insurance;
# my $less_property_tax = $less_insurance - ($purchase_price * $property_tax_percent * 0.01);
# my $less_repairs = $less_property_tax - ($rent_receipts * $repairs_percent * 0.01);

# printf "return*: %.4f%%\n", ($less_repairs/$purchase_price) * 100;
printf "return : %.4f%%\n", (($rent * 11) - ($hoa * 12) - $insurance - ($purchase_price * $property_tax_percent * .01) - 
                             ($rent * 11 * $repairs_percent * .01))/$purchase_price;

sub usage() {
    print "return_estimate.pl <purchase_price> <rent> <hoa> <insurance> [<property_tax>]\n";
    exit 1;
}
