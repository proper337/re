#!/usr/bin/perl
#

use strict;
use warnings;

use DBI;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTML::TreeBuilder::XPath;
use JSON -support_by_pp;
use Data::Dumper;

use Text::Balanced qw (
                          extract_delimited
                          extract_bracketed
                          extract_quotelike
                          extract_codeblock
                          extract_variable
                          extract_tagged
                          extract_multiple
                          gen_delimited_pat
                          gen_extract_tagged
                     );
use POSIX;
use constant MAX_PRICE => 250000;
use constant MAX_RETRIES => 5;

sub browse_zip_page($$$);

my $properties;

my $realtor_dot_com = "http://www.realtor.com";
my $trulia_dot_com  = "http://www.trulia.com";
my $zillow_dot_com  = "http://www.zillow.com";

my $search_suffix = "/realestateandhomes-search";
my $detail_suffix = "/realestateandhomes-detail";
my $beds_listing_type_suffix = "/beds-2#/listingType-condo-townhome-row-home-co-op";
my $zipcode_based_beds_listing_type_suffix = "/sby-1#/beds-2/listingType-condo-townhome-row-home-co-op";
my $pagesize_suffix = "/pagesize-50";

my $properties_to_retry = [];

$| = 1;

###############################################
#
# DB stuff
#
###############################################

my ($dbh, $sth);
$dbh = DBI->connect ('dbi:mysql:database=re', 'root', 'root', {RaiseError => 1, AutoCommit => 1});

#my $low_to_high_suffix = "/sortby-1";

# storage
#
#
# TABLE metro_areas
#
# metro
# area
#
# TABLE mls
#
# mls - primary
# metro
# address - index
# added - date added
# modified - last modified
# sqft
# price - last (most current) price
# DOM
# CDOM
# Offered - offer made
# HOA

# TABLE price_history
#
# MLS
# Date - price observed on date
#

my $zips_arg = $ARGV[0];

my $states;
my $cities;
my $state = "CA";
my $city;
my $realtor_search_url = $realtor_dot_com . "/handlers/resources.ashx";
my $ua = new LWP::UserAgent;
my $resp;
my $zip_city_map = {95628 => 'Fair Oaks',
                    95662 => 'Orangevale',
                    95660 => 'North Highlands',
                    95843 => 'Antelope',
                    95826 => 'Sacramento',
                    95842 => 'Sacramento'};

if (!defined($zips_arg)) {
    $zips_arg = "95628,95662,95660,95843,95826,95842";
}

my @zips = split ",", $zips_arg;

$states = $dbh->selectall_hashref("select * from state", "state");
my $state_id = $states->{$state}{id};

$cities = $dbh->selectall_hashref("select c.id,c.city from city c join state_city sc " .
                                  "where sc.state_id=? and sc.city_id=c.id", "city",
                                  {},$state_id);

foreach my $zip (@zips) {
    print "\n---- $zip ----\n";

    my $city = $zip_city_map->{$zip};
    my $city_id  = $cities->{$city}{id};

    $properties->{$zip}{total} = 0;
    $properties->{$zip}{new} = 0;

    my $page_num = 1;
    my $found_pages=0;

    while (1) {
        my $zip_page = browse_zip_page($zip, $city, $page_num);
        last if (!keys %{$zip_page->{properties}->[0]});

        print "\t\t==== $zip:page$page_num:(". scalar(@{$zip_page->{properties}}) . ") ====\n";
        # if (!defined($zip_page->{properties}->[0]->{PropertyPrice})) {
        #     Carp::croak "Invalid page ";
        # }
        for (my $i = 0; $i < scalar(@{$zip_page->{properties}}); $i++) {
            my $property = $zip_page->{properties}->[$i];
            $property->{city_id} = $city_id;
            $property->{state_id} = $state_id;
            $property->{Zip} = $zip;
            my $fill_status = fill_property_detail($property);
            next if ($property->{PropertyPrice} > MAX_PRICE);
            if ($fill_status) {
                print "\t\t\t http://www.realtor.com" . $property->{detailpageURL} . " -- " . $property->{MetaData} . "\n";
                 if ($fill_status == 1 && defined($property->{'MLS ID'}) && length($property->{'MLS ID'})) {
                   insert_property($property);
                }
            } else {
                print ("#### adding $property->{detailpageURL} to properties to retry later\n");
                push @$properties_to_retry, $property;
            }
            $properties->{$zip}{total}++;
        }
        last if ($zip_page->{is_last});
        $page_num++;
    }
    # print Dumper $properties->{$state}{$city};
}

