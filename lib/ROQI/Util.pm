
package ROQI::Util;

#use XML::LibXML;

sub find_child_elements {
   my ($rootNode) = @_;
   my @found_elements;
   foreach my $child ($rootNode->childNodes) 
   {
         if ($child->nodeType == '1') {
              push @found_elements, $child;
         }
   }
   return @found_elements;
}

sub find_elements ($$$) {
   my ($rootNode, $ns_uri, $tagname) = @_;

   my @found_nodes;
   if ($ns_uri eq "") {
	@found_nodes = $rootNode->getChildrenByTagName($tagname);
   } else {
        @found_nodes = $rootNode->getChildrenByTagNameNS($ns_uri, $tagname);
   }
   #print STDERR "find_elements ns:$ns_uri tag:$tagname got ",$#found_nodes+1," nodes\n";
 
   foreach my $child ($rootNode->childNodes) 
   {
      if ($child->nodeType == '1') {
          @found_nodes = (@found_nodes, &find_elements($child, $ns_uri, $tagname));
      }
   }

   if ($rootNode->localName() eq $tagname) { 
     if ( ($rootNode->namespaceURI() && $rootNode->namespaceURI() eq $ns_uri)
         || (!$rootNode->namespaceURI() && $ns_uri eq '') 
        )
     {
       push @found_nodes, $rootNode;
     }
   }

   return @found_nodes;
}

sub find_text {
   my ($rootNode) = @_;
   my $text = "";
   foreach my $child ($rootNode->childNodes)
   {
      if ($child->nodeType == '3') {
         my $child_text = $child->getValue();
	 $text .= $child->getValue();
#          @found_nodes = (@found_nodes, &find_elements($child, $ns_uri, $tagname));
      }
   }

   $text =~ s/^\s+//;
   $text =~ s/\s+$//;
   return $text;
}

1;

