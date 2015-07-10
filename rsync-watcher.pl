#!/usr/bin/perl

use strict;

use Data::Dumper;
use File::HomeDir;
use Getopt::Long;
use Digest::CRC qw[ crc16 ];

use constant FILE => '/.perlrsync';

#check_files();
#exit();

my @default_excludes = (
    ".realsync", "CVS",    ".git",  ".svn",
    ".hg",       ".cache", ".idea", "nbproject",
    "~*",        "*.tmp",  "*.pyc", "*.swp",
);
my %flags = (
    verbose => 0,
    help    => 0,
    quiet   => 0,
    add     => 0,
);

sub loadFlags {

    GetOptions(
        "v"       => \$flags{verbose},
        "verbose" => \$flags{verbose},
        "h"       => \$flags{help},
        "help"    => \$flags{help},
        "q"       => \$flags{quiet},
        "quiet"   => \$flags{quiet},
        "a"       => \$flags{add},
        "add"     => \$flags{add},
    );
}

sub saveConf {
    my $config = shift;

    die "Bad saving config\n" unless ref $config eq 'ARRAY';

    my $file = File::HomeDir->my_home . '/' . FILE;
    my $i    = 0;
    open F, ">$file";
    foreach my $v (@$config) {
        print F "# start $i\n";
        foreach my $k ( sort keys %$v ) {
            my $sp = substr( ' ' x 10, 0, 10 - length("$i:$k") );
            if ( ref $v->{$k} eq 'ARRAY' ) {
                foreach ( @{ $v->{$k} } ) {
                    print F "$i:$k$sp=> $_\n";
                }
            }
            else {
                print F "$i:$k$sp=> $v->{$k}\n";
            }
        }
        print F "# finish $i\n\n";
        $i++;
    }
    close F;
}