# print "\n#### Retrying failed properties... ####\n";
# foreach my $property (@{$properties_to_retry}) {
#     if (fill_property_detail($property)) {
#         print "\t\t\t " . $property->{detailpageURL} . "\n";
#         insert_property($property);
#     } else {
#         print "\t\t\t FAILED " . $property->{detailpageURL} . "\n";
#     }
# }


sub fill_property_detail {
    my ($property) = @_;
    my $retries = 0;
    my $ret;

    while ($retries++ < MAX_RETRIES) {
        sleep(floor(rand(30)));
        $resp = $ua->get($realtor_dot_com . $property->{detailpageURL});
        $ret = collect_data2($property, $resp);
        return $ret if ($ret);
    }
    return 0;
}

sub collect_data2 {
    my ($property, $resp) = @_;

    if (!$resp->is_success) {
        return 0;
    }

    my $detail_tb = HTML::TreeBuilder::XPath->new_from_content($resp->decoded_content);

    my $add_detail = $detail_tb->findnodes('/html/body//div[@id="AdditionalDetails"]//tr');
    foreach my $detail (@$add_detail) {
        my @th = $detail->look_down('_tag', 'th');
        my @td = $detail->look_down('_tag', 'td');
        next if (!defined($th[0]) || !defined($td[0]));
        if ($th[0]->as_trimmed_text =~ m/MLS ID/) {
            $property->{'MLS ID'} = trim($td[0]->as_trimmed_text);
        }
        if ($th[0]->as_trimmed_text =~ m/Presented by/) {
            $property->{'Presented by'} = join " ", map {$_->as_trimmed_text} $td[0]->content_list;
        }
        if ($th[0]->as_trimmed_text =~ m/Listing Brokered by/) {
            $property->{'Listing Brokered by'} = join " ", map {$_->as_trimmed_text} $td[0]->content_list;
        }
    }

    my $sidebyside_ul = $detail_tb->findnodes('/html/body//li[@class="list-sidebyside"]');
    foreach my $ul (@$sidebyside_ul) {
        my @spans = $ul->look_down('_tag', 'span');
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^Price$/) {
            if (!defined($property->{PropertyPrice})) {
                die "invalid price" if (!defined($spans[1]));
                $property->{PropertyPrice} = trim($spans[1]->as_trimmed_text);
                $property->{PropertyPrice} =~ tr/[\-,\$]+//d;
                $property->{PropertyPrice} = trim_undef($property->{PropertyPrice});
            }
        }
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^Status/) {
            if (!defined($property->{status})) {
                die "invalid status" if (!defined($spans[1]));
                $property->{status} = trim_undef($spans[1]->as_trimmed_text);
            }
        }
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^Beds$/) {
            if (!defined($property->{bed})) {
                die "invalid beds" if (!defined($spans[1]));
                $property->{bed} = trim($spans[1]->as_trimmed_text); 
                $property->{bed} =~ tr/[\-,A-Za-z\\s]+//d;
                $property->{bed} = trim_undef($property->{bed});
            }
        }
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^Baths$/) {
            if (!defined($property->{bath})) {
                die "invalid baths" if (!defined($spans[1]));
                $property->{bath} = trim($spans[1]->as_trimmed_text);
                $property->{bath} =~ tr/[\-,A-Za-z\\s]+//d;
                $property->{bath} = trim_undef($property->{bath});
            }
        }
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^House Size/) {
            if (!defined($property->{ListingSqft})) {
                die "invalid sqft" if (!defined($spans[1]));
                $property->{ListingSqft} = trim($spans[1]->as_trimmed_text);
                $property->{ListingSqft} =~ tr/[\-,A-Za-z\\s]+//d;
                $property->{ListingSqft} = trim_undef($property->{ListingSqft});
            }
        }
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^Lot Size/) {
            if (!defined($property->{LotSqft})) {
                die "invalid baths" if (!defined($spans[1]));
                $property->{LotSqft} = trim($spans[1]->as_trimmed_text);
                $property->{LotSqft} =~ tr/[\-,A-Za-z\\s]+//d;
                $property->{LotSqft} = undef if (length($property->{LotSqft}) == 0);
            }
        }
        if (defined($spans[0]) && $spans[0]->as_trimmed_text =~ m/^Year Built/) {
            if (!defined($property->{YearBuilt})) {
                die "invalid baths" if (!defined($spans[1]));
                $property->{YearBuilt} = trim($spans[1]->as_trimmed_text);
                $property->{YearBuilt} =~ tr/[\-,A-Za-z\\s]+//d;
                $property->{YearBuilt} = undef if (length($property->{YearBuilt}) == 0);
            }
        }
    }
    $property->{'Direct access URL'} = 'http://www.realtor.com' . $property->{detailpageURL};

    $property->{MetaData} = "";
    my $check_sold = $detail_tb->findnodes('/html/body//div[@id="MetaData"]');
    if (scalar(@$check_sold)) {
        $property->{MetaData} = $check_sold->[0]->as_trimmed_text;
   }
    # $sth->bind_param(4,  $property->{'PropertyPrice'});

    return 1;
}

