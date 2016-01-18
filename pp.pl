#!/usr/bin/perl

use v5.20;
use utf8;
use open qw( :encoding(UTF-8) :std );

use strict;
use warnings;

use Text::CSV;
use Data::Dumper;
use JSON;
use File::Slurp;
use Statistics::Basic qw(:all);
use List::Util qw(max min shuffle);
use POSIX qw(ceil floor);


$\ = $/;

my %statistics = (
  'both' => 0,
  'uc' => 0,
  'py' => 0,
  'neither' => 0,
  'total' => 0
);

my %files = ();
my %packages = ();

my $csv = Text::CSV->new ( { binary => 1 } )  # should set binary attribute.
  or die "Cannot use CSV: ".Text::CSV->error_diag ();
  
my @hist = qw(0 0-1 0-2 0-5 0-10 0-20 >20);

my %friendlyname = (
  delete => 'DeleteToken',
  insert => 'InsertToken',
  replace => 'ReplaceToken',
  insertNum => 'InsertDigit',
  deleteNum => 'DeleteDigit',
  insertWord => 'InsertLetter',
  deleteWord => 'DeleteLetter',
  insertPunct => 'InsertSymbol',
  deletePunct => 'DeleteSymbol',
  indent => 'Indent',
  dedent => 'Dedent',
);

sub friendly {
  my ($name) = @_;
  defined($friendlyname{$name}) and return $friendlyname{$name};
  return $name;
}
  

sub linedisthist {
  my ($dist) = @_;
  $dist = int(abs($dist));
  my @r;
  push @r, qw(0) if ($dist == 0);
  push @r, qw(0-1) if ($dist <= 1);
  push @r, qw(0-2) if ($dist <= 2);
  push @r, qw(0-5) if $dist <= 5;
  push @r, qw(0-10) if $dist <= 10;
  push @r, qw(0-20) if $dist <= 20;
  return qw(>20) if $dist > 20;
  return @r;
}

my %filelinecache;
my %unsf;

sub getfileline {
  my ($f, $l) = @_;
  if (defined($filelinecache{$f})) {
    defined ($filelinecache{$f}[$l]) or die("$#{$filelinecache{$f}} $l");
    return $filelinecache{$f}[$l];
  }
  open(SOURCEFILE, '<', $unsf{$f}) or die("Couldn't open $f");
    my $linearray = [''];
    while (<SOURCEFILE>) {
      chomp;
      push @$linearray, $_;
    }
  close SOURCEFILE;
  push @$linearray, '';
  $filelinecache{$f} = $linearray;
  defined ($linearray->[$l]) or die;
  return $linearray->[$l];
}

my $json = read_file('mcc.json') or die "mcc.json: $!";
my $mccdata = from_json($json);

# build line to fn lookup table
my %filelinefn;

for my $f (keys(%$mccdata)) {
  my $fmccdata = $mccdata->{$f};
  my $blockcount = 0;
  my $total = 0;
  my $sf = $f;
  $sf =~ s/\W/_/g;
  for my $block (@$fmccdata) {
    for (my $i = int($block->{'lineno'}); $i <= int($block->{'endline'}); $i++) {
      push @{$filelinefn{$f}{$i}}, $block->{'name'};
      push @{$filelinefn{$sf}{$i}}, $block->{'name'};
    }
    $files{$sf}{'blocks'}{$block->{'name'}}{'complexity'} = $block->{'complexity'};
    $files{$sf}{'blocks'}{$block->{'name'}}{'lines'} = 1+int($block->{'endline'})-int($block->{'lineno'});
    $blockcount++;
    $total += $block->{'complexity'};
  }
  $files{$sf}{'blocks'}{0}{'complexity'} = $total/$blockcount;
#   print STDERR Dumper $filelinefn{$f};
}
# die;
# read CSV inputs

my @mutdata;

