use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'ROQI',
    license             => 'lgpl',
    dist_author         => 'Brian Thomas <bthomas@noao.edu>',
    dist_abstract       => 'false',
    build_requires => {
        'IVOA::Ontology::Subject' => '1.0', 
        'XML::LibXML::Common' => '1.70',
        'LWP::Simple' => '5.835',
        'Scalar::Util' => '1.22',
        'List::MoreUtils' => '0.22',
        'Test::More' => '0.94',
    },
);

$builder->create_build_script();
