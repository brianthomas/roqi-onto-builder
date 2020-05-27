#!/usr/bin/perl -w

package ROQI::Ontology::Fixer;

use XML::LibXML();
use XML::LibXML::Common qw(:libxml);
use LWP::Simple;
use Scalar::Util;
use List::MoreUtils qw/uniq/;
use ROQI::Util;

#
# A small module to fix the sub-classing of subjects
# extracted from VO registry resource metadata 
# It has some nasty global variables, so this software
# is not stable if we run it more than one time within 
# a program 
#

# currently we are performance limited. When we have
# too many terms, the program bogs down 
my $LIMIT_SUBJECT_ASSOCIATION_DEPTH = 9; 

my @DROP_SUBJECTS = qw /a permanent/;
my %IGNORE_SUBJECT;
@IGNORE_SUBJECT{@DROP_SUBJECTS} = ("1") x @DROP_SUBJECTS;

my $SUBJECT_CLASS_NAME = "subject";
 
my %MadeSubclassOfSubject;
my %MadeSubclassOf;
my %ClassElements;
my @REMOVE_NODE;

my $DEBUG = 0; # will print warning messages if set
my $QUIET = 1;

sub setDebug { $DEBUG = shift; }
sub setQuiet { $QUIET = shift; }

sub _reset_globals { 
  %ClassElements = (); 
  %MadeSubclassOf = ();
  %MadeSubclassOfSubject = ();
  @REMOVE_NODE = ();
}

sub fix_ontology_inheritance {
  my ($doc) = @_;

   &_reset_globals();

   # remove unused namespace attributes
   my $root = $doc->documentElement;
   #$root->removeAttribute('xmlns:ucd');
   #$root->removeAttribute('xmlns:r');

   my $cnt = 0;
   my @class_elems = $root->getElementsByTagName("owl:Class");
   # have to copy nodes this way, or it fails
   foreach my $node (@class_elems) { 
     my $orig_id = $node->getAttribute("rdf:ID");
     my $id = &getFixedId($orig_id);

     if (defined $IGNORE_SUBJECT{$id}) 
     {
        # drop it from the Document
        push @REMOVE_NODE, $node;
     }
     else
     { 

        # fix id..
        if ($orig_id ne $id) {
           print STDERR "GOT CHANGED ID old:$orig_id new:$id\n" if $DEBUG;
           $node->removeAttribute("rdf:ID");
           $node->setAttribute("rdf:ID", $id);
        } 

        # in some cases, fixing the id will result
        # in a duplicate class with an existing one.
        # in these cases, we should drop the node
        # from the document
        if (exists $ClassElements{$id}) {
          push @REMOVE_NODE, $node;
        } else {
           $ClassElements{$id} = $node;
        }

     }

   }

   # clean up the trash
   foreach my $remove (@REMOVE_NODE) { 
      print STDERR "REMOVE NODE: ",$remove->getAttribute("rdf:ID"),"\n" if $DEBUG;
      $doc->documentElement->removeChild($remove); 
   }

   # now fix inheritance for remainder
   my $total = $#class_elems+1;
   my @ids = keys %ClassElements;
   foreach my $id (@ids) 
   {
      next if ($id eq $SUBJECT_CLASS_NAME or $id eq ""); 

      print STDERR "Got Class id[$cnt/$total]:$id\n" if $DEBUG;
      &fix_inheritance($doc, $id, $ClassElements{$id});

#    last if ($cnt > 6); 
      $cnt = $cnt+1;
   }

   print STDERR "After fixing there are ",scalar keys %ClassElements," classes in the ontology now.\n" unless $QUIET;

   return $doc;

}

# produce an id comprised of unique, alphabetized subject terms
sub getFixedId($) {
   my ($str) = @_;

   return $SUBJECT_CLASS_NAME if $str eq $SUBJECT_CLASS_NAME;

   # try to insure uniqueness by using a hash  
   my %hash;
   my @terms = split(/\./, $str);

   my @lowercase = map { lc } @terms;
   @hash{@lowercase} = ("") x @lowercase;
   my @alphabetical = sort { lc($a) cmp lc($b) } keys %hash;

   #print STDERR "TERMS:", join "\n", @alphabetical, "\n";

   # currently we are performance limited. When we have
   # too many terms, the program bogs down 
   return join '-', @alphabetical if (scalar @alphabetical > $LIMIT_SUBJECT_ASSOCIATION_DEPTH); 
 
   my @id_keys;
   foreach my $key (@alphabetical) { 
     if (!exists $IGNORE_SUBJECT{$key}) { 
        #push @id_keys, checkSynonym($key);
        push @id_keys, $key;
     }
   }

   my $id = join '.', @id_keys;
   chomp $id;

   print STDERR "FIXED ID $str => $id\n" if $DEBUG;
   return $id;
}

