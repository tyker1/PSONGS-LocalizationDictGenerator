#!/usr/bin/perl

use utf8;
use warnings;
use strict;

use Tk;

use Tk::BrowseEntry;
require Tk::StatusBar;
require Tk::LabEntry;
require Tk::DialogBox;

use Storable; 
use File::Find;
use File::Basename;
use File::Spec;
use List::Util qw(first);

my $dirTranslation="";
my $pathCheckpointFile="";

my %dict_final;
my %dict_duplicates;
my %dict_duplicate_source;
my @lstDuplicateOrigin;
my $idxDuplication= -1;
my $progressIdx = 0;
my $statusLabelText = "";
my $fileCount = 0;
my $counter = 0;
my $total;
my $orignalText;
my $sourceFile = "";
my $translationFrame;
my $acceptBtn;
my $prevBtn;
my $selectedTranslation;
my $dialogHd;
my $dialogPauseBtnText = "暂停";

my $mw = MainWindow->new(
    -title => "字典生成器"
    ); 
$mw->resizable( 0, 0 );
$mw->optionAdd('*font' => '{Microsoft YaHei}');

my $operationFieldFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
my $editFieldFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');

my $startProcessBtn = $operationFieldFrame->Button(
    -text => "预处理",
    -command => \&startProcess,
    -state => 'disabled'
    )->pack
    (
        -side => "left",
        -fill => "both",
        -anchor => "sw"
    );
my $pauseBtn = $operationFieldFrame->Button(
    -text => "保存进度",
    -command => \&saveCheckPoint,
    -state => 'disabled'
    )->pack(
    -side => "left",
    -fill => "both",
    -anchor => "sw",
    -after => $startProcessBtn
);
my $resumeCheckpointBtn = $operationFieldFrame->Button(
    -text => "处理冗余",
    -command => \&resumeProgress,
    -state => 'disabled'
)->pack(
    -side => "left",
    -fill => "both",
    -expand => 1,
    -after => $pauseBtn
);

my $loadCheckpointBtn = $operationFieldFrame->Button(
    -text => "读取进度",
    -command => \&loadCheckpointFile
)->pack(
    -side => "left",
    -fill => "both",
    -expand => 1,
    -after => $resumeCheckpointBtn
);

my $saveDictBtn = $operationFieldFrame->Button(
    -text => "保存字典",
    -command => \&saveDictFile,
    -state => 'disabled'
    )->pack(
        -side => "left",
        -fill => "both",
        -expand => 1,
    -after => $loadCheckpointBtn
);

my $translationPathEntry = $editFieldFrame->LabEntry(
    -label => "汉化项目路径:",
    -labelPack => [-side => "left"],
    -textvariable => \$dirTranslation,
    -width => 26
)->pack(
    -side => "left",
    -fill => "both",
    -expand => 1
);

my $browseDirBtn = $editFieldFrame->Button(
    -text => "...",
    -command => \&openDir
    )->pack(
        -side => "left",
        -fill => "both",
        -expand => 1,
        -after => $translationPathEntry
    );

my $statusBar = $mw->StatusBar();
$statusBar->addLabel(
    -relief         => 'flat',
    -textvariable   => \$statusLabelText,
    -font           => "{Microsoft YaHei}"
);

$editFieldFrame->pack(-fill => 'both', -expand => 1);
$operationFieldFrame->pack(-fill => 'both', -expand => 1);

my @buttons = ($startProcessBtn, $pauseBtn, $resumeCheckpointBtn, $loadCheckpointBtn, $loadCheckpointBtn, $saveDictBtn, $browseDirBtn);

center($mw);
MainLoop; 

sub openDir 
{
    $dirTranslation = $mw->chooseDirectory(
        -initialdir => '~',
        -title => 'Choose the directory contains translation files'
        );
    if ($dirTranslation && -e $dirTranslation)
    {
        $startProcessBtn->configure( -state => "normal");
    }
    else
    {
        $startProcessBtn->configure( -state => "disabled");
    }
    undef %dict_final;
    undef %dict_duplicates;
    undef %dict_duplicate_source;
    undef @lstDuplicateOrigin;
}

