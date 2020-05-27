
package ROQI::Ontology::Trimmer;

use XML::LibXML();
use XML::LibXML::Common qw(:libxml);


sub trim_ontology {
  my ($doc) = @_;

   # drop all owl:Restriction elements
   my @restrictionElements = $doc->documentElement->getElementsByTagName("owl:Restriction");
   foreach my $restriction (@restrictionElements)
   {
      my $parent = $restriction->parentNode;
      my $grandparent = $parent->parentNode;
      $grandparent->removeChild($parent);
   }

   my @objectPropElements = $doc->documentElement->getElementsByTagName("owl:ObjectProperty");
   foreach my $obj_prop_node (@objectPropElements)
   {
      my $parent = $obj_prop_node->parentNode;
      $parent->removeChild($obj_prop_node);
   }

   return $doc;

}

1;

