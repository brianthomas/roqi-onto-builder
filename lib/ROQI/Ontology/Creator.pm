#!/usr/bin/perl -w

package ROQI::Ontology::Creator;

use XML::LibXML();
use XML::LibXML::Common qw(:libxml);
use LWP::Simple;
use Scalar::Util;
use List::MoreUtils qw/uniq/;

use ROQI::Util;
use ROQI::Constants;

use IVOA::Ontology::Subject::FilterConcept;
use IVOA::Ontology::Subject::Tokenizer;

IVOA::Ontology::Subject::Tokenizer::setDebug(0);
IVOA::Ontology::Subject::FilterConcept::setDebug(0);
IVOA::Ontology::Subject::FilterConcept::setReportProgress(0);
#IVOA::Ontology::Subject::FilterConcept::setWikipediaEngine('WWW::Wikipedia');
IVOA::Ontology::Subject::FilterConcept::setWikipediaEngine('IVOA::Ontology::Subject::WikipediaSearch');

#
# A small program to extract VO registry resource metadata 
# from cone and siap services into an RDF graph which may
# be used by ROQI for doing subject queries.
#

my $ROQI_NS_URI = &ROQI::Constants::roqi_uri();
my $UCD_NS_URI = &ROQI::Constants::ucd_uri();
my $REGISTRY_ONTO_NS_URI = &ROQI::Constants::registry_resource_uri();
my $RDF_NS_URI = &ROQI::Constants::rdf_uri();

# all of these uri's are defined by the IVOA
my $REGISTRY_NS_URI = 'http://www.ivoa.net/xml/RegistryInterface/v1.0';
my $RESOURCE_NS_URI = 'http://www.ivoa.net/xml/VOResource/v1.0';
my $CONESEARCH_NS_URI = 'http://www.ivoa.net/xml/ConeSearch/v1.0';
my $SIA_NS_URI = 'http://www.ivoa.net/xml/SIA/v1.0';
my $VODataService_NS_URI = 'http://www.ivoa.net/xml/VODataService/v1.0';
my $CS_ID = 'ivo://ivoa.net/std/ConeSearch';
my $SIAP_ID = 'ivo://ivoa.net/std/SIA';
my $STATUS_ATTR = 'status';

my $IDENTIFIER_ATTRIB_NAME = "identifier";
my $ROLE_ATTRIB_NAME = "role";
my $STANDARDID_ATTRIB_NAME = "standardID";
my $USE_ATTRIB_NAME = "use";
my $VALIDATED_BY_ATTRIB_NAME = "validatedBy";
my $XSITYPE_ATTRIB_NAME = "type";

# this is the name of the "Subject" ontology class
my $SUBJECT_CLASS_NAME = 'subject';
# this is the name of the "Resource" ontology class
my $RESOURCE_CLASS_NAME = 'Resource';

my $ACCESSURL_TAGNAME = 'accessURL';
my $DESCRIPTION_TAGNAME = 'description';
my $CAPABILITY_TAGNAME = 'capability';
my $COLUMN_TAGNAME = 'column';
my $CONTENT_TAGNAME = 'content';
my $COVERAGE_TAGNAME = 'coverage';
my $CURATION_TAGNAME = 'curation';
my $FOOTPRINT_TAGNAME = 'footprint';
my $IDENTIFIER_TAGNAME = 'identifier';
my $INTERFACE_TAGNAME = 'interface';
my $NAME_TAGNAME = 'name';
my $PARAM_TAGNAME = 'param';
my $QUERYTYPE_TAGNAME = 'queryType';
my $RESOURCE_TAGNAME = 'Resource';
my $RESULTTYPE_TAGNAME = 'resultType';
my $RIGHTS_TAGNAME = 'rights';
my $SHORTNAME_TAGNAME = 'shortName';

# this is the name of the subject node in the Registry resource document
my $SUBJECT_TAGNAME = 'subject';
my $TABLE_TAGNAME = 'table';
my $TESTQUERY_TAGNAME = 'testQuery';
my $TITLE_TAGNAME = 'title';
my $UCD_TAGNAME = 'ucd';
my $UNIT_TAGNAME = 'unit';
my $VALIDATION_LEVEL_TAGNAME = "validationLevel";
my $VERBOSITY_TAGNAME = "verbosity";
my $WAVEBAND_TAGNAME = "waveband";


my %UCD1plusMap = ( 
#   'POS_EQ_RA_MAIN' => "pos.eq.ra;meta.main",
   'POS_EQ_RA_MAIN' => "pos.eq.ra",
#   'POS_EQ_DEC_MAIN' => "pos.eq.dec;meta.main",
   'POS_EQ_DEC_MAIN' => "pos.eq.dec",
   '(unassigned)' => "",
);

my %SubjectAvailUCD;
my %DocHasUCDDefined;

my $DEBUG = 0; # will print warning messages if set
my $QUIET = 1;
my $ABBREVIATED_RESOURCE = 0; # if true will write only the id of the resource to the file

