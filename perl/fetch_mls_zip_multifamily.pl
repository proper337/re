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
use URI::Escape;
use File::Path qw(make_path);

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
use constant MAX_PRICE => 2500000;
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
#                   95621 => 'Citrus Heights',
#                   95660 => 'North Highlands',
#                   95670 => 'Gold River',
                    95821 => 'Sacramento',
                    95826 => 'Sacramento',
                    95841 => 'Sacramento',
                    95842 => 'Sacramento',
                    95843 => 'Antelope'
                   };


if (!defined($zips_arg)) {
    $zips_arg = join ",", sort(keys %$zip_city_map);
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
        $resp = ua_get($realtor_dot_com . $property->{detailpageURL});
        $ret = collect_data($property, $resp);
        return $ret if ($ret);
    }
    return 0;
}

sub collect_data {
    my ($property, $resp) = @_;

    if (!$resp->is_success) {
        return 0;
    }

    my $detail_tb = HTML::TreeBuilder::XPath->new_from_content($resp->decoded_content);

    my $data1 = $detail_tb->findnodes('/html/body//li[@class="list-sidebyside"]');
    my $data2 = $detail_tb->findnodes('/html/body//ul[@class="list-disc list-condensed list-col-c group"]/li');
    my $data3 = $detail_tb->findnodes('/html/body//table[@class="table table-data table-bordered table-bordered-alt table-condensed"]//tr');

    foreach my $data1_item (@$data1) {
        my @data1_spans = $data1_item->look_down('_tag', 'span');
        next if (scalar(@data1_spans) != 2);
        if ($data1_spans[0]->as_trimmed_text =~ m/Status/) {
            $property->{status} = trim($data1_spans[1]->as_trimmed_text);
        }
        if ($data1_spans[0]->as_trimmed_text =~ m/\# of Units/) {
            my $units;
            if ($data1_spans[1]->as_trimmed_text =~ m/(\d+)\s*Units/) {
                $units = $1;
            }
            $property->{units} = trim($1);
        }
        if ($data1_spans[0]->as_trimmed_text =~ m/House Size/) {
            if (!defined($property->{ListingSqft})) {
                if ($data1_spans[1]->as_trimmed_text =~ m/([\d,]+)/) {
                    $property->{ListingSqft} = trim($1); $property->{ListingSqft} = scrub_num($property->{ListingSqft});
                }
            }
        }
        if ($data1_spans[0]->as_trimmed_text =~ m/Lot Size/) {
            if (!defined($property->{LotSqft})) {
                if ($data1_spans[1]->as_trimmed_text =~ m/([\d,]+)/) {
                    $property->{LotSqft} = trim($1); $property->{LotSqft} =~ tr/[,]//d;
                }
            }
        }
        if ($data1_spans[0]->as_trimmed_text =~ m/Year Built/) {
            $property->{YearBuilt} = trim($data1_spans[1]->as_trimmed_text);
        }
    }

    foreach my $data2_item (@$data2) {
        my $str = $data2_item->as_trimmed_text;
        if ($str =~ m/Tax paid:\s*([,\d]+)/) {
            $property->{tax} = scrub_num(trim($1));
        }
        if ($str =~ m/Garages:\s*([,\d]+)/) {
            $property->{garages} = scrub_num(trim($1));
        }
        if ($str =~ m/Total # of Bldgs:\s*([,\d]+)/) {
            $property->{buildings} = scrub_num(trim($1));
        }
        if ($str =~ m/(\d+ Bed Unit:\s*[,\d]+)/) {
            $property->{bed_units} .= " ## " if (length($property->{bed_units}));
            $property->{bed_units} .= trim($1);
        }
        if ($str =~ m/Unit\s*(\d)+ Rent:\s*([\$,\d]+)/) {
            $property->{unit_rents} .= " ## " if (length($property->{unit_rents}));
            $property->{"unit_rents"} .= ("unit_" . $1 . ": " . scrub_price(trim($2)));
        }
    }

    foreach my $data3_item (@$data3) {
        my @ths = $data3_item->look_down('_tag', 'th');
        my @td = $data3_item->look_down('_tag', 'td');
        if ($ths[0]->as_trimmed_text =~ m/MLS ID/) {
            $property->{'MLS ID'} = $td[0]->as_trimmed_text;
        }
        if ($ths[0]->as_trimmed_text =~ m/Direct access URL/) {
            $property->{'Direct access URL'} = $td[0]->as_trimmed_text;
        }
        if ($ths[0]->as_trimmed_text =~ m/Added to Site/) {
            $property->{'added_to_site'} = $td[0]->as_trimmed_text;
        }
    }
    # Days on site
    # MLS ID
    # status
    # Property Features = Sum (XXX Features)
    # Direct access URL
    # Presented by
    my $mls;

#   $detail_tb = $detail_tb->delete;

    # This is an error.
    if (!defined($property->{'MLS ID'})) {
        return 0;
    }
    return 1;
}