foreach (@ARGV) {
  open my $fh, "<:encoding(utf8)", $_ or die "$_: $!";
  my $file = $_;
    while ( my $row = $csv->getline( $fh ) ) {
    my ($f,
        $mutline, 
        $pyline, 
        $errorsSoFar, 
        $mutationsSoFar, 
        $fileMutationsSoFar, 
        $charmSoFar, 
        $deltaSoFar, 
        $mutname,
        $toktype, 
        $toktext, 
        $errtype, 
        $pycorrect, 
        undef, 
        undef) = @$row;
    if ($f =~ m/\0/) { next; }
    next if $toktype =~ m/ENDMARKER/i;
    my $type;
    if ($mutname =~ m/insert$/i) {
      $type = 'insert';
    } elsif ($mutname =~ m/delete$/i) {
      $type = 'delete';
    } elsif ($mutname =~ m/replace$/i) {
      $type = 'replace';
    } elsif ($mutname =~ m/(\w+)Random/i) {
      $type = $1;
    } else {
      die "wat: $mutname";
    }
    my $hit;
    if ($pycorrect =~ m/True/i) {
      $hit = 'py';
    } elsif ($pycorrect =~ m/False/i) {
      $hit = 'neither';
    } else {
      print Dumper($row);
      die("$file: wat");
    }
    my $sf = $f;
    $sf =~ s/\W/_/g;
    $unsf{$sf} = $f;
    $statistics{'total'}++;
    $statistics{$type}{'total'}++;
    $statistics{$hit}++;
    $statistics{$type}{$hit}++;
    if ($pyline =~ m/\d+/) {
      for my $histcol (linedisthist($mutline - $pyline)) {
        $statistics{$type}{'pydist'}{$histcol}++;
      }
      $statistics{$type}{'pydist'}{'total'}++;
    }
    $files{$sf}{'mutline'}{$mutline}++;
    $files{$sf}{'pyline'}{$pyline}++;
    $files{$sf}{'muts'}++;
    $files{$sf}{'pyerrs'}++;
    foreach my $block (@{$filelinefn{$f}{$mutline}}) {
      $files{$sf}{'blocks'}{$block}{'muts'}++;
    }
    foreach my $block (@{$filelinefn{$f}{$pyline}}) {
      $files{$sf}{'blocks'}{$block}{'pyerrs'}++;
    }
    if ($errtype !~ m/None/i) {
      $statistics{'err'}{'total'}++;
      $statistics{'err'}{$type}{'total'}++;
      $statistics{'err'}{$hit}++;
      $statistics{'err'}{$type}{$hit}++;
    }
      push @mutdata, [
          $sf,
          $mutline, 
          $pyline, 
        ];
    if ($type =~ m/^(insert|delete|replace)$/) {
      $statistics{'toktype'}{$toktype}{$hit}++;
      $statistics{'toktype'}{$toktype}{'total'}++;
      $statistics{'errtype'}{$errtype}{$hit}++;
      $statistics{'errtype'}{$errtype}{'total'}++;
      $statistics{'errtype'}{$errtype}{$type}++;
    }
    if (not defined($files{$sf})) {
      if ($f =~ m|site-packages/([^/]+)/|i) {
        my $pkg = $1;
        $pkg =~ s/_//g;
        $packages{$pkg}++;
      } else {
        $packages{'Python'}++;
      }
    }
    $files{$sf}{'total'}++;
    $files{$sf}{$type}{'total'}++;
    $files{$sf}{$type}{'uc'}++ if $hit eq 'uc' or $hit eq 'both';
    $files{$sf}{$type}{'py'}++ if $hit eq 'py' or $hit eq 'both';
    $files{$sf}{$type}{'either'}++ if $hit eq 'py' or $hit eq 'uc' or $hit eq 'both';
  }
}