#
# B E G I N 
#

#die "usage: $0 <resource_file1.xml> <resource_file2.xml> .. <resource_fileN.xml>\n" unless ($#ARGV > -1);

sub setDebug { $DEBUG = shift; }
sub setQuiet { $QUIET = shift; }

sub create_ontology_from_files {
  my (@resource_xml_files) = @_;

  my $Ontology_doc = &print_preamble(XML::LibXML::Document->new('1.0','UTF-8'));
  foreach my $file (@resource_xml_files) {
    # parse/load the file
    print STDERR "Doing : $file\n" unless $QUIET or $DEBUG;
    my $PARSER = XML::LibXML->new();
    my $doc = $PARSER->parse_file($file);
    my $rootNode = $doc->documentElement();
    foreach my $resource_node (&ROQI::Util::find_elements($rootNode, $REGISTRY_NS_URI, $RESOURCE_TAGNAME)) {
      &extract_metadata_from_resource_doc($file,$resource_node, $Ontology_doc); 
    }
    # second pass in case they didnt specify the namespace properly
    foreach my $resource_node (&ROQI::Util::find_elements($rootNode, '', $RESOURCE_TAGNAME)) {
      &extract_metadata_from_resource_doc($file, $resource_node, $Ontology_doc);
    }
  }

  &print_postamble($Ontology_doc);

  return $Ontology_doc; #->toString(1);
}


#
# S U B R O U T I N E S 
#

sub extract_metadata_from_resource_doc($) {
   my ($name, $resource_node, $doc) = @_;
   
   $name =~ s/.xml//;
   my $status = $resource_node->getAttribute($STATUS_ATTR);
   if (!$status or $status ne 'active') {
       # we only want active resources, return otherwise
       print STDERR " NO status attribute?? returning\n" unless $QUIET;
       return;
   }

   # create resource metadata obj
   my $resource = new Resource ($resource_node);
#   print STDERR $resource->dump("\t");

   # gather up UCDs
   my @ucds; # = getUCDsFromResource($resource);

   # gather up subjects
   my @subject;
   my @raw_subj;
   foreach my $subjectNode ($resource_node->getElementsByTagName($SUBJECT_TAGNAME)) {
      push @raw_subj, ROQI::Util::find_text($subjectNode);
   }
   print STDERR "RAW SUBJECTS : ", join ',', @raw_subj, "\n" if $DEBUG;

   # tokenize subjects
   my @tokenized_subj = &IVOA::Ontology::Subject::Tokenizer::tokenize(@raw_subj); 
   print STDERR "TOKENIZED SUBJECTS : ", join ',', @tokenized_subj, "\n" if $DEBUG;

   #filter subjects
   my @filtered_subj = &IVOA::Ontology::Subject::FilterConcept::filter(@tokenized_subj);
   print STDERR "FILTERED SUBJECTS : ", join ',', @tokenized_subj, "\n" if $DEBUG;
   push @subject, @filtered_subj;

   # do unique, alphabetical sort
   my @sorted_subject = uniq sort { lc($a) cmp lc($b) } @subject;
   my $subj_id = getSubjectURI(\@sorted_subject);
   my $label = join " ", map (ucfirst, @sorted_subject);
   my $subject_elem = &get_subject_elem($doc, $subj_id, $label, \@sorted_subject);

   # add availUcd which don't yet exist to the subject element
   my $sub_id = $subject_elem->getAttribute("rdf:ID");
   foreach my $ucd (@ucds) { 
      if (!&subject_has_available_ucd($sub_id,$ucd)) 
      {
         print STDERR "Is NOT added yet, so lets create the hasAvailableUCD node for id:($sub_id) ucd:($ucd)\n" if $DEBUG;
         my $has_ucd_prop_node = createAvailableUCDNode($doc, $UCD_NS_URI."#".$ucd); 
         if ($has_ucd_prop_node) {
            print STDERR "Adding Created hasAvailableUCD node for $sub_id $ucd\n" if $DEBUG;
            $subject_elem->addChild($has_ucd_prop_node);
         }
      }
   }

   # add this resource (and its various capabilities) to the subject
   my $res_id = $name;
   $res_id =~ s/[\.-\/\s]/_/g;
   my $new_resource = createResourceIndividual($doc, $resource, $res_id, \@ucds );
   if ($new_resource) {

      my $subcls = addElement($doc,$subject_elem,"rdfs:subClassOf");
      my $rest = addElement($doc,$subcls,"owl:Restriction");
      my $onprop = addElement($doc,$rest,"owl:onProperty");

      my $objprop = addElement($doc,$onprop,"owl:ObjectProperty");
      $objprop->setAttribute("rdf:about","#hasResource");

      my $hasVal = addElement($doc,$rest,"owl:hasValue");
      $hasVal->addChild($new_resource);

   } else {
      my $subjectURI = getSubjectURI(\@sorted_subject);
      print STDERR "Problem creating resource for subject:[$subjectURI], resource not added.\n";
   } 

}