sub scrub_price {
    return scrub_num(@_);
}

sub scrub_num {
    my ($price) = @_;
    $price =~ tr/\$[,a-zA-Z ]//d;
    return $price;
}

sub scrub_price_nodes {
    my ($prices) = @_;
    my @ret;
    map {push @ret, scrub_price($_->as_text);} @$prices;
    return \@ret;
}

sub scrub_beds_baths_nodes {
    my ($beds_baths) = @_;
    my (@ret_beds, @ret_baths);

    map {
        my ($beds, $baths) = split ",", $_->as_text;
        $beds =  scrub_num($beds);
        $baths = scrub_num($baths);
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
        $str = scrub_num($str);
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

sub scrub_column_vals {
    my ($column_vals) = @_;

    $column_vals->{price} = scrub_price($column_vals->{price});

    $column_vals->{sqft} =~ tr/[,a-zA-Z ]//d;
    $column_vals->{baths} =~ tr/[a-zA-Z ]//d;

    my $acres_to_sqft = ($column_vals->{lot} =~ m/Acres/) ? 1 : 0;
    $column_vals->{lot} =~ tr/[,a-zA-Z ]//d;
    if ($acres_to_sqft) {
        $column_vals->{lot} = $column_vals->{lot} * 43560;
    }

    $column_vals->{year_built} =~ tr/ //d;
    $column_vals->{days_on_site} =~ tr/[a-zA-Z ]//d;
    $column_vals->{url} = trim($column_vals->{url});

    my $val;
    $val = trim($column_vals->{presented_by});
    $val =~ s/Presented by//;
    $val =~ s/Mobile:/ Mobile:/;     $val =~ s/Office:/ Office:/;
    $val =~ s/Fax:/ Fax:/;
    $val =~ s/Email Agent.*$//;
    $column_vals->{presented_by} = trim($val);

    $val = trim($column_vals->{brokered_by});
    $val =~ s/Presented by//;
    $val =~ s/Mobile:/ Mobile:/; $val =~ s/Office:/ Office:/;
    $val =~ s/Fax:/ Fax:/;
    $val =~ s/Email Agent.*$//;
    $column_vals->{brokered_by} = trim($val);

    $column_vals->{status} =~ s/Status: //; $column_vals->{status} = trim($column_vals->{status});
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

sub browse_zip_page($$$) {
    my ($zip, $city, $page_num) = @_;
    my $retries = 0;
    my $ret->{properties} = [];

    while ($retries++ < MAX_RETRIES) {
        sleep(ceil(rand(30)));
        $resp=ua_post("http://www.realtor.com/handlers/resources.ashx",
                        Content => 
                        {
                         Input    => 'pg=' . $page_num,
                         MetaKey	=> 'srp',

                         PageData =>	'suffix=&baseurl=realestateandhomes-search&status=homes+for+sale&zip=' . $zip . '&city=' . $city . '&state=CA&statename=California&sortby=1&type=condo-townhome-row-home-co-op&listingType=multi-family-home&sby=1&userlocation=' . $city . '%2C' . 'CA' . '%2C' . $zip . '&MetaKey=srp&seo_loc=Zip&PageTitle=' . $zip . '+Real+Estate+and+Homes+for+Sale&PageH1='  . $zip . '+Real+Estate+and+Homes+for+Sale&baseHost=&mapConstructor=vemap&_rdcLibUrl=http%3A%2F%2Fstatic.move.com%2Flib%2Frdc%2F6.1.2_P2A%2F&svertical=rdc',

                         WidgetList => '[{"ID": "Breadcrumb", "Param": "ajax=0&DataAdapterKey=dat&ArgAdapterKey=argSRP&WidgetRelative=%2FBreadcrumb", "Widget": "Breadcrumb", "WidgetRelative": "/Breadcrumb", "ctxt": "", "extraLoad": null}, {"ID": "oldFacetSearch", "Param": "listingTypeDefault1=single-family-home&listingTypeDefault2=condo-townhome-row-home-co-op&listingTypeDefault3=mfd-mobile-home&statusDefault=sale&geo_server=geo.svc.move.com&DataAdapterKey=dat&ArgAdapterKey=argSRP&mapControl=vemapControl&SaveSearch=1&WidgetRelative=%2FoldFacetSearch", "Widget": "oldFacetSearch", "WidgetRelative": "/oldFacetSearch", "ctxt": "", "extraLoad": null}, {"ID": "oldSRPHeader", "Param": "listingTypeDefault1=single-family&listingTypeDefault2=condo-townhome-row-home-co-op&statusDefault=sale&ajax=0&sortbyDefault=2&listingDataSource=oldSRPHeader&DataAdapterKey=dat&ArgAdapterKey=argSRP&cookieName4RecentViewed=RecentViewed&cookieName4RecentSearch=RecentSearch&pageStatus=SRPWidget%7ColdSRP%7ColdSRPHeader&RecentSearchCookie=1&defaultSRPTab=oldSRPTab&statusWidget=oldFacetSearch&FacetLimit=20&extras=PageH1%7Cstatus%7Cpfbm&WidgetRelative=oldSRPContainer%2FoldSRPHeader", "Widget": "oldSRPHeader", "WidgetRelative": "oldSRPContainer/oldSRPHeader", "ctxt": "", "extraLoad": null}, {"ID": "currentProperty", "Param": "extras=status&ajax=0&DataAdapterKey=dat&WidgetRelative=%2FcurrentProperty", "Widget": "currentProperty", "WidgetRelative": "/currentProperty", "ctxt": "", "extraLoad": null}, {"ID": "oldSRP", "Param": "ajax=0&listingTypeDefault1=single-family-home&listingTypeDefault2=condo-townhome-row-home-co-op&listingTypeDefault3=mfd-mobile-home&statusDefault=sale&sortbyDefault=2&OmnitureUpdate=1&geo_server=geo.svc.move.com&showCustoimzeIndicator=1&srpFadeOutRate=0.5&listingDataSource=oldSRPHeader&DataAdapterKey=dat&ArgAdapterKey=argSRP&cookieName4RecentViewed=RecentViewed&cookieName4RecentSearch=RecentSearch&pageStatus=SRPWidget%7ColdSRP%7ColdSRPHeader&defaultSRPTab=oldSRPTab&statusWidget=oldFacetSearch&FacetLimit=20&extras=mlslid%7Cpfbm%7Ccity%7Cstate&WidgetRelative=%2FoldSRP", "Widget": "oldSRP", "WidgetRelative": "/oldSRP", "ctxt": "", "extraLoad": null}, {"ID": "SearchWidgetSimplifyGo", "Param": "suffix=&baseurl=realestateandhomes-search&status=homes+for+sale&zip=95843&city=ANTELOPE&state=CA&statename=California&sortby=1&type=single-family-home%3Bcondo-townhome-row-home-co-op%3Bmfd-mobile-home&listingType=single-family-home%3Bcondo-townhome-row-home-co-op%3Bmfd-mobile-home&sby=1&userlocation=Antelope%2CCA%2C95843&MetaKey=WidgetService&seo_loc=Zip&PageTitle=95843+Real+Estate+-+ANTELOPE%2C+CA+95843+Homes+for+Sale+-+Realtor.com%26reg%3B+&PageH1=95843+Real+Estate+and+Homes+for+Sale&baseHost=&mapConstructor=vemap&_rdcLibUrl=http%3A%2F%2Fstatic.move.com%2Flib%2Frdc%2F6.1.2_P2A%2F&svertical=rdc&wdgtType=SimplifyButton&supressThrobber=1&DataAdapterKey=dat&ArgAdapterKey=arg&WidgetRelative=%2FSearchWidgetWithOutCount", "Widget": "SearchWidgetWithOutCount", "WidgetRelative": "/SearchWidgetWithOutCount", "ctxt": "Top", "extraLoad": null}, {"ID": "TrackNewSearch", "Param": "WidgetRelative=%2FTrackNewSearch", "Widget": "TrackNewSearch", "WidgetRelative": "/TrackNewSearch", "ctxt": "", "extraLoad": null}]'
                        }
                       );

        last if ($resp->is_success);
    }

    if (!$resp->is_success) {
        Carp::croak "could not get summary page for $zip, $page_num";
    }

    my $ind = index($resp->content, "flexui.initWidget;flexui.dataSet.byKey('SRP', ");
    if ($ind == -1) {
        Carp::croak "unexpected page format found 1 for $zip, $page_num";
    }
    my $begin_relevant = substr($resp->content, $ind + length("flexui.initWidget;flexui.dataSet.byKey('SRP', {list:"));
    my @extracted = extract_multiple_bracketed($begin_relevant);
    # if (scalar(@extracted) != 3) {
    #     Carp::croak "unexpected page format found 2 for $state_obj->{state}, $city_obj->{city}, $page_num";
    # }

    my @properties_strs = 
      extract_multiple_bracketed(substr($extracted[0],1,length($extracted[0])-2));

    foreach my $property_str (@properties_strs) {
        $property_str =~ s!\\"{!{!g;
        $property_str =~ s!\\\\/!/!g;
        $property_str =~ s!\\\\"!"!g;
        $property_str =~ s!\\"!"!g;
        $property_str =~ s!}",!},!g;

        my $property = from_json($property_str, {allow_singlequote => 1});

#
#         # sanity checks: 
#         # at this point we at least need the {PropertyPrice}, {detailpageURL}, {LotSqft}, {ListingSqft}
#         #
#         if (!defined($property->{PropertyPrice}) || !defined($property->{detailpageURL}) ||
#             !defined($property->{LotSqft}) || !defined($property->{ListingSqft})) {
#             Carp::croak ("One of required PropertyPrice, detailpageURL, LotSqft, ListingSqft is absent for: " .
#                          get_property_address($property));
#         }
        push @{$ret->{properties}}, $property;
    }

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
        $properties->{$property->{State}}{new}++;
        $properties->{$property->{State}}{$property->{City}}{new}++;
    }

    # DO update on duplicate key
    #
    $sth = $dbh->prepare("insert into " .
                         "price_history(mls,status,address,price,sqft,ppsqft," . 
                         "beds,baths,lot,built,dos,url,presented_by,brokered_by,features,zip,hashdump,units,tax,garages,buildings,bed_units,unit_rents,added_to_site) " .
                         "values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ". 
                         "on duplicate key update mls=values(mls),status=values(status),address=values(address), " .
                         "price=values(price),sqft=values(sqft),ppsqft=values(ppsqft),beds=values(beds), " .
                         "baths=values(baths),lot=values(lot),built=values(built),dos=values(dos),url=values(url), " .
                         "presented_by=values(presented_by),brokered_by=values(brokered_by),features=values(features), " .
                         "zip=values(zip),hashdump=values(hashdump),units=values(units),tax=values(tax),garages=values(garages), " .
                         "buildings=values(buildings), bed_units=values(bed_units), unit_rents=values(unit_rents), " .
                         "added_to_site=values(added_to_site), added=now()");

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
    $sth->bind_param(14, $property->{'Listing brokered by'});
    $sth->bind_param(15, $property->{'Property Features'});
    $sth->bind_param(16, $property->{'Zip'});
    $sth->bind_param(17, to_json($property, {allow_blessed => 1}));
    $sth->bind_param(18, $property->{'units'});
    $sth->bind_param(19, $property->{'tax'});
    $sth->bind_param(20, $property->{'garages'});
    $sth->bind_param(21, $property->{'buildings'});
    $sth->bind_param(22, $property->{'bed_units'});
    $sth->bind_param(23, $property->{'unit_rents'});
    $sth->bind_param(24, $property->{'added_to_site'});
    $sth->execute;

    $properties->{$property->{City}}{total}++;
}

sub get_property_address {
    my ($property) = @_;
    my $ret = "";

    if (defined($property->{JsonData}{adr})) {
        $ret .= $property->{JsonData}{adr};
    } else {
        $ret .= "UNKNOWN_address";
    }
    $ret .= ", ";
    if (defined($property->{JsonData}{ct})) {
        $ret .= $property->{JsonData}{ct};
    } else {
        $ret .= "UNKNOWN_city";
    }
    $ret .= ", ";
    if (defined($property->{State})) {
        $ret .= $property->{State};
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

sub read_bytes_from_file {
    my ($file_name) = @_;

    local $/ = undef;
    open FILE, $file_name or die "Couldn't open response file";
    binmode FILE;
    my $ret = <FILE>;
    close FILE;
    return $ret;
}

sub ua_post {
    my ($url, @post_params) = @_;
    my $resp;


    $resp = $ua->post($url, @post_params);
    die "post failed. url: $url post_params: @post_params" if (!$resp->is_success);
    return $resp;
}

sub ua_get {
    my ($url, $get_params) = @_;

    my $resp;
    $resp = $ua->get($url);
    die "get failed. url = $url" if (!$resp->is_success);
    return $resp;
}
