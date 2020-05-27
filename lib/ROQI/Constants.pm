package ROQI::Constants;

my $RDF_NS_URI = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
my $ROQI_NS_URI = 'http://www.ivoa.net/owl/v1.0/registrySubject.owl';
my $REGISTRY_ONTO_NS_URI = 'http://www.ivoa.net/owl/v1.0/registryResource.owl';
my $UCD_NS_URI = 'http://www.ivoa.net/Document/WD/vocabularies/20080222/UCD';

sub rdf_uri() { $RDF_NS_URI; }
sub roqi_uri() { $ROQI_NS_URI; }
sub registry_resource_uri() { $REGISTRY_ONTO_NS_URI; }
sub ucd_uri() { $UCD_NS_URI; }

1;