sub getSubjectURI ($) {
   my ($subj_arr_ref) = @_;
   my $subjectURI = join '.', @{$subj_arr_ref};
   return getSubjectURI_str($subjectURI);
}

sub getSubjectURI_str ($) {
  my ($subjectURI) = @_;
  $subjectURI =~ s/ /_/g; # remove all whitespace
  return $subjectURI;
}

sub getUCDsFromResource($) {
   my ($resource) = @_;

   return unless 
   my @ucds;
   if (defined $resource->getCapabilities()) 
   {

     my @capabilities = @{$resource->getCapabilities()};
     if ($#capabilities > -1) {
        foreach $capability (@capabilities)
        {

           my $standardID = $capability->getStandardId();
           if (!$standardID)
           {
                print STDERR "Resource:",$resource->getIdentifier()," has a capability with no standardID, skipping\n" if $DEBUG;
           }
           elsif ($standardID eq $CS_ID)
           {
                push @ucds, &extract_conesearch_metadata($capability);
           }
           elsif($standardID eq $SIAP_ID)
           {
                push @ucds, &extract_siap_metadata($capability);
           }
           else
           {
		$name = "UNDEFINED" unless (defined $name);
                print STDERR "Resource:$name lacks a known capability, skipping\n" if $DEBUG;
           }
        }
     }
#   elsif ($#table_nodes > -1)
#   {
#        foreach my $table_node (@table_nodes) { &extract_cds_table_metadata($table_node); }
#   }
     else
     {
        print STDERR "Resource: $name lacks any capability or table nodes, skipping\n" if $DEBUG;
     }

   }

   return @ucds;
}

sub createResourceIndividual ($$) {
   my ($doc, $r, $id, $ucds_ref)  = @_;

   my @ucds = @{$ucds_ref};
   my $rnode = $doc->createElement("r:".$RESOURCE_CLASS_NAME);
   $rnode->setAttribute("rdf:ID", $id);

if (!$ABBREVIATED_RESOURCE) 
{
   addSimpleURIElement($doc, $rnode, 'r:identifier', $r->getIdentifier());
   addSimpleStringElement($doc, $rnode, 'r:shortName', $r->getShortName());
   addSimpleStringElement($doc, $rnode, 'rdfs:comment', $r->getContent()->getDescription());
   addSimpleStringElement($doc, $rnode, 'r:title', $r->getTitle());
   addSimpleStringElement($doc, $rnode, 'r:rights', $r->getRights());

   addCoverageElement($doc,$rnode,$r, $id."_cov");

   # validation level
   addValidationLevelElement($doc,$rnode,$r,$id."_val");

   # capabilities
   my $i = 0;
   if ($r->getCapabilities()) {
      for my $capability (@{$r->getCapabilities()}) {
         addCapabilityElement($doc,$rnode,$capability, $id."_cap".$i);
         $i++;
      }
   }
}

   # hasUCD
   for my $ucd (uniq sort @ucds) {
      print STDERR "hasUCD:[$ucd]\n" unless $QUIET;
      addHasUCDElement($doc,$rnode,$ucd);
   }

   print STDERR "Create Individual resource from resource node:",$rnode->tagName(),"\n" if $DEBUG;

   return $rnode;
}

sub addCapabilityElement($$$$) {
   my ($doc,$rnode,$capability,$id) =@_;

   my $prop_node = addElement ($doc, $rnode, "r:hasCapability");
   my $cap_node = addElement ($doc, $prop_node, "r:Capability");
   $cap_node->setAttribute("rdf:ID",$id);

   addSimpleURIElement($doc, $cap_node, 'r:standardId', $capability->getStandardId());
   addSimpleStringElement($doc, $cap_node, 'xsi:type', $capability->getType());

   addInterfaceElement($doc,$cap_node,$capability->getInterface(),$id."iface");

}

sub addInterfaceElement ($$$$) {
   my ($doc,$cap_node,$iface,$id) = @_;


   my $prop_node = addElement ($doc, $cap_node, "r:hasInterface");
   my $i_node = addElement ($doc, $prop_node, "r:Interface");
   $i_node->setAttribute("rdf:ID",$id);

   if (defined $iface) {
     addSimpleStringElement($doc, $i_node, 'xsi:type', $iface->getType());
     addSimpleStringElement($doc, $i_node, 'r:queryType', $iface->getQueryType());
     addSimpleStringElement($doc, $i_node, 'r:resultType', $iface->getResultType());
     addSimpleStringElement($doc, $i_node, 'r:role', $iface->getRole());

     #accessURL
     my $au_prop_node = addElement ($doc, $i_node, "r:hasAccessURL");
     my $au_node = addElement ($doc, $au_prop_node, "r:AccessURL");
     $au_node->setAttribute("rdf:ID",$id."_aurl");
   
     addSimpleStringElement($doc, $au_node, 'r:use', $iface->getAccessUrl()->getUse());
     addSimpleURIElement($doc, $au_node, 'r:url', $iface->getAccessUrl()->getValue());
   }

}