sub saveCheckPoint
{
    my $types = [
    ['Checkpoint Files',      '.ckp'      ],
    [],
    ];
    my $pathSaveCheckpointFile = $mw->getSaveFile(
        -filetypes => $types,
        -initialfile => 'jp2chs_checkpoint',
        -defaultextension => '.ckp',
        -title => "Select a location to save checkpoint"
    );
    if ($pathSaveCheckpointFile)
    {
        my %checkPointTable = (
            dict_final => \%dict_final,
            dict_duplicates => \%dict_duplicates,
            dict_duplicate_source => \%dict_duplicate_source,
            lstDuplicateOrigin => \@lstDuplicateOrigin,
            idxDuplication => $idxDuplication,
        );

        store(\%checkPointTable, $pathSaveCheckpointFile) or die "Cannot save checkpoint file $pathSaveCheckpointFile :$!\n";
    }
}

sub loadCheckpointFile
{
    my $types = [
    ['Checkpoint Files',      '.ckp'      ],
    [],
    ];
    $pathCheckpointFile = $mw->getOpenFile(
        -filetypes => $types,
        -defaultextension => ".ckp",
        -title => "Pick up a checkpoint file"
    );
    if ($pathCheckpointFile && -e $pathCheckpointFile && -f $pathCheckpointFile)
    {
        print "Got file : $pathCheckpointFile\n";

        my $jsRef = retrieve($pathCheckpointFile);

        die "Cannot retrieve data from checkpoint file $pathCheckpointFile" unless defined $jsRef;

        %dict_final = %{$jsRef->{dict_final}};;
        %dict_duplicates = %{$jsRef->{dict_duplicates}};;
        %dict_duplicate_source = %{$jsRef->{dict_duplicate_source}};;
        @lstDuplicateOrigin = @{$jsRef->{lstDuplicateOrigin}};;
        $idxDuplication= $jsRef->{idxDuplication};
        print "idxDuplication = $idxDuplication\n";

        my $lenDictFinal = keys %dict_final;
        $counter = keys %dict_duplicates;

        $saveDictBtn->configure( -state => "normal");
        $resumeCheckpointBtn->configure( -state => "normal");
        $pauseBtn->configure( -state => "normal");
        $statusLabelText = "载入翻译：$lenDictFinal; 冗余: $counter; 进度： ". ($idxDuplication+1)."/$counter";
    }
    else
    {
        $pathCheckpointFile = "";
    }
}

