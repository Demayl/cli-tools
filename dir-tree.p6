#!/usr/bin/env perl6
use v6.c;
use Shell::Command; # install panda ( git clone https://github.com/tadzik/panda.git ) # TODO remove it

# Generate Directory tree with files for tests
# See &MAIN() for info about default values
# TODO add some docs and more verbose help

subset Depth    of Int where 3 <= * <= 60 ; # define custom types, or use where clause in signature
subset PosInt   of Int where * > 0;
subset FileSize of Int where 0 < * <= 1024; # Maximum 1GB file allowed

signal(SIGINT).tap({ say "INT catched"; exit 0 }); # Async signal catch

sub random-generator {
    return ('a'..'z',0..9,'A'..'Z').flat.roll(*);
}

sub MAIN($directory!, FileSize :$file-size=10, PosInt :$dir-count=50, Depth :$depth = 3, PosInt :$file-count=500, Bool :$async=True){

    mkdir $directory if $directory.IO !~~ :d ;
    chdir $directory ;

    my PosInt $file-chars = 10;

    my $rand-str        = random-generator[^($file-count*$file-chars)]; # Get enough random chars to fill names
    my IO::Path $root   = $*CWD;
    my Int $total       = $file-count;
    my Str $separator   = $*SPEC.dir-sep;

    my PosInt $file_per_dir = ($file-count / $dir-count).Int; # Int actualy rounds the number
    my Int $left_files      = (( ($file-count / $dir-count) - $file_per_dir ) * $dir-count).Int ;

    my Int @iter        = 1..$dir-count;
    my IO::Path @dirs   = ();
    my Str @names-s[$file-count]       = $rand-str.rotor($file-chars).map({ .join ~ '.txt' }).unique; # Make sub-arrays with $file-chars elems to make file names

# Use sized array to keep the size to "pop" from
    my Str @names = @names-s; # TODO re-generate repeated names ( In that form they are in the end of array )

    my Promise @procs;

    say "$file-count files will be created ( $file_per_dir per dir ) - Total " ~ ($file-count*$file-size) ~ " MB space";

    while @iter.shift -> $fol is copy {
        $fol ~= @iter.elems ?? $separator ~ @iter.shift !! '' for ^$depth;
        @dirs.push: IO::Path.new( $fol );
    }

    for @dirs -> $dir {
        mkpath( $dir.abspath ); # mkdir -p 'absolute path'

        my Str @subdirs = $dir.Str.split: $separator; # split relative directories

        while @subdirs.pop -> $subdir {
            temp $file_per_dir ; # copy will live only one iteration in current block
            $file_per_dir++ if $left_files; # 0 Int is false, "0" Str is true

            my IO::Path $cur-dir    .= new( (|@subdirs,$subdir).join($separator) );
            my Block $dest-file     := -> { $*SPEC.join('', $cur-dir.abspath, @names.pop // random-generator[^$file-chars].join ~ '.txt' ) };
            
            # Windows server has another tool - 'CREATFIL.EXE'
            #TODO make it with pipe or use C posix_fallocate() <fcntl.h>
            #NOTE only MoarVM implements Proc::Async for now
            if $*DISTRO.is-win { # TODO check for admin privileges ?

                if $async {
                    @procs.push( Proc::Async.new("fsutil", "file", "createnew", $dest-file.(), $file-size*1024*1024).start ) for ^$file_per_dir;
                } else {
                   run "fsutil", "file", "createnew", $dest-file.(), $file-size*1024*1024 for ^$file_per_dir;
                }
            } else {

                if $async {
                    @procs.push( Proc::Async.new("fallocate", "-l", $file-size~"M", $dest-file.() ).start ) for ^$file_per_dir;
                } else {
                    run "fallocate", "-l", $file-size~"M", $dest-file.() for ^$file_per_dir;
                }
            }

            $total      -= $file_per_dir;
            $left_files-- if $left_files;
            print "\r   $total to create";

        }
    }

    await Promise.allof( @procs ); # wait all left working procs

    say "\nCreated $dir-count dirs, with $file-count files ( $file_per_dir per directory )";
}