sub addHasUCDElement($$$) {
   my ($doc,$rnode,$ucd) = @_;

   my $prop_node = addElement ($doc, $rnode, "hasUCD");
   my $ucd_node = addElement ($doc, $prop_node, "ucd:".$ucd);

   my $id = $ucd."_0";
   if (exists $DocHasUCDDefined{$id}) 
   {
      $ucd_node->setAttribute("rdf:about","#".$id);
   } 
   else 
   {
      $DocHasUCDDefined{$id} = 1;
      $ucd_node->setAttribute("rdf:ID",$id);
   }

}

sub addCoverageElement ($$$$) {
   my ($doc, $rnode, $r, $id) = @_;

   if (defined $r->getCoverage()) {
     my $cov_prop_node = addElement($doc,$rnode,"r:hasCoverage");
     my $cov_node = addElement($doc,$cov_prop_node,"r:Coverage");
     $cov_node->setAttribute("rdf:ID",$id);
     addSimpleURIElement($doc, $cov_node, 'r:footprint', $r->getCoverage()->getFootPrint());
     addSimpleStringElement($doc, $cov_node, 'r:waveband', $r->getCoverage()->getWaveband());
   }

}

sub addValidationLevelElement ($$$$) {
   my ($doc,$rnode,$r,$id) = @_;

   if (defined $r->getValidationLevel()) {
      my $vl_prop_node = addElement($doc,$rnode,"r:hasValidationLevel");
      my $vl_node = addElement($doc,$vl_prop_node,"r:ValidationLevel");
      $vl_node->setAttribute("rdf:ID",$id);

      addSimpleStringElement($doc, $vl_node, 'r:value', $r->getValidationLevel()->getValue());
      addSimpleURIElement($doc, $vl_node, 'r:validatedBy', $r->getValidationLevel()->getValidatedBy());
   }
}

sub addElement ($$$) {
  my ($doc, $p, $tag) = @_;
  my $new_node = $doc->createElement($tag);
  $p->addChild($new_node);
  return $new_node;
}
 
sub addSimpleStringElement($$$$) {
   return addSimpleElement (@_,"http://www.w3.org/2001/XMLSchema#string");
}

sub addSimpleURIElement($$$$) {
   return addSimpleElement (@_,"http://www.w3.org/2001/XMLSchema#anyURI");
}

sub addSimpleElement($$$$$) {
   my ($doc, $p, $tag, $text, $dt) = @_;

   my $new_elem;
   if (defined $text) {
     $new_elem = addElement($doc, $p, $tag);
     $new_elem->setAttribute("rdf:datatype",$dt);

     my $new_txt = $doc->createTextNode($text);
     $new_elem->addChild($new_txt);
   }

   return $new_elem;
}

sub subject_has_available_ucd($$) {
   my ($subject,$ucd) = @_;

   print STDERR "check_avail_ucd($subject,$ucd)\n" if $DEBUG;
   if (!exists $SubjectAvailUCD{$subject}) 
   {
      my %new_avail_ucds;
      $new_avail_ucds{$ucd} = 1;
      $SubjectAvailUCD{$subject} = \%new_avail_ucds;
   } else {
      my $avail_ucds_ref = $SubjectAvailUCD{$subject};
      my %avail_ucds = %{$avail_ucds_ref};
      if (exists $avail_ucds{$ucd}) 
      {
         return 1;
      } else {
         $avail_ucds{$ucd} = 1;
         $SubjectAvailUCD{$subject} = \%avail_ucds;
      }
   }
   return 0;
}

# find the subject elem, if it doesnt exist yet, 
# then create it, and insert it in the document.  
#
sub get_subject_elem {
  my ($doc, $id, $label, $subject_arr_ref) = @_;
  my $subject_node;

  # search for existing node in current class defs 
  my @current_subjects = $doc->documentElement->getElementsByTagName("owl:Class");
  foreach my $sn (@current_subjects) {
     if ($id eq $sn->getAttribute("rdf:ID")) {
        $subject_node = $sn;
        last;
     }
  } 

  # create the node if it doesnt already exist
  if (!defined $subject_node) {
    $subject_node = createSubjectNode($doc,$id,$label, $subject_arr_ref);
  }

  return $subject_node;
}

sub createSubjectNode($$$$) {
    my ($doc, $id, $label, $subj_arr_ref) = @_;

    print STDERR " create Subject:[$id]\n" if $DEBUG;
    my $subject_node = $doc->createElement("owl:Class");
    $subject_node->setAttribute("rdf:ID", $id);
    $doc->documentElement()->addChild($subject_node);

    my $label_node = addElement($doc,$subject_node,"rdfs:label");
    $label_node->addChild($doc->createTextNode($label));

   return $subject_node;
}

