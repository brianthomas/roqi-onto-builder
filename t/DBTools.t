
use ROQI::Ontology::Tools;
use ROQI::DBTools;
use t::TestUtils;
use XML::LibXML();
use XML::LibXML::Common qw(:libxml);
use Test::More; #qw(no_plan);

my $CAPTURE_OUTPUT = 0;

  # test 1 : can we load the module?
  require_ok( 'ROQI::DBTools' );

  ROQI::DBTools::setDebug(0);
  ROQI::Ontology::Tools::setQuiet(1);

  # this is tested elsewhere  
  my $onto_doc = &ROQI::Ontology::Tools::create_ontology_from_files("t/CDS.VizieR_J_AJ_109_1169.xml");

  # test2 : do we get the database loader content we expect?
  my $parsed_doc = &ROQI::DBTools::create_dbload_document($onto_doc);

  my $PARSER = XML::LibXML->new();
  my $expected_doc = $PARSER->parse_file("t/db_load.xml");

  if ($CAPTURE_OUTPUT) {
    open (OUT, ">out0.xml"); print OUT $parsed_doc->toString(1); close OUT;
  }

  #open (DBLOAD, "t/db_load.xml"); &compare_check(*DBLOAD, $db_load_doc->toString(1)); close DBLOAD;

  ok(&TestUtils::compare_nodes($parsed_doc->documentElement(), $expected_doc->documentElement(), ""));

  #print STDERR $db_load_doc->toString(1);

  done_testing();

1;

sub compare_check {
  my ($fh, $onto) = @_;

  my @expected = split "\n", $onto;
  my $cnt = 0;
  foreach my $line (<$fh>) {
    chomp $line;
    $line =~ s/\s+//g;
    my $check = $expected[$cnt];
    $check =~ s/\s+//g;
    is ($line, $check);
    $cnt = $cnt +1;
  } 

}