sub addLocation {
    my $loc = emptyPath();

    my @getParamsList = (
        {
            # tag => "path",
            text         => sub {"LOCAL directory to replicate FROM:"},
            errorMessage => sub {
                my ( $one, $loc, $val ) = @_;
                "No such directory: $val";
            },
            checkValue => sub {
                my ( $one, $loc, $val ) = @_;

                return unless -d $val;

                $loc->{path} = $val;
                print "...added LOCAL directory $loc->{path}\n";

                return 1;
            },
        },
        {
            # tag => "host",
            text => sub {"REMOTE host to replicate TO (host or host:port):"},
            errorMessage => sub {"Invalid hostname!"},
            comment    => "Remote host to replicate to over SSH.",
            checkValue => sub {
                my ( $one, $loc, $val ) = @_;

                my ( $host, $port ) = split( ':', $val );
                return unless $host;
                $port ||= 22;
                $loc->{host} = $host;
                $loc->{port} = $port;

                print "...added host $loc->{host}\n";
                print "...added port $loc->{port}\n";

                return 1;
            },
        },
        {
            # tag => "user",
            text => sub {
                my ( $ine, $loc ) = @_;
                return "REMOTE SSH login at $loc->{host}:";
            },
            errorMessage => sub {"Invalid login format!"},
            checkValue   => sub {
                my ( $one, $loc, $val ) = @_;
                return if $val =~ m/["\s]/;

                $loc->{user} = $val;
                print "...added REMOTE SSH login $loc->{user}\n";
                return 1;
            },
        },
        {
            # tag  => "pass",
            text => sub {
                my ( $ine, $loc ) = @_;
                return "REMOTE SSH password at $loc->{user}\@$loc->{host}:";
            },
            errorMessage => sub {"Invalid login format!"},
            checkValue   => sub {
                my ( $one, $loc, $val ) = @_;
                return if $val =~ m/[\s]/;

                $loc->{pass} = $val;
                print "...added REMOTE SSH password for $loc->{user}\n";
                return 1;
            },
        },

        {
            # tag  => "remPath",
            text => sub {
                my ( $ine, $loc ) = @_;
                return
                    "REMOTE directory at $loc->{host}\@$loc->{host} to replicate to:";
            },
            errorMessage => sub {
                my ( $one, $loc, $val ) = @_;
                return "Directory $val at $loc->{host}\@$loc->{host}"
                    . " does not exist. Try again.";
            },
            comment => "Directory at the remote host to replicate files to.",
            checkValue => sub {
                my ( $one, $loc, $val ) = @_;
                $loc->{remPath} = $val;

                print "...added REMOTE directory $loc->{remPath}\n";

                return 1;
            },
        },

        {
            # tag => "ignor", default values,
            text => sub {
                "Do you want default exclusions:\n" . "  "
                    . join( " ", @default_excludes ) . "\n"
                    . "Please select yes por no [yes]:";
            },
            errorMessage => sub {""},
            comment      => "",
            checkValue   => sub {
                my ( $one, $loc, $val ) = @_;
                if ( $val eq "" or $val =~ m/yes/i ) {
                    push( @{ $loc->{ignor} }, @default_excludes );

                    print "...Exclusions: "
                        . join( ", ", @{ $loc->{ignor} } ) . "\n";
                }
                return 1;
            },
        },
        {
            # tag => "ignor",
            text => sub {
                "Exclusions configuration are:\n" . "  "
                    . join( " ", @{ $loc->{ignor} } ) . "\n"
                    . "Enter a space-separated list of ADDITIONAL exclusions:";
            },
            errorMessage => sub {""},
            comment      => "",
            checkValue   => sub {
                my ( $one, $loc, $val ) = @_;
                $val =~ s/^\s+|\s+$//gios;
                my @addList = split( /[,\s]+/, $val );
                push( @{ $loc->{ignor} }, @addList ) if @addList;

                print "...Exclusions: "
                    . join( ", ", @{ $loc->{ignor} } ) . "\n";

                return 1;
            },
        },

    );

    foreach my $one (@getParamsList) {
        my $notReady = 1;
        while ($notReady) {
            my $s    = $one->{text};
            my $text = &$s( $one, $loc );
            my $val  = promptUser($text);

            my $testSub = $one->{checkValue};

            unless ( &$testSub( $one, $loc, $val ) ) {
                my $s = $one->{errorMessage};
                my $text = &$s( $one, $loc, $val );
                print "error text  : ", $text, "\n";
                $notReady = 0;
            }
            else {
                $notReady = 0;
            }
        }
    }

    my $textOk = qq{
Replicate FROM $loc->{host} TO $loc->{user}\@$loc->{host}:$loc->{port}$loc->{remPath}
Please select yes por no
};
    my $yesNo = promptUser($textOk);
    if ( $yesNo =~ m/yes/i ) {
        return $loc;
    }

    return undef;
}

sub promptUser {

    my ($promptString) = @_;

    print $promptString, " ";

    $| = 1;    # force a flush after our print
    my $out = <STDIN>;    # get the input from STDIN (presumably the keyboard)

    chomp($out);

    return $out;
}

sub emptyPath {
    my %in = @_;
    return {
        sha_files => {},

        path    => "",
        sha_new => '',
        sha_old => '',
        remPath => "",
        pass    => "",
        host    => "22",
        port    => "",
        user    => "",
        ignor   => $in{empty_defuault_ignor} ? [] : [@default_excludes],
    };
}

sub loadConf {

    my $file = File::HomeDir->my_home . '/' . FILE;
    my @lines;
    open F, $file;
    @lines = <F>;
    close F;

    my $id     = "";
    my $values = {};
    foreach my $s (@lines) {
        chomp($s);
        next unless $s;
        my ( $tag, $val ) = split( /\s*=>\s*/, $s, 2 );
        $tag =~ s/^\s+|\s+$//gios;
        $val =~ s/^\s+|\s+$//gios;
        $val =~ s/^"|"$//gios;
        ( $id, $tag ) = split( ":", $tag );

        next unless $id =~ m/^[0-9]+$/ && $tag && $val;

        $values->{$id} = emptyPath( empty_defuault_ignor => 1 )
            unless exists $values->{$id};
        if ( ref( $values->{$id}{$tag} ) eq "ARRAY" ) {
            push @{ $values->{$id}{$tag} }, $val;
        }
        else {
            $values->{$id}{$tag} = $val;
        }
    }

    my @out;
    foreach my $v ( sort { $a <=> $b } keys %$values ) {
        push @out, $values->{$v};
    }
    return [@out];
}

sub update_sha {
    my ($path) = @_;

    foreach my $v (@$path) {
        my $t = `ls -lRTucit $v->{path} | sha1sum`;
        $t =~ s/[^0-9a-z]//gis;
        $v->{sha_new} = $t;
    }
}

sub check_files {
    my ($v) = @_;
    my $path = $v->{path};

    my $t = `ls -lRTucit $path`;
    my @list = split( /\n/, $t );

    if ( @list && $list[0] =~ m/^total .*/ ) {
        shift @list;
    }

    my @update_files;
    my %delete_files = map { ( $_ => 1 ) } ( keys %{ $v->{sha_files} } );
    my %dirs = ( $path => 1 );

    my $count = 0;
    for ( my $i = 0; $i < @list; $i++ ) {

        next unless $list[$i];

        if (   $i < $#list
            && $list[$i] =~ m/\:$/
            && $list[ $i + 1 ] =~ m/^total\s+(\d+)/ )
        {
            $path = $list[$i];
            $path =~ s{\:$}{/};
            $dirs{$path} = 0 unless exists $dirs{$path};

            $i++;
            next;
        }

    # 28122586 -rw-r--r--  1 ostrovok  wheel  2999 Jul  1 11:26:05 2015 cms.go
        my @s = split /\s+/, $list[$i];
        my $file = $path . pop(@s);
        next unless -f $file;

        $count++;
        $dirs{$path}++;
        my $key = crc16( join( ' ', @s ) );
        delete $delete_files{$file} if $delete_files{$file};
        unless ( $v->{sha_files}{$file} && $v->{sha_files}{$file} eq $key ) {
            push @update_files, $file;
            $v->{sha_files}{$file} = $key;
        }
    }

    my $return_all = $count / 3 < scalar(@update_files) ? 1 : 0;

    # Get empty dirs:
    my @d_dirs = grep { not exists $dirs{$_} } ( keys %{ $v->{sha_dirs} } );
    my @update_dirs
        = grep { not exists( $v->{sha_dirs}{$_} ) } ( keys %dirs );
    $v->{sha_dirs} = {%dirs};

    my @d_files = keys %delete_files;
    for my $file (@d_files) {
        for my $dir (@d_dirs) {
            if ( $file =~ m{$dir} ) {
                delete $delete_files{$file};
                last;
            }
        }
    }

    return ( $return_all, [@update_files], [@update_dirs],
        [ keys %delete_files ],
        [@d_dirs] );
}

sub _prepare_delete {
    my ($v) = @_;

    my $sshExe
        = $v->{port} != 22 ? "ssh -oBatchMode=no -p $v->{port}" : "ssh";
    my $sshpassExe = $v->{pass} ? "sshpass -p \"$v->{pass}\"" : "";

    return "$sshpassExe $sshExe $v->{user}\@$v->{host} \"rm -R %s\" ";
}

sub _prepare_build {
    my ($v) = @_;

    my $excludeLine
        = @{ $v->{ignor} }
        ? '--exclude={"' . join( '","', @{ $v->{ignor} } ) . '"}'
        : "";

    my $sshpassExe = $v->{pass} ? " sshpass -p \"$v->{pass}\" " : "";
    my $sshExe = $v->{port} != 22 ? " ssh -oBatchMode=no -p $v->{port} " : "";

    my $sshE = "";

    if ( $sshpassExe || $sshExe ) {
        $sshE = "-e '$sshpassExe $sshExe'";
    }

    return
          "rsync -zqrhI "
        . "$sshE $excludeLine %s "
        . " $v->{user}\@$v->{host}:%s";
}

sub exe_build {
    my ( $exe_line, $path, $host, $port, $remPath ) = @_;
    viewInfo("RSYNC $path to $host:$port$remPath ");

    my $exe = sprintf( $exe_line, $path, $remPath );
    viewVerbose($exe);
    system($exe);
}

sub build_files {
    my ( $v, $update_files ) = @_;

    return unless @$update_files;

    my $exe_line = _prepare_build($v);

    foreach my $file (@$update_files) {

        my $rem_file = $file;
        $rem_file =~ s{$v->{path}}{};
        $rem_file = $v->{remPath} . $rem_file;

        exe_build( $exe_line, $file, $v->{host}, $v->{port}, $rem_file );
    }
}

sub build {
    my ($v) = @_;

    my $exe_line = _prepare_build($v);
    exe_build( $exe_line, $v->{path}, $v->{host}, $v->{port}, $v->{remPath} );
}

sub build_delete {
    my ( $v, $files_dirs ) = @_;

    return unless @$files_dirs;

    my $line = _prepare_delete($v);

    my $remPath = $v->{remPath} . '/';
    my $path    = $v->{path} . '/';

    $path =~ s{/+}{/}gos;
    $remPath =~ s{/+}{/}gos;

    foreach my $file (@$files_dirs) {

        $file =~ s{/+}{/}gos;
        $file =~ s#^$path#$remPath#;

        my $exe = sprintf( "$line", $file );
        viewVerbose($exe);
        system($exe);
    }
}

sub run () {

    loadFlags();
    my $config = loadConf();

    if ( $flags{help} ) {
        help();
        exit();
    }

    viewVerbose("--> Start...");

    if ( $flags{add} ) {
        if ( my $location = addLocation() ) {
            push( @$config, $location );
            saveConf($config);
        }
    }

    viewVerbose(Dumper($config));
    my $timeSleep = 1;
    viewInfo("--> Start run monitor: Files changed, Building...");
    while (1) {
        update_sha($config);
        my $viewMessage = 0;
        foreach my $v (@$config) {
            if ( $v->{sha_new} ne $v->{sha_old} ) {
                my ($update_all,   $update_files, $update_dirs,
                    $delete_files, $delete_dirs
                ) = check_files($v);

                if ($update_all) {
                    viewVerbose("We're updating top dir");
                    build($v);
                }
                else {
                    viewVerbose("We're updating by files & dirs");
                    build_files( $v, $update_dirs );
                    build_files( $v, $update_files );
                }

                build_delete( $v, $delete_files );
                build_delete( $v, $delete_dirs );

                $v->{sha_old} = $v->{sha_new};
                $viewMessage = 1;
            }
        }
        if ($viewMessage) {
            viewInfo("--> Monitor: Files changed, Building...\n");
        }
        sleep($timeSleep);
    }
}

sub viewInfo {
    my $line = shift;

    return if $flags{quiet};

    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
    $year += 1900;

    printf( "[%4d-%02d-%02d %02d:%02d:%02d] %s\n",
        $year, $mon, $mday, $hour, $min, $sec, $line );
}

sub viewVerbose {
    return unless $flags{verbose};
    print join( "\n", @_ ), "\n";
}

run();

sub help {
    print <<HELP

It's a watcher which monitors for directories and starts rsync for each changes. Script was written with PERL.
Introduction

No yet
Installing and starting

First. Install perl modules:

> sudo cpan Data::Dumper File::HomeDir Getopt::Long

Second. Download https://raw.githubusercontent.com/iostrovok/rsync-watcher/master/rsync-watcher.pl to your computer or "git clone" https://github.com/iostrovok/rsync-watcher/.

Third. Run program:

> perl rsync-watcher.pl

How use

Add new location for monitoring.

> perl rsync-watcher.pl -a
# or
> perl rsync-watcher.pl --add

Help

> perl rsync-watcher.pl -h
# or 
> perl rsync-watcher.pl --help

Run

> perl rsync-watcher.pl

HELP
}