my $outfh;
open $outfh, ">:encoding(utf8)", "perfile.csv" or die "perfile.csv: $!";
$csv->print($outfh, ['file', 'ucd', 'uci', 'ucr', 'pyd', 'pyi', 'pyr',
'ed', 'ei', 'er']);
for my $f (keys(%files)) {
  my $row = [$f];
  for my $which (qw(uc py either)) {
    for my $type (qw(delete insert replace)) {
      push @$row, (defined($files{$f}{$type}{$which})
        ? $files{$f}{$type}{$which}/$files{$f}{$type}{'total'}
        : 0);
    }
  }
  $csv->print($outfh, $row);
}

close $outfh or die;

sub filelinematches {
  my ($f, $l, $m) = @_;
  my $line = getfileline($f, $l);
  defined($line) or die("file: $f line: $l");
  my $number = () = $line =~ /$m/gc;
  return $number;
}

my @alllines;

open $outfh, ">:encoding(utf8)", "perline.csv" or die "perline.csv: $!";
$csv->print($outfh, ['file', 'line', 'muts', 'py', 'diff', 'rat', 
                     'colons', 'indent', 'ifthenelse', 'assign',
                     'brackets', 'parens', 'dots', 'ls', 'tests',
                     'words', 'numbers', 'strings', 'braces', 'du', 'arith',
                     'comment', 'empty', 'idelta', 'commas', 'linelen', 
                     'fdelta', 'lcc']);
