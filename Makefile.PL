use strict;
use ExtUtils::MakeMaker;

WriteMakefile (
  AUTHOR        => 'Arctica Project Developers',
  ABSTRACT      => "Arctica Service: Audio Server PulseAudio",
  NAME          => 'Arctica::Services::Audio::Server::PulseAudio',
  (eval { ExtUtils::MakeMaker->VERSION(6.21) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM     => {
    'Test::More' => '0.47',
  },
  VERSION_FROM  => 'lib/Arctica/Services/Audio/Server/PulseAudio/Version.pm',
  clean               => { FILES => '' },
);