# this markup is now invalid, see collect_data2
sub collect_data {
    my ($property, $resp) = @_;

    if (!$resp->is_success) {
        return 0;
    }

    my $detail_tb = HTML::TreeBuilder::XPath->new_from_content($resp->decoded_content);

    my $summary_th_nodes = $detail_tb->findnodes('/html/body//table[@class="summaryTable"]/tr/th');
    my $summary_td_nodes = $detail_tb->findnodes('/html/body//table[@class="summaryTable"]/tr/td');
    my $presented_by1_nodes = $detail_tb->findnodes('/html/body//div[@class="agentModule"]/div/h3');
    my $presented_by2_nodes = $detail_tb->findnodes('/html/body//div[@class="agentModule"]/div/div/ul/li');

    if (scalar(@$summary_th_nodes) != scalar(@$summary_td_nodes)) {
        Carp::carp("Mismatched number of th/td nodes found");
        return 0;
    }

    my $mls;

    for (my $j = 0; $j < scalar(@$summary_th_nodes); ++$j) {
        my $key = $summary_th_nodes->[$j]->as_trimmed_text;
        my $val = $summary_td_nodes->[$j]->as_trimmed_text;
        if ($key eq "Days on site") {
            $val =~ tr/[\-\$,a-zA-Z ]//d;
        }
        $property->{$key} = $val;

    }

    my $property_features_nodes = $detail_tb->findnodes('/html/body//div[@class="propertyData"]/ul');
    if (!defined($property_features_nodes->[0])) {
        print "undefined Status node, skipping...";
        return;
    }
    my @li_nodes = $property_features_nodes->[0]->look_down("_tag","li"); # First li node is Status
    if (defined($li_nodes[0]) && $li_nodes[0]->as_trimmed_text =~ m/^Status: (.*)/) {
        $property->{status} = trim($1);
    } else {
        print "no listing status for " . get_property_address($property);
        return 2;
    }
    $property->{'Property Features'} = join " ", map {$_->as_trimmed_text} @li_nodes;

    my $property_data_p_nodes = $detail_tb->findnodes('/html/body//div[@class="propertyData"]/p');
    for (my $j = 0; $j < scalar(@$property_data_p_nodes); ++$j) {
        my $val = $property_data_p_nodes->[$j]->as_trimmed_text;
        if ($val =~ m/^MLS ID: (.*)/) {
            $property->{'MLS ID'} = trim($1);
        }

        if ($val =~ m!^http://www.realtor.com/realestateandhomes-detail/!) {
            $property->{'Direct access URL'} = trim($val);
        }
    }


    if (defined($presented_by1_nodes)) {
        $property->{'Presented by'} = join " ", $presented_by1_nodes->string_values();
    }
    if (defined($presented_by2_nodes)) {
        $property->{'Presented by'} .= join " ", $presented_by2_nodes->string_values();
    }

    $detail_tb = $detail_tb->delete;

    # sanity checks:
    #
    # this probably went off-market/got-sold.  It'll not have MLS ID at this point.

    if (!defined($property->{'Property Features'}) && defined($property->{'Estimated Value'})) {
        return 2;
    }

    # This is an error.
    if (!defined($property->{'MLS ID'})) {
        return 0;
    }
    return 1;
}

