#!/usr/bin/env perl

use strict;

use Getopt::Long;
use File::Copy;
use File::Basename;
use IO::File;
use XML::Twig;
use Text::Balanced qw (extract_bracketed);
#use PDF::API2; #not installed on lxplus

my $VERSION = sprintf "%d.%03d", q$Revision: 1.1 $ =~ /(\d+)/g;
my $verbose;
my $texFile = 'example/example.tex';
my $doc = 'example_pas.pdf';
my $style = 'pas';
my $baseDir = 'C:/Documents and Settings/George Alverson/My Documents/CMS/TDRs/notes/notes/example';
my $outDir = "C:/Temp/test";
my $logFile = "tmp/example_temp.log";
my $execute = '1';
my $reportTitle = '1';
my $contactAddress;
my $help;
my $updateRecord;
my $dataNotMC = 1;
GetOptions ('verbose!' => \$verbose,
            'help|?' => \$help,
            'texFile=s' => \$texFile,
            'doc=s' => \$doc,
            'style=s' => \$style,
            'baseDir=s' => \$baseDir,
            'outDir=s' => \$outDir,
            'logFile=s' => \$logFile,
            'contactAddress=s' => \$contactAddress,
            'execute!' => \$execute,
            'updateRecord=i' => \$updateRecord,
            'data!' => \$dataNotMC);
if ($verbose)
{
    print "$0 called with texFile = $texFile, doc= $doc, style = $style, baseDir = $baseDir, outDir = $outDir, logFile = $logFile, contact = $contactAddress\n";
}
if ($help)
{
    print
    "\n >>> makeManifest: pulls references to figures from a TDR log file and copies the actual figures
            to a directory with names equal to the figure numbers.\n

            Note that the log file must be produced using a modified \\includegraphics command.

            Since the logo is in the \"general\" directory and has no path information in the log file,
            this script should be run there.

            Options/Parameters:\n
              - texFile: tex file with pdftitle, pdfauthor, etc. Defaults to $texFile.\n
              - doc: base document (in pdf). Defaults to $doc.\n
              - style: note style. Defaults to $style.\n
              - baseDir: base of input directory. Defaults to $baseDir.\n
              - outDir: output directory for files. Defaults to $outDir.\n
              - logFile: the TDR log file. Defaults to $logFile.\n
              - updateRecord: update the given record number at CDS. Defaults to $updateRecord.\n
              - contactAddress: e-mail contact address. Defaults to $contactAddress.\n
              - verbose: produce diagnostic output. Defaults to $verbose.\n
              - help: produce this message.\n\n

            Example:\n
              $0 -logFile=\"..\\tmp\\ptdr2_temp.log\"
            \n\n";


    exit;
}

## see more documentation at the end


      my $baseURL = $outDir;
      my $figNum; # one of following categories: 0, 1.29, CP 2
      my $figNam; # filename less extension of included figure
      my $figPath; # filename with associated path

      my $lastFigPart = undef; #a, b, c, etc.
      my $lastFigNum = undef;
      my $lastFigPath = undef;
      my $lastNewFig = undef; # filename for new file
      my $lastExt = undef;  # .jpg or .pdf
      my $skipfirst = 1; # first includegraphics is _almost_ always the experiment logo
      my $figOffset = undef; # 1 unless the first figure is actually a sub-figure, in which case 0

      my $newFig;
      my $cmdString;
      my $outFile;
      my $ext;