sub startProcess
{
    undef %dict_final;
    undef %dict_duplicates;
    undef %dict_duplicate_source;
    undef @lstDuplicateOrigin;
    $idxDuplication= -1;

    my @btnState;
    for my $idx (0..$#buttons)
    {
        push @btnState, $buttons[$idx]->cget(-state);
        $buttons[$idx]->configure(-state => "disabled");
    }

    if ($dirTranslation && -e $dirTranslation)
    {
        find(\&wanted, $dirTranslation);
    }

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

    $counter = 0;
    $total = keys %dict_duplicates;
    $idxDuplication=0;
    my $total_Origin = keys %dict_final;
    @lstDuplicateOrigin = keys %dict_duplicates;
    for my $idx (0..$#buttons)
    {
        $buttons[$idx]->configure(-state => "normal");
    }
 #   $saveDictBtn->configure( -state => "normal");
    $statusLabelText = "处理文件: $fileCount; 生成翻译: $total_Origin; 冗余 : $total";
}

sub saveDictFile
{
    my $save = $mw->getSaveFile(
        -filetypes => [
                        ["Dict File", ".ini"],
                        [],
                    ], 
        -initialfile => 'jp2chs',
        -defaultextension => '.ini'
        );

    open my $fh, ">:encoding(utf-8)", $save or die "Cannot create dict file $save : $!\n";
    foreach my $original(keys %dict_final)
    {
        print $fh "$original=$dict_final{$original}\n";
    }
    close $fh;
}

sub resumeProgress
{
    $dialogHd = $mw->DialogBox(
        -title => "冗余处理",
        -buttons => ["OK"]
    );
    $dialogHd->Subwidget("B_OK")->packForget();
    my $frame1 = $dialogHd->add("Frame", -borderwidth => 2, -relief => 'groove')->pack(-fill => 'both', -expand => 1);
    $translationFrame = $dialogHd->add("Frame", -borderwidth => 2, -relief => 'groove')->pack(-fill => 'both', -expand => 1);
    my $frame3 = $dialogHd->add("Frame", -borderwidth => 2, -relief => 'groove')->pack(-side => "bottom", -fill => 'both', -expand => 1);
    my $dialogStatusBar = $dialogHd->StatusBar();
    
    $frame1->Label(
        -textvariable => \$orignalText
    )->pack;

    $prevBtn = $frame3->Button(
        -text => "上一个",
        -command => \&btnPrevious
    )->pack(
        -side => "left",
        -fill => "both",
        -expand => 1,
        -fill => "both"
    );

    $acceptBtn = $frame3->Button(
        -text => "接受该翻译",
        -command => \&btnAccept
    )->pack(
        -side => "left",
        -fill => "both",
        -expand => 1,
        -fill => "both",
        -after => $prevBtn,
    );
    my $rejectBtn = $frame3->Button(
        -text => "拒绝该翻译",
        -command => \&btnReject
    )->pack(
        -side => 'left',
        -after => $acceptBtn,
        -fill => "both",
        -expand => 1
    );
    $frame3->Button(
        -textvariable => \$dialogPauseBtnText,
        -command => \&dialogButtonPause
    )->pack(
        -side => 'left',
        -after => $rejectBtn,
        -fill => "both",
        -expand => 1
    );
    $dialogStatusBar->addLabel(
            -relief         => 'flat',
            -textvariable   => \$sourceFile,
    );
    $dialogStatusBar->addLabel(
        -text           => 'Processed:',
        -width          => '20',
        -anchor         => 'center',
    );
    $dialogStatusBar->addLabel(
        -width          => 4,
        -anchor         => 'center',
        -textvariable   => \$idxDuplication,
        -foreground     => 'blue',
    );
    $dialogStatusBar->addLabel(
        -width          => 1,
        -anchor         => 'center',
        -text   => "/",
    );
    $dialogStatusBar->addLabel(
        -width          => 4,
        -anchor         => 'center',
        -text   => "$counter",
    );
    my $p = $dialogStatusBar->addProgressBar(
            -from           => $idxDuplication,
            -to             => $counter,
            -variable       => \$progressIdx,
        );

    $orignalText = $lstDuplicateOrigin[$idxDuplication];
    my @lstPossible_translation = @{${$dict_duplicates{$orignalText}}};
    $selectedTranslation = $dict_final{$orignalText};

    my @lstFileSources = @{${$dict_duplicate_source{$orignalText}}};
    my $idx = first { $lstPossible_translation[$_] eq $selectedTranslation } 0..$#lstPossible_translation;
    $sourceFile = basename($lstFileSources[$idx]);

    for my $idx (0..$#lstPossible_translation)
    {
        $translationFrame->Radiobutton(
            -text => $lstPossible_translation[$idx],
            -value => $lstPossible_translation[$idx],
            -variable => \$selectedTranslation,
            -command => \&onRadiobuttonChanged
            )->pack;
    }

    $prevBtn->configure(-state => "disabled") unless ($idxDuplication);

    $dialogHd->Show();

}

sub btnAccept
{
    $acceptBtn->configure(-state => "disabled");
    $dict_final{$lstDuplicateOrigin[$idxDuplication]} = $selectedTranslation;
    my $hasTranslation = 0;

    $idxDuplication++;
    $selectedTranslation = "";

    if ($idxDuplication == $counter)
    {
        my $answer = $mw->Dialog(
            -title => '冗余检查完成',
            -text => "冗余检查全部完成\n是否关闭本窗口？",
            -default_button => 'Yes', 
            -buttons => [ 'Yes', 'No'], 
            -bitmap => 'question'
            -font   => "{Microsoft YaHei}"
            )->Show( );
        if ($answer eq "Yes")
        {
            $dialogHd->Exit();
        }
        else
        {
            $idxDuplication--;
            #$selectedTranslation = $dict_final{$lstDuplicateOrigin[$idxDuplication]};
            $hasTranslation = 1;
            $dialogPauseBtnText = "完成";
        }
    }

    processRadiobuttons();

    $selectedTranslation = "" unless ($hasTranslation);
}

sub btnReject
{
    $acceptBtn->configure(-state => "disabled");
    my $hasTranslation = 0;
    delete $dict_final{$lstDuplicateOrigin[$idxDuplication]};

    $idxDuplication++;
    $selectedTranslation = "";

    if ($idxDuplication == $counter)
    {
        my $answer = $mw->Dialog(
            -title => '冗余检查完成',
            -text => "冗余检查全部完成\n是否关闭本窗口？",
            -default_button => 'Yes', 
            -buttons => [ 'Yes', 'No'], 
            -bitmap => 'question'
            -font   => "{Microsoft YaHei}"
            )->Show( );
        if ($answer eq "Yes")
        {
            $dialogHd->Exit();
        }
        else
        {
            $idxDuplication--;
            #$selectedTranslation = $dict_final{$lstDuplicateOrigin[$idxDuplication]};
            $hasTranslation = 1;
            $dialogPauseBtnText = "完成";
        }
    }

    processRadiobuttons();

    $selectedTranslation = "" unless ($hasTranslation);
}

sub btnPrevious
{
    $idxDuplication = $idxDuplication > 0 ? $idxDuplication-- : 0;
    if ($idxDuplication <= 0)
    {
        $prevBtn->configure( -state => 'disabled');
    }
    processRadiobuttons();
}

sub dialogButtonPause
{
    $counter = $total-1 if ($dialogPauseBtnText eq "完成");
    $dialogHd->Exit();
}

sub onRadiobuttonChanged
{
    $orignalText = $lstDuplicateOrigin[$idxDuplication];
    my @lstPossible_translation = @{${$dict_duplicates{$orignalText}}};
    my @lstFileSources = @{${$dict_duplicate_source{$orignalText}}};
    my $idx = first { $lstPossible_translation[$_] eq $selectedTranslation } 0..$#lstPossible_translation;
    $sourceFile = basename($lstFileSources[$idx]);

    $acceptBtn->configure( -state => "normal");
}

sub processRadiobuttons
{
    $progressIdx = $idxDuplication;
    my @packedWidgets = $translationFrame->packSlaves; 
    foreach my $widget (@packedWidgets)
    {
        $widget->destroy if Tk::Exists($widget);
    }

    $orignalText = $lstDuplicateOrigin[$idxDuplication];
    my @lstPossible_translation = @{${$dict_duplicates{$orignalText}}};
    $selectedTranslation = $dict_final{$orignalText};

    my @lstFileSources = @{${$dict_duplicate_source{$orignalText}}};
    my $idx = first { $lstPossible_translation[$_] eq $selectedTranslation } 0..$#lstPossible_translation;
    $sourceFile = basename($lstFileSources[$idx]);

    for my $idx (0..$#lstPossible_translation)
    {
        $translationFrame->Radiobutton(
            -text => $lstPossible_translation[$idx],
            -value => $lstPossible_translation[$idx],
            -variable => \$selectedTranslation,
            -command => \&onRadiobuttonChanged
            )->pack;
    }
    $prevBtn->configure(-state => $idxDuplication ? "normal" : "disabled");
    center($dialogHd);
}

sub center {
  my $win = shift;

  $win->withdraw;   # Hide the window while we move it about
  $win->update;     # Make sure width and height are current

  # Center window
  my $xpos = int(($win->screenwidth  - $win->width ) / 2);
  my $ypos = int(($win->screenheight - $win->height) / 2);
  $win->geometry("+$xpos+$ypos");

  $win->deiconify;  # Show the window again
}

sub wanted
{
    if ($File::Find::name =~ m/\.ini$/igs)
    {
        $fileCount++;
        $statusLabelText = "Processing File:". basename($File::Find::name);
        $statusBar->update;
        open my $fh, "<:encoding(utf-8)", $File::Find::name or die "Cannot Open $File::Find::name: $!\n";
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