sub scrub_price_nodes {
    my ($prices) = @_;
    my @ret;
    map {
        my $str = $_->as_text;
        $str =~ tr/[\-\$,a-zA-Z ]//d;
        push @ret, $str;
    } @$prices;
    return \@ret;
}

sub scrub_beds_baths_nodes {
    my ($beds_baths) = @_;
    my (@ret_beds, @ret_baths);

    map {
        my ($beds, $baths) = split ",", $_->as_text;
        $beds =~ tr/[\-,a-zA-Z ]//d;
        $baths =~ tr/[\-,a-zA-Z ]//d;
        push @ret_beds, $beds;
        push @ret_baths, $baths;
    } @$beds_baths;

    return (\@ret_beds, \@ret_baths);
}

sub scrub_area_nodes {
    my ($areas) = @_;
    my @ret;

    map {
        my $str = $_->as_text;
        my $unit_acre=0;

        if ($str =~ m/Acre/) {
            $unit_acre=1;
        }
        $str =~ tr/[\-,a-zA-Z ]//d;
        if ($unit_acre) {
            $str *= 43560;
        }
        push @ret, $str;
    } @$areas;

    return \@ret;
}

sub scrub_nodes {
    my ($nodes) = @_;
    my @ret;

    map {
        push @ret, trim($_->as_text);
    } @$nodes;
    return \@ret;
}

sub scrub_anchor_nodes {
    my ($anchors) = @_;
    my (@ret_addresses, @ret_hrefs);

    map {
        my $address = $_->as_trimmed_text;
        my $href = $_->attr('href');

        push @ret_addresses, $address;
        push @ret_hrefs, trim($href);
    } @$anchors;

    return (\@ret_addresses, \@ret_hrefs);
}

sub apply_filter {
    my ($column_vals, $filter) = @_;

    if ($column_vals->{price} <= 80000) {
        return 1;
    }

    return 0;
}


sub trim($)
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

sub trim_undef {
    my $string = shift;
    my $ret = trim($string);
    if (length($ret) == 0) {
        return undef;
    }
    return $ret;
}

sub browse_zip_page($$$) {
    my ($zip, $city, $page_num) = @_;
    my $retries = 0;
    my $ret->{properties} = [];

    while ($retries++ < MAX_RETRIES) {
        sleep(ceil(rand(30)));
        my $url = "http://www.realtor.com/realestateandhomes-search/$zip/type-condo-townhome-row-home-co-op/price-na-" . MAX_PRICE;
        if ($page_num != 1) {
            $url .= ("/pg-" . $page_num);
        }
        $url .= "?pgsz=50";
        $resp=$ua->get($url);
        last if ($resp->is_success);
    }

    if (!$resp->is_success) {
        Carp::croak "could not get summary page for $zip, $page_num";
    }

    my $tree = HTML::TreeBuilder::XPath->new_from_content($resp->decoded_content);
    my $listings = $tree->findnodes('/html/body//div[@class =~ "^listing (listing-showcase)? (listing-branded)?"');
    foreach my $listing (@$listings) {
        my $listing_photo_a = $listing->look_down('_tag', 'a', 'class', 'listing-photo');
        die "no listing photo url" if (!defined($listing_photo_a));
        my $property;
        $property->{detailpageURL} = $listing_photo_a->attr('href');

        my @location_spans = $listing->look_down('_tag', 'span', 'class', qr/^listing-/);
        die "invalid location spans" if (!scalar(@location_spans));
        $property->{street} = $location_spans[0]->as_trimmed_text; $property->{street} =~ tr/[\-,]+//d;
        $property->{city} = $location_spans[1]->as_trimmed_text; $property->{city} =~ tr/[\-,]+//d;
        $property->{state} = $location_spans[2]->as_trimmed_text; $property->{state} =~ tr/[\-,]+//d;

        push @{$ret->{properties}}, $property;
    }

    my $next = $tree->findnodes('/html/body//a[@class =~ "pagination-next "]');
    $ret->{is_last} = !(defined($next) && scalar(@$next) && defined($next->[0]->attr('href')));
    return $ret;
}

