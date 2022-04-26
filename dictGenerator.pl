#!/usr/bin/perl

use warnings;
use strict;

use File::Find;
use File::Basename;
use File::Spec;

my $num_args = $#ARGV + 1;
if ($num_args != 2) {
    print "\nUsage: perl ./translation_transfer.pl PATH_TO_TRANSLATION_FOLDER PATH_TO_DICT_FILE\n";
    exit;
}

my $path_translation_dir = $ARGV[0];
my $path_dict_file = $ARGV[1];

$path_translation_dir = File::Spec->rel2abs($path_translation_dir) unless (File::Spec->file_name_is_absolute( $path_translation_dir ));
$path_dict_file = File::Spec->rel2abs($path_dict_file) unless (File::Spec->file_name_is_absolute( $path_dict_file ));

my %dict_final;
my %dict_duplicates;
my %dict_duplicate_source;

sub wanted
{
    if ($File::Find::name =~ m/\.ini$/igs)
    {
        open my $fh, "<", $File::Find::name or die "Cannot Open $File::Find::name: $!\n";
        while (my $line = <$fh>)
        {
            chomp($line);
            if ($line =~ m/^(?<org>.+?)=(?<tran>.+)/igs)
            {
                my $origin = $+{org};
                my $translation = $+{tran};

                unless ($origin eq $translation)
                {
                    if (exists $dict_final{$origin})
                    {
                        push @{${$dict_duplicate_source{$origin}}}, $File::Find::name;
                        if (exists $dict_duplicates{$origin}  && @{${$dict_duplicates{$origin}}})
                        {
                            push @{${$dict_duplicates{$origin}}}, $translation;
                        }
                        else
                        {
                            $dict_duplicates{$origin} = \[$dict_final{$origin}, $translation];
                        }
                    }
                    else
                    {
                        $dict_final{$origin} = $translation;
                        $dict_duplicate_source{$origin} = \[$File::Find::name];
                    }
                }
            }

        }
        close $fh;
    }
}

find(\&wanted, $path_translation_dir);

delete $dict_duplicates{$_} for grep {
    my @lstPossible_translation = @{${$dict_duplicates{$_}}};
    my $isRedundant = $lstPossible_translation[0] eq $lstPossible_translation[1];

    for my $idx (2..$#lstPossible_translation)
    {
        $isRedundant = $isRedundant && ($lstPossible_translation[$idx-1] eq $lstPossible_translation[$idx]);
        last unless ($isRedundant);
    }
    $isRedundant
} keys %dict_duplicates;

my $counter = 0;
my $total = keys %dict_duplicates;

print "Total Duplicates <<$total>>\n";

foreach my $original(keys %dict_duplicates)
{
    use utf8;
    use Encode qw( encode decode );
    binmode(STDIN,":encoding(gbk)");
    my @lstPossible_translation = @{${$dict_duplicates{$original}}};
    my @lstFileSources = @{${$dict_duplicate_source{$original}}};

    my $code_utf8 = decode("UTF-8", $original);
    my $str_ansi = encode("euc-cn", $code_utf8);
    $counter = $counter + 1;
    print "Found multiple translation ($counter/$total) for <<$str_ansi>>:\n";

    foreach my $idx (0..$#lstPossible_translation)
    {
        my $code_utf8_translation = decode("UTF-8", $lstPossible_translation[$idx]);
        my $str_ansi_translation = encode("euc-cn", $code_utf8_translation);
        print "$idx.  $str_ansi_translation ($lstFileSources[$idx])\n";
    }

    print "Please choose the correct translation[0..$#lstPossible_translation] or -1 to reject translation:";
    chomp(my $idx = <STDIN>);
    if ($idx == -1)
    {
        print ">> Translation for <<$str_ansi>> rejected\n";
        delete $dict_final{$original};
    }
    else
    {
        $dict_final{$original} = $lstPossible_translation[$idx];
    }
    
}

open my $fh, ">", $path_dict_file or die "Cannot create dict file for given location : $!\n";
foreach my $original(keys %dict_final)
{
    print $fh "$original=$dict_final{$original}\n";
}
close $fh;