#
#--------------------------------------------
#     extract Author/Title info from the TeX file
#
   my $title = '';
   my $author = '';

   open(FILE, $texFile) || die("can't open TeX file $texFile: $!");
   $_ .= do { local( $/ ); <FILE> }; #grab entire content!
   close(FILE);
   # extract svn info: exemplars-- (note that these are the real values for this file)
   # \RCS$Revision: 1.1 $
   # \RCS$Date: 2010/07/16 18:51:27 $
   # \RCS$HeadURL: svn+ssh://valerieh@svn.cern.ch/reps/tdr2/utils/trunk/general/makeManifest.pl $
   # \RCS$Id: makeManifest.pl,v 1.1 2010/07/16 18:51:27 valerieh Exp $
   # -- what it looked like under cvs, with the dollar signs removed
   #\RCS Revision: 1.4 
   #\RCS Date: 2008/07/31 09:20:05 
   #\RCS Name: 
   my $repo = 'svn\+ssh://svn.cern.ch/reps/tdr2/'; 
   my $svn_repo_type = '';
   my $svn_tag = '';
   my $svn_year = 1900;
   my $pat1 = "\\\\RCS\\\$"."Id:\\s+(\\S*)\\.tex\\s+(\\d+)\\s+(\\d{4})-(\\d{2})-(\\d{2})\\s+(\\d{2}):(\\d{2}):(\\d{2})Z\\s+\(\\S+)\\s+\\\$";
   if (m/$pat1/s)
   {
       my $svn_filename = $1; my $svn_rev = $2; my $svn_filedate = $3."/".$4."/".$5; $svn_year = $3;
       my $pat2 = "\\\\RCS\\\$"."HeadURL:\\s+".$repo."(papers|notes)/(\\S*)/$svn_filename\\.tex\\s+"."\\\$";
       if (m/$pat2/s)
       {
           $svn_repo_type = $1;
           $svn_tag = $2;
       }
   }    
   # extract metadata
   m/\\hypersetup(.*)/s; # find hypersetup
   my $xtract = $1;
   my $substring = extract_bracketed($xtract,'{}');
   if ($substring =~ m/pdftitle\s*=\s*\{(.*?)\}/s) #use non-greedy matching
   { $title = $1}
   else
   {
      print "Cannot find title in metadata\n";
   }
   if ($substring =~ m/pdfauthor\s*=\s*\{(.*?)\}/s)
   { $author = $1}
   else
   {
       print "Cannot find author in metadata\n";
   }
   if ($reportTitle)
   {
       print "\n", ">>> --- Metadata report on $doc --- <<<";
       print "\n", ">>>";
       print "\n", ">>> PDF TITLE: ",$title;
       print "\n", ">>> PDF AUTH : ",$author,"\n\n";
   }
   # extract the LaTeX title
   my $ltitle;
   my $pos = index($_,'\title');
   if ($pos)
   {
       my $stext = substr($_,$pos+6); #skip \title
       $ltitle = extract_bracketed($stext,'{}');
       $ltitle = substr($ltitle,1,-1); # remove braces
       # now clean up  whitespace
       $ltitle =~ s/^\s*//; #begin
       $ltitle =~ s/\s*$//; #end
       $ltitle =~ s/\s{2,}/ /mg; #multiple interior...
       if ($reportTitle) { print ">>> LaTeX TITLE: ",$ltitle,"\n";}
   }
   else
   {
       print "$0: no LaTeX title found\nExiting...\n";
       return;
   }
   # extract the LaTeX abstract
   my $abstract;
   $pos = index($_,'\abstract');
   if ($pos)
   {
       my $stext = substr($_,$pos+9); #skip \abstract
       $abstract = extract_bracketed($stext,'{}');
       $abstract = substr($abstract,1,-1); # remove braces
       # now clean up  whitespace
       $abstract =~ s/^\s*//; #begin
       $abstract =~ s/\s*$//; #end
       $abstract =~ s/\s{2,}/ /mg; #multiple interior...
       if ($reportTitle)
       {
           print ">>> LaTeX ABSTRACT: ",$abstract,"\n";
           print ">>> ---- <<<\n";
       }
   }
   else
   {
       print "$0: no abstract found\nExiting...\n";
       return;
   }


# extract from PDF. This requires the PDF::API2 module, which is not
# available on lxplus
#    my $pdf = PDF::API2->open($doc);
#    my  %h = $pdf->info;
##    print %h;
#   if ($verbose)
#   {
#       print "\n", ">>> TITLE: ",$title,"\n";
#       print "\n", ">>> AUTH : ",$author,"\n";
#   }
#
#--------------------------------------------