sub insert_property {
    my ($property) = @_;

    $sth = $dbh->prepare ("insert into mls(state_id,city_id,mls,seen) " .
                          "values($property->{state_id},$property->{city_id},\'$property->{'MLS ID'}\',now()) " . 
                          "on duplicate key update seen=now()");
    $sth->execute;

    $sth = $dbh->prepare ("insert ignore into mls_status_history(mls,status) " .
                          "values(\'$property->{'MLS ID'}\',\'$property->{status}\')");
    $sth->execute;

    if ($sth->rows) {
        $properties->{$property->{state}}{new}++;
        $properties->{$property->{state}}{$property->{city}}{new}++;
    }

    # DO update on duplicate key
    #
    $sth = $dbh->prepare("insert into " .
                         "price_history(mls,status,address,price,sqft,ppsqft," . 
                         "beds,baths,lot,built,dos,url,presented_by,brokered_by,features,zip,hashdump) " .
                         "values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ". 
                         "on duplicate key update mls=values(mls),status=values(status),address=values(address), " .
                         "price=values(price),sqft=values(sqft),ppsqft=values(ppsqft),beds=values(beds), " .
                         "baths=values(baths),lot=values(lot),built=values(built),dos=values(dos),url=values(url), " .
                         "presented_by=values(presented_by),brokered_by=values(brokered_by),features=values(features), " .
                         "zip=values(zip),hashdump=values(hashdump),added=now()");

    $sth->bind_param(1,  $property->{'MLS ID'});
    $sth->bind_param(2,  $property->{'status'});
    $sth->bind_param(3,  get_property_address($property));
    $sth->bind_param(4,  $property->{'PropertyPrice'});
    $sth->bind_param(5,  $property->{'ListingSqft'});
    $sth->bind_param(6,  undef);
    eval {
        if (defined($property->{'ListingSqft'}) && $property->{'ListingSqft'} != 0) {
            $sth->bind_param(6,  $property->{'PropertyPrice'}/$property->{'ListingSqft'});
        }
    };
    $sth->bind_param(7,  $property->{'bed'});
    $sth->bind_param(8,  $property->{'bath'});
    $sth->bind_param(9,  $property->{'LotSqft'});
    $sth->bind_param(10, $property->{'YearBuilt'});
    $sth->bind_param(11, $property->{'Days on site'});
    $sth->bind_param(12, $property->{'Direct access URL'});
    $sth->bind_param(13, $property->{'Presented by'});
    $sth->bind_param(14, $property->{'Listing Brokered by'});
    $sth->bind_param(15, $property->{'Property Features'});
    $sth->bind_param(16, $property->{'Zip'});
    $sth->bind_param(17, to_json($property, {allow_blessed => 1}));
    $sth->execute;

    $properties->{$property->{city}}{total}++;
}

sub get_property_address {
    my ($property) = @_;
    my $ret = "";

    if (defined($property->{street})) {
        $ret .= $property->{street};
    } else {
        $ret .= "UNKNOWN_address";
    }
    $ret .= ", ";
    if (defined($property->{city})) {
        $ret .= $property->{city};
    } else {
        $ret .= "UNKNOWN_city";
    }
    $ret .= ", ";
    if (defined($property->{state})) {
        $ret .= $property->{state};
    } else {
        $ret .= "UNKNOWN_state";
    }
    $ret .= " ";
    if (defined($property->{Zip})) {
        $ret .= $property->{Zip};
    } else {
        $ret .= "UNKNOWN_zip";
    }
    return $ret;
}

sub extract_multiple_bracketed {
    my ($str) = @_;
    my $begin = -1;
    my $depth = -1;
    my @ret;

    for(my $i = 0; $i < length($str); $i++) {
        # skip the initial junk till we get to {
        if ($depth == -1) {
            next if (substr($str,$i,1) ne '{');
            $begin = $i;
            $depth = 0;
        }

        if (substr($str,$i,1) eq '{') {$depth++; next;}
        if (substr($str,$i,1) eq '}') {
            $depth--;
            if ($depth == 0) {
                if ($begin == -1) {
                    Carp::carp("invalid string to extract_multiple_bracketed");
                }
                push @ret, substr($str,$begin, $i-$begin+1);
                $depth = $begin = -1;
            }
        }
    }
    return @ret;
}

sub make_sql_list {
    my ($comma_separated) = @_;
    my @fields = split ",", $comma_separated;
    my $ret = "";

    return $ret if (scalar (@fields) == 0);

    foreach my $field (@fields) {
        if (length($ret)) {
            $ret .= ",\'" . "$field" . "\'";
        } else {
            $ret .= "(\'" . "$field" . "\'";
        }
    }
    $ret .= ')';
}
