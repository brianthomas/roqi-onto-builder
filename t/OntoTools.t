
use ROQI::Ontology::Tools;
use ROQI::Ontology::Fixer;
use t::TestUtils;
use XML::LibXML();
use XML::LibXML::Common qw(:libxml);
use Test::More; #qw(no_plan);

  my $CAPTURE_OUTPUT = 0;

  # test 1 : can we load the module?
  require_ok( 'ROQI::Ontology::Tools' );
  require_ok( 'ROQI::Ontology::Fixer' );

  ROQI::Ontology::Tools::setDebug(0);
  ROQI::Ontology::Tools::setQuiet(1);
  TestUtils::setDebug(0);

  doTest("t/CDS.VizieR_J_AJ_109_1169.xml", "t/extract_output.owl", "t/trimmed_output.owl", "t/fixed_output.owl");
  doTest("t/vopdc.obspm_portal.xml", "t/extract_output2.owl", "t/trimmed_output2.owl", "t/fixed_output2.owl");

  my_exit(0);

  1;

sub doTest {

  my ($data, $base, $trimmed, $fixed) = @_;

  # test 2, do we get the content we expect?
  &TestUtils::resetErrorMsg();
  my $onto = &ROQI::Ontology::Tools::create_ontology_from_files($data);
  if ($CAPTURE_OUTPUT) {
    my $file = ">".$base.".test";
    open (OUT, $file); print OUT $onto->toString(1); close OUT;
  }

  my $PARSER = XML::LibXML->new();
  my $expected_doc = $PARSER->parse_file($base);

  my $test_success = &TestUtils::compare_nodes($onto->documentElement(), $expected_doc->documentElement(), "");
    print STDERR &TestUtils::getErrorMsg() if !$test_success;
  ok($test_success, "expected document");

  # Test: do we get trimmed content we expect?
  my $trimmed_onto;
  if (defined $trimmed) {
    &TestUtils::resetErrorMsg();
    $trimmed_onto = &ROQI::Ontology::Tools::trim_ontology($onto);
  #  print STDERR $trimmed_onto->toString(1);
    if ($CAPTURE_OUTPUT) {
      my $file = ">".$trimmed.".test";
      open (OUT, $file); print OUT $trimmed_onto->toString(1); close OUT;
    }
    #open (TRIMMED, $trimmed);
    #my $test_success = &compare_check(*TRIMMED, $trimmed_onto->toString(1),"");
   # close TRIMMED;
    my $expected_trimmed_doc = $PARSER->parse_file($trimmed);
    my $test_success = &TestUtils::compare_nodes($trimmed_onto->documentElement(), $expected_trimmed_doc->documentElement(), "");
    print STDERR &TestUtils::getErrorMsg() if !$test_success;
    ok($test_success, "trimmed document");
  }

  # Test : do we get the fixed content we expect?
  if (defined $fixed && $trimmed_onto) {
    &TestUtils::resetErrorMsg();
    #ROQI::Ontology::Fixer::setDebug(1); #ROQI::Ontology::Fixer::setQuiet(0);
    my $fixed_onto = &ROQI::Ontology::Fixer::fix_ontology_inheritance($trimmed_onto);
    #print STDERR $fixed_onto->toString(1);
    if ($CAPTURE_OUTPUT) {
       my $file = ">".$fixed.".test";
       open (OUT, $file); print OUT $fixed_onto->toString(1); close OUT;
    }
    my $expected_fixed_doc = $PARSER->parse_file($fixed);
    #print STDERR $expected_fixed_doc->toString(1);
    my $test_success = &TestUtils::compare_nodes($fixed_onto->documentElement(), $expected_fixed_doc->documentElement(), "");
    print STDERR &TestUtils::getErrorMsg() if !$test_success;
    ok($test_success, "fixed document");
  }

}

sub compare_check {
  my ($fh, $onto) = @_;

  my @expected = split "\n", $onto;
  my $cnt = 0;
  foreach my $line (<$fh>) {
    chomp $line;
    if (!is ($line, $expected[$cnt])) 
    {
      return 0;
    }
    $cnt = $cnt +1;
    return 1;
  } 

}

sub my_exit {
  my ($signal) = @_;

  done_testing();
  exit $signal;
}