# Generate the XML
      my $noteCode = $baseDir; # get canonical name from directory name
      my @parts = split m+/+, $noteCode;
      $noteCode = $parts[$#parts-1];
#     don't want to include the collection parent: from J-Y LM, 2008/07/18
#      my $collection = XML::Twig::Elt->new(collection=>{xmlns=>"http://www.loc.gov/MARC21/slim"});
      my $record = XML::Twig::Elt->new('record');
      # see http://www.loc.gov/marc/bibliographic/ for tag mappings, but FFT is CERN specific.
      # currently documentation is available at http://invenio-demo.cern.ch/help/admin/bibupload-admin-guide
      # tag 100 is only for changes: from J-Y LM, 2008/07/18
      #my $control = XML::Twig::Elt->new(controlfield=>{ tag=>"100", ind1=>" ", ind2=>" "});
      #$control->paste('last_child',$record);
      if ($updateRecord)
      {
          my $control = XML::Twig::Elt->new(controlfield=>{ tag=>"001", ind1=>" ", ind2=>" "},$updateRecord);
          $control->paste('last_child',$record);
      }
      # CMS note number (MARC Source of Acquisition)
      my $xml_style = $style; # remove redundant CMS
      if (lc($style) =~ 'cmspaper') {$xml_style = 'paper';} 
      &insert_datafield("037",$record,"CMS-".uc($xml_style)."-".$noteCode);

      # Title (MARC Title Statement)
      &insert_datafield("245",$record,$title);

      # Year (MARC Publication)
      &insert_datafield("260",$record,$svn_year);

      # unknown id - got from example: http://cdsweb.cern.ch/record/1101102?of=xm
      if (! $updateRecord)
      {
          my $pubdat = XML::Twig::Elt->new(datafield=>{ tag=>"269", ind1=>" ", ind2=>" "});
          &insert_subfield("a",$pubdat,"Geneva");
          &insert_subfield("b",$pubdat,"CERN");
          &insert_subfield("c",$pubdat,$svn_year);
          $pubdat->paste('last_child',$record);
      }
      
      # Data/MC indicator: tag 653, ind1:1, subfield 9: CMS, subfield a: Data/Monte-Carlo: from J-Y LM, 2010/02/10
      my $tagDataMC = XML::Twig::Elt->new(datafield=>{tag=>"653", ind1=>"1", ind2=>" "});
      &insert_subfield("9",$tagDataMC,"CMS");
      if ($dataNotMC)
      {
          &insert_subfield("a",$tagDataMC,"Data");
      }
      else
      {
          &insert_subfield("a",$tagDataMC,"Monte-Carlo");
      }
      $tagDataMC->paste('last_child',$record);

#      # CDS
#      &insert_datafield("859",$record,'cds.support@cern.ch');

      # 520 tags: (MARC Electronic Location and Access: ind1 = 3 =>abstract, subfield a=> Summary)
      # Abstract
      my $tag520 = XML::Twig::Elt->new(datafield=>{tag=>"520", ind1=>" ", ind2=>" "});
      &insert_subfield("a",$tag520,$abstract);
      $tag520->paste('last_child',$record);

      # 856 tags: (MARC Electronic Location and Access: ind1 = 4 =>HTTP, subfield y=> Link text)
      # CMS analysis page url
      &insert_856datafield($record,"http://cms.cern.ch/iCMS/analysisadmin/cadi?ancode=".$noteCode,"Additional information for the analysis (restricted access)");


      # Authorlist: need url to supply authorlist to replace "The CMS Collaboration"
      #&insert_856datafield($record,"The CMS Collaboration","CERN");

      # 980 tag: (MARC Equivalence or Cross-Reference Series Personal Name/Title"
      if ($style eq 'pas')
      {
          &insert_datafield("980",$record,"CMS-PHYSICS-ANALYSIS-SUMMARIES");
      }
      elsif ($style eq 'cmspaper')
      {
          &insert_datafield("980",$record,"CMS_Papers"); # should be ?CMSPUBDRAFTFINAL? ?CMSPUBDRAFT?
      }

      # 859:8560 tags: (email:  subfield f)
      my $tag8560 = XML::Twig::Elt->new(datafield=>{tag=>"859", ind1=>" ", ind2=>" "});
      &insert_subfield("f",$tag8560,$contactAddress);
      $tag8560->paste('last_child',$record);

      # FFT
      my $fft_tag = XML::Twig::Elt->new(datafield=>{tag=>"FFT", ind1=>" ", ind2=>" "});
      my $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"a"},$baseURL."/".$doc);
      $doc_tag->paste('last_child',$fft_tag);
      $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"t"},"Main");
      $doc_tag->paste('last_child',$fft_tag);
      $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"d"},"Fulltext in PDF");
      $doc_tag->paste('last_child',$fft_tag);
      $fft_tag->paste('last_child',$record);

      # add each figure
      if ($verbose) {print "Opening $logFile to look for figures\n";}
      open (LOGFILE, $logFile) || die ("can't open the log file $logFile: $!");
      local $/ = "\012"; # necessary when called, for some unknown reason
      while (<LOGFILE> )
      {
        chomp;
# look for start of figure blocks
        if (/^<789FIG (.*)$/)
        {
#---------- pull out the name/number
            if ($verbose) {print $_ ,"\n"};
            $figPath = undef;
            if (substr($_,-1,1) ne '>') # line wrapped
            {
              my $line = $_;
              $_ = <LOGFILE>;
              $_ = $line.$_;   #concatenate both lines
              # try again
            }
            if (!/^<789FIG (\S*)\s(.*)>$/) {die "Unsuccessfully tried to wrap 789 line:\n$_\n";}
            $figNam = $1;
            $figNum = $2;
#---------- now get the path to the file
            while (!$figPath && ($_ = <LOGFILE>))
            {
              if (/^<use (.*)/)
              {
                my $tmp = $1;
                if ($tmp =~ /(.*)>/)
                {
                   $figPath = $1;
                }
                else
                {
                   $_ = <LOGFILE>; # get next line
                   if (/(.*)>/)
                   {
                     $figPath = $tmp.$1;
                   }
                   else
                   {
                     die "Was looking for second line of path and got lost!\n";
                   }
                }
#                print "FIGPATH: ",$figPath,"\n";
              }
            }
            $ext = substr($figPath,-4,4);
            if ($ext ne '.jpg' && $ext ne '.pdf' && $ext ne '.png' && $ext ne '.jpeg')
            {
               die "Error extracting extension: ",$ext," found from ",$figPath,"\n";
            }
#---------  block processing complete. Have figure info. Now format it.
            if ( $skipfirst or $figPath =~ /BigDraft/ )
            {
                $skipfirst = undef;
            }
            else
            {
                if (! defined($figOffset) ) # set offset from first encountered figure number
                {
                    if ($figNum == 0) { $figOffset = 1 } else { $figOffset = 0 }; 
                }
                $outFile = &genFigName;
                if ($outFile)
                {
                    $fft_tag = XML::Twig::Elt->new(datafield=>{tag=>"FFT", ind1=>" ", ind2=>" "});
                    $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"a"},$outDir."/".$outFile); # need to put back URL if go to server from afs
                    $doc_tag->paste('last_child',$fft_tag);
                    $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"t"},"Additional");
                    $doc_tag->paste('last_child',$fft_tag);
                    $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"z"},"Figure");
                    $doc_tag->paste('last_child',$fft_tag);
                    $outFile =~ m/^(\S+)\.\S{3,4}$/s;
                    $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"d"},$1);
                    $doc_tag->paste('last_child',$fft_tag);
                    $fft_tag->paste('last_child',$record);
                }
            }
      }
      }
      close(LOGFILE);
      # kick out last figure
      $figNum = $figNum + 1; # otherwise sets figPart
      $outFile = &genFigName;
      if ($outFile)
      {
          $fft_tag = XML::Twig::Elt->new(datafield=>{tag=>"FFT", ind1=>" ", ind2=>" "});
          $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"a"},$outDir."/".$outFile); #ditto here for URL
          $doc_tag->paste('last_child',$fft_tag);
          $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"t"},"Additional");
          $doc_tag->paste('last_child',$fft_tag);
          $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"z"},"Figure");
          $doc_tag-> paste('last_child',$fft_tag);
          $outFile =~ m/^(\S+)\.\S{3,4}$/s;
          $doc_tag = XML::Twig::Elt->new(subfield=>{code=>"d"},$1);
          $doc_tag->paste('last_child',$fft_tag);
          $fft_tag->paste('last_child',$record);
      }
