#!/usr/bin/perl
# Runs Musicfy's Now Playing reader (Frameworks/MusicfyNowPlaying.dylib) inside an Apple
# binary, the only kind of process MediaRemote answers since macOS 15.4.
#   /usr/bin/perl now-playing.pl /path/to/MusicfyNowPlaying.dylib
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV or die "usage: now-playing.pl <dylib>\n";
my $handle = DynaLoader::dl_load_file($library, 0) or die DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "musicfy_now_playing_run") or die DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::run", $symbol);
run();