sub fix_inheritance ($$$) {
   my ($doc, $id, $class_elem) = @_;

   print STDERR "fix_inheritance called for subject:$id\n" if $DEBUG;

   my @parent_subjects = split(/\./, $id);
   #print STDERR "PARENT subjs:", join "\n", @parent_subjects, "\n";

   # we iterate over all combos
   foreach my $i (0 .. $#parent_subjects) 
   {
      my $drop_subject = $parent_subjects[$i];
      my $new_subject = "";
      #for my $sub ( sort { lc($a) cmp lc($b) } @parent_subjects) {
      for my $sub ( @parent_subjects) {
         if ($sub ne $drop_subject) { 
            $new_subject = $new_subject . $sub . '.';
         }
      }
      chop $new_subject; 
      
      next if (!defined $new_subject or $new_subject eq "");

      print STDERR "NEW SUBJECT :[$new_subject]\n" if $DEBUG;
      &add_parent_subject($doc,$class_elem,$id,$new_subject);
   }

   # for top classes only
   if ($#parent_subjects == 0) { 
      &check_add_subject_as_superclass($doc,$id,$class_elem);
   }

}

sub add_parent_subject ($$$) 
{
   my ($doc, $class_elem, $id, $parent_subj) = @_;

   my $parent_id = &getSubjectURI_str ($parent_subj);

   my @terms = split (/\./, $parent_subj);
   my @sorted_terms = uniq sort { lc($a) cmp lc($b) } @terms;
   my $parent_label = join " ", map (ucfirst, @sorted_terms);

   # this will create the parent subject node
   my $parent_node = get_subject_elem ($doc, $parent_id, $parent_label);

   if (!defined $parent_node) {
      print STDERR "Cant get parent subject node $parent_subj for $id!! Crashing in a heap!\n"; 
      exit(-1); 
   }

   if (defined $parent_subj and $parent_subj ne "" and $parent_subj ne $id) {

       #print STDERR " add super-class $parent_subj to $id \n" if $DEBUG;
       if (!checkMadeSubclassOf($class_elem, $parent_id)) {

          &fix_inheritance($doc, $parent_id, $parent_node);

          my $parent_sub_subclass_elem = &addElement($doc,$class_elem,"rdfs:subClassOf");
          $parent_sub_subclass_elem->setAttribute("rdf:resource","#".$parent_id);
          setMadeSubclassOf($class_elem, $parent_id);
       }
       
   } 

}

sub checkMadeSubclassOf {
   my ($class_elem, $subj) = @_;
#   print STDERR "CHECKMADESUBCLASSOF $class_elem, $subj\n" if $DEBUG;

   return 0 unless (defined $MadeSubclassOf{$class_elem});

   my %made_subclass = %{$MadeSubclassOf{$class_elem}};

   return $made_subclass{$subj};
}

sub setMadeSubclassOf {
   my ($class_elem, $subj) = @_;

   if (!defined $MadeSubclassOf{$class_elem}) {
      my %hash;
      $MadeSubclassOf{$class_elem} = \%hash;
   }

   my %made_subclass = %{$MadeSubclassOf{$class_elem}};
   $made_subclass{$subj} = 1; 
   $MadeSubclassOf{$class_elem} = \%made_subclass;

} 

sub check_add_subject_as_superclass ($$) {
   my ($doc,$id, $class_elem) = @_;
   if (!exists $MadeSubclassOfSubject{$id}) { 
       #print STDERR " add Subject as superclass of $id total_classes:[",scalar keys %ClassElements,"]\n" if $DEBUG;

       my $parent_sub_subclass_elem = &addElement($doc,$class_elem,"rdfs:subClassOf");
       $parent_sub_subclass_elem->setAttribute("rdf:resource","#".$SUBJECT_CLASS_NAME);

       $MadeSubclassOfSubject{$id} = 1;
   }
}

sub getClassLabelText($) {
   my ($class_elem) = @_;

   my $label;
   my @label_elems = $class_elem->getElementsByTagName("rdfs:label");
   if ($label_elems[0]) { 
     $label = ROQI::Util::find_text($label_elems[0]);
   }
   return $label;
}

sub getSubjectURI_str ($) {
  my ($subjectURI) = @_;
  $subjectURI =~ s/ //g; # remove all whitespace
  return $subjectURI;
}

sub addElement ($$$) {
  my ($doc, $p, $tag) = @_;

#  print STDERR "addElement $tag\n" if $DEBUG;
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

# find the subject elem, if it doesnt exist yet, 
# then create it, and insert it in the document.  
#
sub get_subject_elem {
  my ($doc, $id, $label) = @_;

  # search for existing node in current class defs 
  my $subject_node = find_class_element($doc,$id);

  # create the node if it doesnt already exist
  if (!defined $subject_node) {
     # first, try resorting to fixed Id, and search again 
     my $new_id = &getFixedId($id);
     $subject_node = find_class_element($doc,$new_id);

     # still not found? then create w/ alphabetical id 
     if (!defined $subject_node) {
        $subject_node = createSubjectNode($doc,$id,$label );
        {
           # its a top subject if no '.' 
           &check_add_subject_as_superclass($doc,$id,$subject_node) unless ($id =~ m/\./);
        }
     }
  }

  return $subject_node;
}

sub find_class_element ($) {
  my ($doc,$id) = @_;
  my $class_node;

  $class_node = $ClassElements{$id};
  return $class_node;
}

sub createSubjectNode($$$) {
    my ($doc, $id, $label ) = @_;

#    print STDERR " create Subject:[$id] total_classes:[",scalar keys %ClassElements,"]\n"; # if $DEBUG;
    my $subject_node = $doc->createElement("owl:Class");
    $subject_node->setAttribute("rdf:ID", $id);
    $doc->documentElement()->addChild($subject_node);

    my $label_node = addElement($doc,$subject_node,"rdfs:label");
    $label_node->addChild($doc->createTextNode($label));

    $ClassElements{$id} = $subject_node;
    return $subject_node;
}

1;


