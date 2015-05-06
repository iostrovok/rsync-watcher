# rsync-watcher #

## It's a watcher which monitors for directories and starts rsync for each changes. Script was written with PERL.##

### Introduction ###

No yet

### Installing and starting ###

First. Install perl modules:

```bash
> sudo cpan Data::Dumper File::HomeDir Getopt::Long
```

Second. Download https://raw.githubusercontent.com/iostrovok/rsync-watcher/master/rsync-watcher.pl to your computer or "git clone" https://github.com/iostrovok/rsync-watcher/.

Third. Run program:
```bash
> perl rsync-watcher.pl
```

### How use ###

Add new location for monitoring.

```bash
> perl rsync-watcher.pl -a
# or
> perl rsync-watcher.pl --add
```

Help 
```bash
> perl rsync-watcher.pl -h
# or 
> perl rsync-watcher.pl --help
```

Run 
```bash
> perl rsync-watcher.pl
```
