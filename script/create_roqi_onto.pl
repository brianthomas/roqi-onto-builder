#!/usr/bin/perl -w  

use ROQI::Util;
use ROQI::DBTools;
use ROQI::Ontology::Creator;
use ROQI::Ontology::Trimmer;
use ROQI::Ontology::Fixer;

die "no input registry XML files given" unless $#ARGV > -1;

ROQI::Ontology::Creator::setQuiet(0);

print STDERR "Getting 'raw' Ontology from Registry files\n";
my $roqi_raw_ontology_doc = ROQI::Ontology::Creator::create_ontology_from_files(@ARGV);

print STDERR "Creating DB Load file\n";
open (DBFILE, ">roqi_data.xml");
my $dbload = ROQI::DBTools::create_dbload_document($roqi_raw_ontology_doc)->toString(1);
print DBFILE $dbload;
close DBFILE;

print STDERR "Trimming unused information from ontology\n";
my $trimmed_roqi_ontology_doc = ROQI::Ontology::Trimmer::trim_ontology ($roqi_raw_ontology_doc);

open (ONTO, ">roqi.owl");
print STDERR "Fixing and writing roqi ontology\n";
print ONTO ROQI::Ontology::Fixer::fix_ontology_inheritance($trimmed_roqi_ontology_doc)->toString(1);
close ONTO;

print "Finished, wrote results to roqi.owl and roqi_data.xml";

# extract_subject_metadata.pl data-march-2009/cdsweb.u-strasbg.fr/*.xml > roqi_raw.owl
# create_db_loadfile.pl roqi_raw.owl > roqi_data.xml
# trim_metadata_in_onto.pl roqi_raw.owl > roqi_basic.owl
# fix_subject_inheritance.pl roqi_basic.owl > roqi.owl