for my $f (keys(%files)) {
  my @lines = (sort {$b <=> $a} (keys(%{$files{$f}{'mutline'}})));
  my $lastline = $lines[0];
  my $previndent = 0;
  for (my $line = 1; $line <= $lastline; $line++) {
    my $empty = ((getfileline($f, $line) =~ m/^\s*$|^\s*#/ ) ? 1 : 0);
    my $m = $files{$f}{'mutline'}{$line} ? $files{$f}{'mutline'}{$line} : 0;
    next if $m == 0;
    my $p = $files{$f}{'pyline'}{$line} ? $files{$f}{'pyline'}{$line} : 0;
    my $avgmutsperline = ($files{$f}{'muts'} > 0 ? $files{$f}{'muts'} : 0) / $lastline;
    $files{$f}{'avgmutsperline'} = $avgmutsperline;
    my $r = ($p-$m)/$avgmutsperline;
    my $colons = filelinematches($f, $line, qr/:/);
    my ($indentation) = getfileline($f, $line) =~ m/^\s*/g;
    my $indent = () = $indentation =~ m/    |\t/g;
    my $findent;
    if ($line < $lastline) {
      my ($findentation) = getfileline($f, $line+1) =~ m/^\s*/g;
      $findent = () = $findentation =~ m/    |\t/g;
    } else {
      $findent = 0;
    }
    my $ifthenelse = filelinematches($f, $line, qr/if|then|else|elif/);
    my $brackets = filelinematches($f, $line, qr/[\[\]]/);
    my $parens = filelinematches($f, $line, qr/[()]/);
    my $dots = filelinematches($f, $line, qr/\w\.\w/);
    my $longstrings = filelinematches($f, $line, qr/\"\"\"/);
    my $words = filelinematches($f, $line, qr/and|exec|not|assert|finally|or|break|for|pass|class|from|print|continue|global|raise|def|if|return|del|import|try|elif|in|while|else|is|with|except|lambda|yield/);
    my $numbers = filelinematches($f, $line, qr/-?0x[\da-fA-F]|-?\d+(?:\.\d+)?(?:[+-]?[eE]\d+)?/);
    my $strings = filelinematches($f, $line, qr/\".[^\"]|\'/);
    my $braces = filelinematches($f, $line, qr/\{|\}/);
    my $du = filelinematches($f, $line, qr/__/);
    my $notop = qr{[^+\-*/%=!<>&|^~]};
    my $arith = filelinematches($f, $line, qr{$notop(?:\+|-|\*|/|\%|\*\*|//|&|\|\^|\~|<<|>>)$notop});
    my $tests = filelinematches($f, $line, qr/$notop(?:\==|\!=|<>|>|<|<=|>=)$notop/);
    my $assign = filelinematches($f, $line, qr{$notop(?:\=|\+=|-=|\*=|/=|%=|\*\*=|//=)$notop});
    my $comment = filelinematches($f, $line, qr{#[^'"]+$});
#     print getfileline($f, $line) if $assign;
    my $commas = filelinematches($f, $line, qr{,});
    my $linelen = length(getfileline($f, $line));
    my $lcc = filelinematches($f, $line, qr{\\\s*#[^'"]+$|\\\s*$});
    my $row = [$f, $line, $m, $p, $p-$m, $r,
        $colons,   #7
        $indent,   #8
        $ifthenelse, #9
        $assign, #10
        $brackets, #11
        $parens, #12
        $dots, #13
        $longstrings, #14
        $tests, #15
        $words, #16
        $numbers, #17
        $strings, #18
        $braces, #19
        $du, #20
        $arith, #21
        $comment, #22
        $empty, #23
        $indent-$previndent, #24
        $commas,
        $linelen, #26
        $findent-$indent, #27
        $lcc, #28
      ];
    push @alllines, [getfileline($f, $line), $r];
    $files{$f}{'r'}{$line} = $r;
    $csv->print($outfh, $row);
    foreach my $block (@{$filelinefn{$f}{$line}}) {
      $files{$f}{'blocks'}{$block}{'colons'} += $colons;
      $files{$f}{'blocks'}{$block}{'indent'} += $indent;
      $files{$f}{'blocks'}{$block}{'ifthenelse'} += $ifthenelse;
      $files{$f}{'blocks'}{$block}{'assign'} += $assign;
      $files{$f}{'blocks'}{$block}{'brackets'} += $brackets;
      $files{$f}{'blocks'}{$block}{'parens'} += $parens;
      $files{$f}{'blocks'}{$block}{'dots'} += $dots;
      $files{$f}{'blocks'}{$block}{'longstrings'} += $longstrings;
      $files{$f}{'blocks'}{$block}{'tests'} += $tests;
      $files{$f}{'blocks'}{$block}{'words'} += $words;
      $files{$f}{'blocks'}{$block}{'numbers'} += $numbers;
      $files{$f}{'blocks'}{$block}{'strings'} += $strings;
      $files{$f}{'blocks'}{$block}{'braces'} += $braces;
      $files{$f}{'blocks'}{$block}{'du'} += $du;
      $files{$f}{'blocks'}{$block}{'arith'} += $arith;
      $files{$f}{'blocks'}{$block}{'comment'} += $comment;
      $files{$f}{'blocks'}{$block}{'empty'} += $empty;
      $files{$f}{'blocks'}{$block}{'idelta'} += $indent-$previndent;
      $files{$f}{'blocks'}{$block}{'commas'} += $commas;
      $files{$f}{'blocks'}{$block}{'linelen'} += $linelen;
      $files{$f}{'blocks'}{$block}{'fdelta'} += $findent-$indent;
      $files{$f}{'blocks'}{$block}{'lcc'} += $lcc;
      push @{$files{$f}{'blocks'}{$block}{'array'}}, $r;
    }
    $previndent = $indent;
  }
}

close $outfh or die;

for my $line (sort {$a->[1] <=> $b->[1]} @alllines) {
  my $score = sprintf("%-3.2f", $line->[1]);
  print "$score\t$line->[0]";
}



open $outfh, ">:encoding(utf8)", "perblock.csv" or die "perblock.csv: $!";
my @extrastats =    ('colons', 'indent', 'ifthenelse', 'assign',
                     'brackets', 'parens', 'dots', 'longstrings', 'tests',
                     'words', 'numbers', 'strings', 'braces', 'du', 'arith',
                     'comment', 'empty', 'idelta', 'commas', 'linelen', 
                     'fdelta', 'lcc');

$csv->print($outfh, ['file', 'block', 'muts', 'py', 'diff', 'rat', 
                     'mcc', 'lines', 'variance', 'min',
                     'max', 'range', 'avgmutsperblock', 'bcharm',
                     @extrastats]);
for my $f (keys(%files)) {
  my @blocks = (sort {$a cmp $b} (keys(%{$files{$f}{'blocks'}})));
  for my $block (@blocks) {
    next if $block eq 0;
    my $m = $files{$f}{'blocks'}{$block}{'muts'} ? $files{$f}{'blocks'}{$block}{'muts'} : 0;
    my $p = $files{$f}{'blocks'}{$block}{'pyerrs'} ? $files{$f}{'blocks'}{$block}{'pyerrs'} : 0;
    my $avgmutsperline = $files{$f}{'avgmutsperline'};
    my $avgmutsperblock = $files{$f}{'muts'}/scalar(keys %{$files{$f}{'blocks'}});
    my $max = max(@{$files{$f}{'blocks'}{$block}{'array'}});
    unless (defined($max)) {
#       print Dumper $files{$f}{'blocks'}{$block}{'array'};
#       die;
        next;
    };
    my $min = min(@{$files{$f}{'blocks'}{$block}{'array'}});
    my $blocklines = $files{$f}{'blocks'}{$block}{'lines'};
    $files{$f}{'blocks'}{$block}{'indent'} /= $blocklines;
    my $row = [$f, $block, $m, $p, $p-$m, 
      ($p-$m)/($avgmutsperline), #V6
      $files{$f}{'blocks'}{$block}{'complexity'}, #V7
      $blocklines, #V8
      scalar(variance($files{$f}{'blocks'}{$block}{'array'}))*1, #V9
      $min, #V10
      $max, #V11
      ($max - $min)*1, #V12
      $avgmutsperblock,
      ($p-$m)/($avgmutsperblock), #V14
      map({ $files{$f}{'blocks'}{$block}{$_} } @extrastats),
    ];
    $csv->print($outfh, $row);
  }
}


close $outfh or die;



my @allMuts = qw(delete insert replace deleteNum insertNum deletePunct insertPunct deleteWord insertWord dedent indent);

for my $type (@allMuts) {
  $statistics{$type}{'min'} = 2**50;
  for my $f (keys(%files)) {
    if ($files{$f}{$type}) {
      if ($files{$f}{$type} < $statistics{$type}{'min'}) {
        $statistics{$type}{'min'} = $files{$f}{$type};
        print "$f $type $files{$f}{$type}";
      }
    }
  }
}

# print Dumper \%statistics;


use LaTeX::Table;
use Number::Format qw(:subs);  # use mighty CPAN to format values
my $top = 1;
# -----------------------------------------------------------------------------

my $histsize = 10000;
my %histsall;
my @things = qw(rand out asc desc abs);

$histsall{'rand'} = [(0) x ($histsize+1)];
$histsall{'out'} = [(0) x ($histsize+1)];
$histsall{'asc'} = [(0) x ($histsize+1)];
$histsall{'desc'} = [(0) x ($histsize+1)];
$histsall{'abs'} = [(0) x ($histsize+1)];

my $progi = 0;

for my $mutdata_i (@mutdata) {
  my ($sf, $mutline, $pyline) = @$mutdata_i;
  if ($progi % 1000 == 0) {
    print STDERR "$progi/$#mutdata";
  }
  $progi++;
#   last if $progi >= 100000;
  my @lines = (sort {$b <=> $a} (keys(%{$files{$sf}{'mutline'}})));
  my $lastline = $lines[0];
  my @randorder = shuffle(@lines);

  my $linesChecked = 0;
  for my $tryline (@randorder) {
    if ($files{$sf}{'mutline'}{$tryline}) {
      $linesChecked++;
      if ($tryline == $mutline) {
        last;
      }
    }
  }
  $files{$sf}{'hist'}{'rand'}{$linesChecked}++;
  $histsall{'rand'}[ceil(($linesChecked/$lastline)*$histsize)]++;

  $linesChecked = 0;
  my $tryDistance = 0;
  while ($tryDistance <= $lastline) {
    if ($files{$sf}{'mutline'}{$pyline+$tryDistance}) {
      $linesChecked++;
      if ($pyline+$tryDistance == $mutline) {
        last;
      }
    }
    if ($tryDistance > 0 && $files{$sf}{'mutline'}{$pyline-$tryDistance}) {
      $linesChecked++;
      if ($pyline-$tryDistance == $mutline) {
        last;
      }
    }
    $tryDistance++;
  }
  $files{$sf}{'hist'}{'out'}{$linesChecked}++;
  $histsall{'out'}[ceil(($linesChecked/$lastline)*$histsize)]++;

  my @charmasc = sort {$files{$sf}{'r'}{$a} <=> $files{$sf}{'r'}{$b}} @lines;
  $linesChecked = 0;
  for my $tryline (@charmasc) {
    if ($files{$sf}{'mutline'}{$tryline}) {
      $linesChecked++;
      if ($tryline == $mutline) {
        last;
      }
    }
  }
  $files{$sf}{'hist'}{'asc'}{$linesChecked}++;
  $histsall{'asc'}[ceil(($linesChecked/$lastline)*$histsize)]++;

  my @charmdesc = sort {$files{$sf}{'r'}{$b} <=> $files{$sf}{'r'}{$a}} @lines;
  $linesChecked = 0;
  for my $tryline (@charmdesc) {
    if ($files{$sf}{'mutline'}{$tryline}) {
      $linesChecked++;
      if ($tryline == $mutline) {
        last;
      }
    }
  }
  $files{$sf}{'hist'}{'desc'}{$linesChecked}++;
  $histsall{'desc'}[ceil(($linesChecked/$lastline)*$histsize)]++;

  my @charmabs = sort {abs($files{$sf}{'r'}{$b}) <=> abs($files{$sf}{'r'}{$a})} @lines;
  $linesChecked = 0;
  for my $tryline (@charmabs) {
    if ($files{$sf}{'mutline'}{$tryline}) {
      $linesChecked++;
      if ($tryline == $mutline) {
        last;
      }
    }
  }
  $files{$sf}{'hist'}{'abs'}{$linesChecked}++;
  $histsall{'abs'}[ceil(($linesChecked/$lastline)*$histsize)]++;
}

open $outfh, ">:encoding(utf8)", "filehists.csv" or die "filehists.csv: $!";
  $csv->print($outfh, [
      'file',
      'lines',
      @things
    ]);
for my $f (keys(%files)) {
  my @lines = (sort {$b <=> $a} (keys(%{$files{$f}{'mutline'}})));
  my $lastline = $lines[0];
  @lines = (1..$lastline);
  my %accumulator = map {$_ => 0} @things;
  for my $line (@lines) {
    my @out;
    for my $thing (@things) {
      my $quantity = $files{$f}{'hist'}{$thing}{$line};
      $accumulator{$thing} += $quantity ? $quantity : 0;
    }
    $csv->print($outfh, [
        $f,
        $line,
        (map {$accumulator{$_}} @things)
      ]);
  }
}
close $outfh;

open $outfh, ">:encoding(utf8)", "hists.csv" or die "hists.csv: $!";
  $csv->print($outfh, [
      'progress',
      @things
    ]);
my %accumulator = map {$_ => $histsall{$_}[0]} @things;
for my $i (1..$histsize) {
  for my $thing (@things) {
    my $quantity = $histsall{$thing}[$i];
    $accumulator{$thing} += $quantity;
  }
  $csv->print($outfh, [
      $i,
      (map {$accumulator{$_}} @things)
    ]);  
}