#!/usr/bin/perl -w
 
package ROQI::DBTools;

use XML::LibXML();
use XML::LibXML::Common qw(:libxml);
use ROQI::Constants;

# A small program to extract subject/resource metadata into
# an xml format which is suitable for loading into the db

my $DEBUG = 0;

sub setDebug { $DEBUG = shift; }

sub create_dbload_document {
   my ($doc) = @_;

#   my $PARSER = XML::LibXML->new();
#   my $doc = $PARSER->parse_file($file);

   my $res_doc = XML::LibXML::Document->new();
   my $root = $res_doc->createElement("roqidata");
   $root->setAttribute('xmlns:rdf', &ROQI::Constants::rdf_uri());
   $root->setAttribute('xmlns:owl', 'http://www.w3.org/2002/07/owl#');
   $root->setAttribute('xmlns:rdfs','http://www.w3.org/2000/01/rdf-schema#');
   $root->setAttribute('xmlns:xsd', 'http://www.w3.org/2001/XMLSchema#');
   $root->setAttribute('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance#');
   $root->setAttribute('xmlns:ucd', &ROQI::Constants::ucd_uri()."#");
   $root->setAttribute('xmlns:r', &ROQI::Constants::registry_resource_uri()."#");
   $root->setAttribute('xmlns', &ROQI::Constants::roqi_uri().'#');
   $root->setAttribute('xml:base', &ROQI::Constants::roqi_uri());

   $res_doc->setDocumentElement($root);

   my @subjectElements = $doc->documentElement->getElementsByTagName("owl:Class");
   foreach my $elem (@subjectElements) {
      my $new_elem = &createSubjectNode($res_doc, $elem);
      $res_doc->documentElement->addChild($new_elem);
   }

   return $res_doc; #->toString(1);
}

sub createSubjectNode 
{
  my ($doc, $owl_node) = @_;

  my $subj_node = $doc->createElement("subject");
  $subj_node->setAttribute("rdf:ID", $owl_node->getAttribute("rdf:ID"));

  my @resourceElements = $owl_node->getElementsByTagName("r:Resource");
  foreach my $elem (@resourceElements) { $subj_node->addChild($elem); }

  return $subj_node;
}

1;