#      $record->paste('last_child',$collection);  #: from J-Y LM, 2008/07/18

      my $MANIFEST = IO::File->new("> ".$outDir."/manifest.xml") or die $!;
      if ($verbose) {print "Going to print out XML Manifest to $outDir/manifest.xml\n";}
#      open ($MANIFEST, "> ".$outDir."/manifest.xml") or die "Can't open manifest file\n";
#     print the <?xml...> line to make good xml; for xml fragment, leave it out
#      print $MANIFEST qq|<?xml version="1.0" encoding="UTF-8"?>\n|;
      $record->print($MANIFEST);
      close $MANIFEST;
      if ($verbose) {print "Closed manifest file: $outDir/manifest.xml\n";}
      return;

sub genFigName
{# Generate figure name
    my $outFile = undef;
    $newFig = "Figure_".&formatNumber($figNum+$figOffset);
    if (!$lastFigPath) # first pass
    {
    #fall through
    }
    elsif ($figNum ne $lastFigNum)
    {
      if ($lastFigPart)
      {
        $outFile = "$lastNewFig-$lastFigPart$lastExt";
        $lastFigPart = undef;
      }
      else
      {
        $outFile = "$lastNewFig$lastExt";
      }
    }
    else
    {
      if (!$lastFigPart)
      {
        $lastFigPart = 'a';
      }
      $outFile = "$lastNewFig-$lastFigPart$lastExt";
      $cmdString = "copy $lastFigPath $outDir/$outFile";
      $lastFigPart = chr(ord($lastFigPart)+1);
    }
    if ($outFile)
    {
       if (!$execute)
       {
         print "$baseDir/$lastFigPath --> $outDir/$outFile\n";
       }
       else
       {
         if ($verbose) {print "$baseDir/$lastFigPath --> $outDir/$outFile\n"};
         if (!copy ("$baseDir/$lastFigPath",$outDir."/".$outFile))
         {
             print "Copy of >>>> $lastFigPath failed\n";
             $outFile = undef;
         }
       }
    }
    $lastFigNum = $figNum;
    $lastNewFig = $newFig;
    $lastFigPath = $figPath;
    $lastExt = $ext;
    return $outFile;

}
sub formatNumber
{
#   format string  of form nn.mm as 0nn-0mm. Ignore strings with non-numeric data.
#
    my $arg = shift;
    $arg =~ s/\s/-/g; # remove any blanks
    if ($arg =~ /[^\d\.]/)
    {
      if ($arg =~ /^CP-(\d*)/)
      {
        my $out = sprintf(' CP-%03d',$1+1);
        return ($out);
      }
      elsif ($arg =~ /^([A-Z])\.(\d*)/)
      {
        my $out = sprintf('%s-%03d',$1,$2+1);
        return ($out);
      }
      else
      {
        print "formatNumber: bailout: $arg\n";
        return ($arg);
      }
    }#non-numeric, return as is
    $arg =~ /(\d*)\.*(\d*)/;
    my $num = $1;
    my $frac = $2;
    my $out;
    if ($frac eq '')
    {
      $out = sprintf('%03d',$num);
    }
    else
    {
      $out = sprintf('%03d',$num)."-".sprintf('%03d',$frac+1);
    }
    return ($out);
}
#############################################################################
sub insert_subfield {
#
# arguments:
# code (ex: "a" or )
# field: xml twig to insert into (as last child)
# value (ex: the title)
#
my $code = shift;
my $field = shift;
my $value = shift;
my $subid = XML::Twig::Elt->new(subfield=>{code=>$code},$value);
$subid->paste('last_child',$field);
}
#############################################################################
sub insert_856datafield {
# 856 records are urls: http://cdsdev.cern.ch/help/admin/bibupload-admin-guide
my $report = shift;
my $url = shift;
my $descrip = shift;
my $id = XML::Twig::Elt->new(datafield=>{tag=>"856", ind1=>"4", ind2=>" "});
my $subid = XML::Twig::Elt->new(subfield=>{code=>"u"},$url);
$subid->paste('last_child',$id);
$subid = XML::Twig::Elt->new(subfield=>{code=>"y"},$descrip);
$subid->paste('last_child',$id);
$id->paste('last_child',$record);
}
#############################################################################
sub insert_datafield {
#
# arguments:
# tag (ex: "037")
# record xml twig to insert into (as last child)
# value (ex: the title)
#
my $tag = shift;
my $record = shift;
my $value = shift;
my $id = XML::Twig::Elt->new(datafield=>{tag=>$tag, ind1=>" ", ind2=>" "});
my $subid = XML::Twig::Elt->new(subfield=>{code=>"a"},$value);
$subid->paste('last_child',$id);
$id->paste('last_child',$record);
}
#---------------------------
#
#    (was) figstrip.pl
#
#    Purpose: to create a directory of figures as used in a TDR, numbered as in the document
#
#    Requires: Modified cms-tdr.cls
#
# tracinggraphics must be turned on and the definition of \Ginclude@graphics must be modified with the following insertion:
#{0 0 .9}{#1}\typeout{<789FIG  #1 \thefigure>}\OldGinclude@graphics{#1}}
#            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
#
# Here's what we then look for in the logfile:
#----
#<789FIG introduction/BunchStructure-323_jpg 1.0>
#<introduction/BunchStructure-323_jpg.jpg, id=3354, 484.9317pt x 289.44135pt>
#File: introduction/BunchStructure-323_jpg.jpg Graphic file (type jpg)
#<use introduction/BunchStructure-323_jpg.jpg> [3] [4 <C:\Documents and Settings
#\George Alverson\My Documents\CMS\PTDR\TDR\ptdr1\tex\..\fig\introduction/BunchS
#tructure-323_jpg.jpg>]
#----
# whenever there is a warning, will see this form:
#----
#<789FIG ecal/Performance/Resolution_Comp_Hodo_3x3_704_tdr 1.6>
#
#Warning: pdflatex (file ecal/Performance/Resolution_Comp_Hodo_3x3_704_tdr.pdf):
# pdf inclusion: found pdf version <1.6>, but at most version <1.5> allowed
#
#<ecal/Performance/Resolution_Comp_Hodo_3x3_704_tdr.pdf, id=3716, 569.12625pt x
#532.99126pt>
#File: ecal/Performance/Resolution_Comp_Hodo_3x3_704_tdr.pdf Graphic file (type
#pdf)
#<use ecal/Performance/Resolution_Comp_Hodo_3x3_704_tdr.pdf> [16 <C:\Documents a
#nd Settings\George Alverson\My Documents\CMS\PTDR\TDR\ptdr1\tex\..\fig\ecal/Per
#formance/Resolution_Comp_Hodo_3x3_704_tdr.pdf>]
#----
# with multiple files in a figure (a),(b),(c), get:
#----
#<789FIG tracker/TrackerReco/muon_all_pt-col 1.10>
#<tracker/TrackerReco/muon_all_pt-col.pdf, id=3838, 569.12625pt x 546.04pt>
#File: tracker/TrackerReco/muon_all_pt-col.pdf Graphic file (type pdf)
#<use tracker/TrackerReco/muon_all_pt-col.pdf>
#<789FIG tracker/TrackerReco/muon_all_tip-col 1.10>
#<tracker/TrackerReco/muon_all_tip-col.pdf, id=3840, 569.12625pt x 546.04pt>
#File: tracker/TrackerReco/muon_all_tip-col.pdf Graphic file (type pdf)
#<use tracker/TrackerReco/muon_all_tip-col.pdf>
#<789FIG tracker/TrackerReco/muon_all_lip-col 1.10>
#<tracker/TrackerReco/muon_all_lip-col.pdf, id=3842, 569.12625pt x 546.04pt>
#File: tracker/TrackerReco/muon_all_lip-col.pdf Graphic file (type pdf)
#<use tracker/TrackerReco/muon_all_lip-col.pdf>
#---
# normal appendix
#---
#<789FIG appendix2/JetSystematicsFig B.1>
#---
# colour plates
#---
#<789FIG introduction/Hgg_m120.pdf CP 0>
#---
# Additional gotcha's:
# x 1) first figure (logo on front) is figure 0, no .xx
# 2) figures for colour plates are "CP  0", etc, and are off by 1 (CP 0 is really CP 1).
# x 3) a last single figure has to be dealt with by hand.
# 4) if there is are figures from appendices D, E, ... the Colour Plate figures will be out of order.
# 5) mixing cygwin and DOS shell may cause EOL confusion.
# x 6) becasue the logo is in general and doesn't have full path information, this should be run from general
#-------------------------------------------------------------------------
