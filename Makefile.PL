use 5.018000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Message::Multipart',
    VERSION_FROM      => 'lib/Message/Multipart.pm', # finds $VERSION
    PREREQ_PM         => {
       "Carp"         => 0,
       "Encode"       => 0,
       "MIME::QuotedPrint" => 0,
       "MIME::Base64" => 0,
       "Net::SMTP"    => 0
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Message/Multipart.pm', # retrieve abstract from module
       AUTHOR         => 'Tooru Iwasaki <rockbone.g{at}gmail.com>') : ()),
);