sub createAvailableUCDNode($$) {
   my ($doc,$ucdUri) = @_; 

   my $has_ucd_prop_node = $doc->createElement("rdfs:subClassOf");

   my $rest_node = addElement($doc,$has_ucd_prop_node,"owl:Restriction"); 

   my $svfNode = addElement($doc,$rest_node,"owl:someValuesFrom");
   $svfNode->setAttribute("rdf:resource",$ucdUri);

   my $onPropNode = addElement($doc, $rest_node, "owl:onProperty");

   my $objPropNode = addElement($doc,$onPropNode,"owl:ObjectProperty");
   $objPropNode->setAttribute("rdf:about","#hasAvailableUcd");

   return $has_ucd_prop_node;
}

sub extract_cds_table_metadata ($) {
    my ($table_node) = @_;

#            <vs:column>
#              <name>recno</name>
#              <description>Record number within the original table (starting from 1)</description>
#              <unit> </unit>
#              <ucd>RECORD</ucd>
#            </vs:column>

   foreach my $column_node (&ROQI::Util::find_elements ( $table_node, $VODataService_NS_URI, $COLUMN_TAGNAME)) {
       my @name = $column_node->getElementsByTagName($NAME_TAGNAME);
       my @desc = $column_node->getElementsByTagName($DESCRIPTION_TAGNAME);
       my @unit = $column_node->getElementsByTagName($UNIT_TAGNAME);
       my @ucd = $column_node->getElementsByTagName($UCD_TAGNAME);

       print STDOUT "<FIELD";
       if ($#name == 0) {
           print STDOUT " name=\"".&ROQI::Util::find_text($name[0])."\"";
       }
       if ($#unit == 0) {
           print STDOUT " unit=\"".&ROQI::Util::find_text($unit[0])."\"";
       }
       if ($#ucd == 0) {
           print STDOUT " ucd=\"".&ROQI::Util::find_text($ucd[0])."\"";
       }
       print STDOUT ">\n";
       if ($#desc == 0) {
           print STDOUT $desc[0]->toString()."\n";
       }
       print STDOUT "</FIELD>\n";
   } 
}

