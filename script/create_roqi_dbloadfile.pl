#!/usr/bin/perl -w  

use ROQI::Util;
use ROQI::DBTools;
use ROQI::Ontology::Fixer;
use ROQI::Ontology::Tools;

die "no input registry XML files given" unless $#ARGV > -1;

print STDERR "Getting 'raw' Ontology from Registry files\n";
my $roqi_raw_ontology_doc = ROQI::Ontology::Tools::create_ontology_from_files(@ARGV);

print STDERR "Creating DB Load file\n";
open (DBFILE, ">roqi_data.xml");
my $dbload = ROQI::DBTools::create_dbload_document($roqi_raw_ontology_doc)->toString(1);
print DBFILE $dbload;
close DBFILE;

print "Finished, wrote results to roqi_data.xml\n";

# extract_subject_metadata.pl data-march-2009/cdsweb.u-strasbg.fr/*.xml > roqi_raw.owl
# create_db_loadfile.pl roqi_raw.owl > roqi_data.xml
# trim_metadata_in_onto.pl roqi_raw.owl > roqi_basic.owl
# fix_subject_inheritance.pl roqi_basic.owl > roqi.owl

