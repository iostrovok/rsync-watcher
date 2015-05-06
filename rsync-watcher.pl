#!/usr/bin/perl

use strict;

use Data::Dumper;
use File::HomeDir;
use Getopt::Long;

use constant FILE => '/.perlrsync';

my @default_excludes = (
    ".realsync", "CVS",    ".git",  ".svn",
    ".hg",       ".cache", ".idea", "nbproject",
    "~*",        "*.tmp",  "*.pyc", "*.swp",
);

sub loadFlags {

    my %flags = (
        verbose => 0,
        help    => 0,
        quiet   => 0,
        add     => 0,
    );

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

    return %flags;
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

sub build {
    my ($v) = @_;

    #my @exclude = map {"--exclude '$_'"} @{ $v->{ignor} };
    #my $excludeLine = join( ' ', @exclude );

    my $excludeLine
        = @{ $v->{ignor} }
        ? '--exclude={"' . join( '","', @{ $v->{ignor} } ) . '"}'
        : "";

    my $sshpassExe = $v->{pass} ? " sshpass -p \"$v->{pass}\" " : "";
    my $sshExe
        = $v->{port} != 22 ? " ssh -oBatchMode=no -p $v->{port}' " : "";

    my $sshE = "";

    if ( $sshpassExe || $sshExe ) {
        $sshE = "-e '$sshpassExe $sshExe'";
    }

    my $exe
        = "rsync -zqrhI "
        . "$sshE $excludeLine $v->{path} "
        . " $v->{user}\@$v->{host}:$v->{remPath}";
    print "RSYNC $v->{path} to $v->{host}:$v->{port}$v->{remPath}\n";
    print "$exe\n";
    system($exe);
}

sub run () {

    my %flags  = loadFlags();
    my $config = loadConf();

    print Dumper($config);

    if ( $flags{add} ) {
        if ( my $location = addLocation() ) {
            push( $config, $location );
            saveConf($config);
        }
    }

    print Dumper($config);
    my $timeSleep = 1;
    print "--> Start run monitor: Files changed, Building...\n";
    while (1) {
        update_sha($config);
        my $viewMessage = 0;
        foreach my $v (@$config) {
            if ( $v->{sha_new} ne $v->{sha_old} ) {
                build($v);
                $v->{sha_old} = $v->{sha_new};
                $viewMessage = 1;
            }
        }
        if ($viewMessage) {
            print "\n--> Monitor: Files changed, Building...\n";
        }
        sleep($timeSleep);
    }
}

print "--> Start...\n";
run();