sub extract_siap_metadata($) {
   my ($capability_node) = @_;

   my @ucds;
   my $interface = $capability->getInterface();
   if ((!$interface->getQueryType() || $interface->getQueryType() eq 'GET')
            &&
           (!$interface->getResultType()
               || $interface->getResultType() eq 'text/xml' 
               || $interface->getResultType() eq 'text/xml+votable' 
               || $interface->getResultType() eq 'application/xml+votable'
           )
   ) {

            my $url = $interface->getURL()."format=metadata"; 
            print STDERR " * Resolving metadata from siap service at: $url\n" if $DEBUG;
            my $votable = get $url;
            my $PARSER = XML::LibXML->new();
            my $votable_doc;
            eval {
                 $votable_doc = $PARSER->parse_string($votable);
            };
	    if (defined $@ and $@) {
              # could'nt marshal an XML document, bad encoding, something else??
              warn "  Skipping interface node in siap metadata because :",$@;
            } elsif (defined $votable_doc) {
              my $rootNode = $votable_doc->documentElement();
              foreach my $fieldNode (&ROQI::Util::find_elements($rootNode, '', 'FIELD')) {
                     # print STDOUT $fieldNode->toString(), "\n";
                     my @found_ucds = extract_ucd_from_field($fieldNode);
                     if ($#found_ucds > -1) { push @ucds, @found_ucds; }
              }
            }
   }
   else
   {
           print STDERR "Ignoring siap interface with odd config: ",$interface->dump("\t"),"\n" if $DEBUG;
   }
   return @ucds;

}

sub extract_conesearch_metadata($) {
   my ($capability) = @_;
 
   my @ucds;
   my $interface = $capability->getInterface();
   if ((!$interface->getQueryType() || $interface->getQueryType() eq 'GET')
            && 
           (!$interface->getResultType() 
               || $interface->getResultType() eq 'text/xml'
               || $interface->getResultType() eq 'text/xml+votable' 
               || $interface->getResultType() eq 'application/xml+votable')
   ) {

            my $tsq = $capability->getTestQuery();
            if ($tsq) {
               my $url = $interface->getURL()
			. "RA=". $tsq->{'ra'}
			. "&DEC=". $tsq->{'dec'}
			. "&SR=". $tsq->{'sr'}
	       ;
               print STDERR " * Resolving metadata from conesearch service at: $url\n" if $DEBUG;
               my $votable = get $url;
   	       my $PARSER = XML::LibXML->new();
	       my $votable_doc;
	       eval { 
 		 $votable_doc = $PARSER->parse_string($votable);
	       }; 
	       if (defined $@ and $@) {
                   # could'nt marshal an XML document, bad encoding, something else??
                   warn "  Skipping conesearch metadata because :",$@;
               } elsif (defined $votable_doc) { 
                 my $rootNode = $votable_doc->documentElement();
                 foreach my $fieldNode (&ROQI::Util::find_elements($rootNode, '', "FIELD")) {
                     # print STDOUT $fieldNode->toString(), "\n";
                     my @found_ucds = extract_ucd_from_field($fieldNode);
                     if ($#found_ucds > -1) { push @ucds, @found_ucds; }
                 }
               }

            } 
            else 
            {
                print STDERR "Ignoring conesearch, missing test query: ",$interface->dump("\t"),"\n" if $DEBUG; 
            }

    } 
    else
    {
           print STDERR "Ignoring conesearch interface with odd config: ",$interface->dump("\t"),"\n" if $DEBUG; 
    } 

#   my $metadata = get $interface->accessURL . "format=metadata";

   return @ucds;
}

sub extract_ucd_from_field($) {
   my ($field_elem) = @_;
   my $ucd;
   my @found_ucds;

   # in CDS metadata, they put the actual ucd in a comment!
   # NOTE: does not appear to be the case anymore, whew!
#   my $field_comment = get_first_comment($field_elem); 
#   if ($field_comment) {
#      my $comment_txt = $field_comment->nodeValue();
#      if ($comment_txt =~ m/.*ucd="(.+)".*/) {
#         print "FIELD COMMENT:",$1,"\n";
#         $ucd = $1;
#      }
#   }

   # most keep the ucd in the field attribute
   if (not $ucd) {
       my $fld_ucd = $field_elem->getAttribute("ucd"); 
       if ($fld_ucd) {
           $ucd = $fld_ucd;
       }
   }

   if ($ucd) {
       #print STDERR "RECTIFY UCD:$ucd\n";

       # there may be multiple ucds as a 'word'. Need
       # to parse each separately
       my @ucds = split ";",$ucd;
       foreach my $u (@ucds) {

          #print STDERR "CHECK ucd:$u\n";

          # remap, if needed
          $u = &remap_ucd_to_1plus($u);

          # now change to id for UCD onto 
          $u =~ s/\?//g;
          $u =~ s/ //g;
          $u =~ s/\.//g;
          $u =~ s/-//g;
          $u = lc $u;
          $u = ucfirst $u;

          if ($u eq '' || $u =~ m/[\?,\/\\]/) {
            print STDERR "Warning: found illegal UCD:$u, ignoring\n";
          } else {
            push @found_ucds, $u;
          }
       }
   }

   return @found_ucds;
}

# normalize the values of the ucd's to 1+ standard
sub remap_ucd_to_1plus($) {
   my ($ucd) = @_;
#   print "TEST REMAP of [$ucd] [",$UCD1plusMap{$ucd},"]\n";
   if ( exists $UCD1plusMap{$ucd}) {
     $ucd = $UCD1plusMap{$ucd};
   } 
   return $ucd;
}

sub get_first_comment($) {
   my ($node) = @_; 
   foreach my $child ($node->getChildNodes()) {
      if ($child->nodeType == XML_COMMENT_NODE) {
        return $child;
      }
   }
}

sub print_preamble ($) {
   my ($doc) = @_;
    
   my $root = $doc->createElement("rdf:RDF"); 
   $doc->setDocumentElement($root);
   $root->setAttribute('xmlns:rdf', $RDF_NS_URI);
   $root->setAttribute('xmlns:owl', 'http://www.w3.org/2002/07/owl#');
   $root->setAttribute('xmlns:rdfs','http://www.w3.org/2000/01/rdf-schema#');
   $root->setAttribute('xmlns:xsd', 'http://www.w3.org/2001/XMLSchema#');
   $root->setAttribute('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance#');
   $root->setAttribute('xmlns:ucd', $UCD_NS_URI."#");
   $root->setAttribute('xmlns:r', $REGISTRY_ONTO_NS_URI."#");
   $root->setAttribute('xmlns', $ROQI_NS_URI.'#');
   $root->setAttribute('xml:base', $ROQI_NS_URI);

   my $onto_decl = addElement($doc,$root,"owl:Ontology");
   $onto_decl->setAttribute("rdf:about","");

   my $onto_import_ucd = addElement($doc,$onto_decl, "owl:imports");
   $onto_import_ucd->setAttribute("rdf:resource",$UCD_NS_URI);
  
   my $onto_import_reg = addElement($doc,$onto_decl,"owl:imports");
   $onto_import_reg->setAttribute("rdf:resource",$REGISTRY_ONTO_NS_URI);

   my $onto_comment = addElement($doc,$onto_decl,"rdfs:comment");
   $onto_comment->setAttribute("rdf:datatype","http://www.w3.org/2001/XMLSchema#string");
   my $onto_comment_txt = $doc->createTextNode("ROQI application ontology.");
   $onto_comment->addChild($onto_comment_txt);

   my $subject_decl = addElement($doc,$root,"owl:Class");
   $subject_decl->setAttribute("rdf:ID",$SUBJECT_CLASS_NAME);

   #print STDERR $doc->toString(1);
   return $doc;

}

sub print_postamble ($) {
   my ($doc) = @_;
 
   my $root = $doc->documentElement();
   #$root->addChild(
   #   createObjPropNode($doc,"hasAvailableUcd", $UCD_NS_URI."#UCD","#".$SUBJECT_CLASS_NAME)
   #);

   #$root->addChild(
   #   createObjPropNode($doc,"hasUCD", $UCD_NS_URI."#UCD",$REGISTRY_ONTO_NS_URI."#".$RESOURCE_TAGNAME)
   #);

   $root->addChild(
      createObjPropNode($doc,"hasResource", $REGISTRY_ONTO_NS_URI."#".$RESOURCE_TAGNAME, "#".$SUBJECT_CLASS_NAME)
   );
}

sub createObjPropNode {
   my ($doc, $id, $range, $domain) = @_;

   my $objPropNode = $doc->createElement("owl:ObjectProperty");
   $objPropNode->setAttribute("rdf:ID",$id);

   my $rangeNode = addElement($doc,$objPropNode,"rdfs:range");
   $rangeNode->setAttribute("rdf:resource",$range);

   my $domainNode = addElement($doc,$objPropNode,"rdfs:domain");
   $domainNode->setAttribute("rdf:resource",$domain);

   return $objPropNode;

}

1;

package Resource;

sub new ($) {
   my ($proto,$cap_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($cap_node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   $self->{$CAPABILITY_TAGNAME} = ();
   foreach my $child (&ROQI::Util::find_child_elements($cap_node))
   {
      my $fieldname = $child->localname();
      if ($fieldname eq $CAPABILITY_TAGNAME) {
         push @{$self->{$CAPABILITY_TAGNAME}}, new Capability ($child);
      } elsif ($fieldname eq $CONTENT_TAGNAME) {
         $self->{$CONTENT_TAGNAME} = new Content ($child);
      } elsif ($fieldname eq $COVERAGE_TAGNAME) {
         $self->{$COVERAGE_TAGNAME} = new Coverage ($child);
      } elsif ($fieldname eq $CURATION_TAGNAME) {
         $self->{$CURATION_TAGNAME} = new Curation ($child);
      } elsif ($fieldname eq $VALIDATION_LEVEL_TAGNAME) {
         $self->{$VALIDATION_LEVEL_TAGNAME} = new ValidationLevel ($child);
      } else {
         $self->{$fieldname} = &ROQI::Util::find_text($child);
      }
   }
   return $self;

}

sub getIdentifier() { return shift->{$IDENTIFIER_ATTRIB_NAME}; }
sub getShortName() { return shift->{$SHORTNAME_TAGNAME}; }
sub getTitle() { return shift->{$TITLE_TAGNAME}; }
sub getRights() { return shift->{$RIGHTS_TAGNAME}; }
sub getCapabilities () { my ($self)=@_; return $self->{$CAPABILITY_TAGNAME}; }
sub getCoverage() { return shift->{$COVERAGE_TAGNAME}; }
sub getCuration() { return shift->{$CURATION_TAGNAME}; }
sub getContent() { return shift->{$CONTENT_TAGNAME}; }
sub getValidationLevel() { return shift->{$VALIDATION_LEVEL_TAGNAME}; }

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
       next unless $key;
       $dump .= $indent . $key. " => ";
       if (Scalar::Util::blessed($self->{$key})) {
          $dump .= "\n\t".$indent. $self->{$key}->dump($indent."\t\t")."\n";
       } elsif ($self->{$key} =~ m/ARRAY/) {
          my @arr = @{$self->{$key}};
          foreach my $item (@arr) {
             $dump .= "\n\t".$indent.$item->dump($indent."\t\t")."\n";
          }
       } else {
          $dump .= $self->{$key}."\n";
       }
   }
   return $dump;
}

1;

package Content;

sub new ($) {
   my ($proto,$cap_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($cap_node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   foreach my $child (&ROQI::Util::find_child_elements($cap_node))
   {
      my $fieldname = $child->localname();
      $self->{$fieldname} = &ROQI::Util::find_text($child);
   }
   return $self;
}

sub getDescription() { return shift->{$DESCRIPTION_TAGNAME}; }

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
          $dump .= $indent . $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}


1;

package Curation;

sub new ($) {
   my ($proto,$cap_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($cap_node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   foreach my $child (&ROQI::Util::find_child_elements($cap_node))
   {
      my $fieldname = $child->localname();
      $self->{$fieldname} = &ROQI::Util::find_text($child);
   }
   return $self;

}

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
          $dump .= $indent . $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}

1;

package Coverage;

sub new ($) {
   my ($proto,$cap_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($cap_node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   foreach my $child (&ROQI::Util::find_child_elements($cap_node))
   {
      my $fieldname = $child->localname();
      $self->{$fieldname} = &ROQI::Util::find_text($child);
   }
   return $self;
}

sub getFootPrint() { return shift->{$FOOTPRINT_TAGNAME}; };
sub getWaveband() { return shift->{$WAVEBAND_TAGNAME}; };

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
          $dump .= $indent . $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}

1;

package Capability;

sub new ($) {
   my ($proto,$cap_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($cap_node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }
 
   foreach my $child (&ROQI::Util::find_child_elements($cap_node))
   {
      my $fieldname = $child->localname();
      if ($fieldname eq $INTERFACE_TAGNAME) {
         $self->{$INTERFACE_TAGNAME} = new Interface($child);
      } elsif ($fieldname eq $TESTQUERY_TAGNAME) {
         $self->{$TESTQUERY_TAGNAME} = new TestQuery ($child);
      } else {
         $self->{$fieldname} = &ROQI::Util::find_text($child);
      }
   }
   return $self;

}

sub getStandardId() { return shift->{$STANDARDID_ATTRIB_NAME}; }
sub getType () { return shift->{$XSITYPE_ATTRIB_NAME}; }
sub getVerbosity() { return shift->{$VERBOSITY_TAGNAME}; }
sub getInterface () { return shift->{$INTERFACE_TAGNAME}; }
sub getTestQuery() { return shift->{$TESTQUERY_TAGNAME}; }

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
       $dump .= $indent . $key. " => ";
       if (Scalar::Util::blessed($self->{$key})) {
          $dump .= $self->{$key}->dump($indent."\t")."\n";
       } else {
          $dump .= $self->{$key}."\n";
       }
   }
   return $dump;
}

1;

package Interface;

sub new ($) {
   my ($proto,$interface_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($interface_node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   $self->{$PARAM_TAGNAME} = ();
   foreach my $child (&ROQI::Util::find_child_elements($interface_node))
   {
      my $fieldname = $child->localname();
      if ($fieldname eq $PARAM_TAGNAME) {
         push @{$self->{$PARAM_TAGNAME}}, &ROQI::Util::find_text($child);
      } elsif ($fieldname eq $ACCESSURL_TAGNAME) {
         $self->{$fieldname} = new AccessUrl($child);
      } else {
         $self->{$fieldname} = &ROQI::Util::find_text($child);
      }
     
   }

   return $self;
}

sub getAccessUrl () { return shift->{$ACCESSURL_TAGNAME}; }
sub getQueryType () { return shift->{$QUERYTYPE_TAGNAME}; }
sub getResultType () { return shift->{$RESULTTYPE_TAGNAME}; }
sub getParams() { return shift->{$PARAM_TAGNAME}; }
sub getRole() { return shift->{$ROLE_ATTRIB_NAME}; }
sub getType() { return shift->{$XSITYPE_ATTRIB_NAME}; }

sub getURL () { my ($self) =@_; return $self->getAccessUrl()->getValue(); }

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
        next unless $key;
        next unless $self->{$key};
        $dump .= $indent . $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}

1;

package TestQuery;

sub new ($) {
   my ($proto,$interface_node) = @_;
   my $self = bless ({}, $proto);

   foreach my $child (&ROQI::Util::find_child_elements($interface_node))
   {
      my $fieldname = $child->localname();
      $self->{$fieldname} = &ROQI::Util::find_text($child);
   }

   return $self;
}

sub dump() {
   my ($self) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
          $dump .= "\t". $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}

1;

package ValidationLevel;

sub new ($) {
   my ($proto,$node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   foreach my $child (&ROQI::Util::find_child_elements($node))
   {
      my $fieldname = $child->localname();
      $self->{$fieldname} = &ROQI::Util::find_text($child);
   }

   $self->{'value'} = &ROQI::Util::find_text($node);

   return $self;

}

sub getValue() { return shift->{'value'}; }
sub getValidatedBy() { return shift->{$VALIDATED_BY_ATTRIB_NAME}; }

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
          $dump .= $indent . $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}

1;


package AccessUrl;

sub new ($) {
   my ($proto,$node) = @_;
   my $self = bless ({}, $proto);

   foreach my $attr ($node->getAttributes()) {
      my $atname = $attr->name();
      $self->{$atname} = $attr->value();
   }

   foreach my $child (&ROQI::Util::find_child_elements($node))
   {
      my $fieldname = $child->localname();
      $self->{$fieldname} = &ROQI::Util::find_text($child);
   }

   $self->{'value'} = &ROQI::Util::find_text($node);

   return $self;

}

sub getUse() { return shift->{$USE_ATTRIB_NAME}; }
sub getValue() { return shift->{'value'}; }

sub dump() {
   my ($self, $indent) = @_;
   my $dump = "$self\n";
   foreach my $key (keys %$self) {
          $dump .= $indent . $key. " => ". $self->{$key}."\n";
   }
   return $dump;
}

1;
