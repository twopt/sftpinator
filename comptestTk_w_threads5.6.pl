#!/usr/bin/perl

#TODO: focusForce, $widget->focus; $widget->bind('<Return>', &sub)
BEGIN {
	$ENV{PERL_DL_NONLAZY} = 1;
}

use warnings;
use strict;
#use Encode qw/encode decode/;
use threads;
use threads::shared;

my $thr;
my $msg:shared = undef;
my $doneCopying:shared = undef;
my $doneBzip:shared = undef;
my $currentFile:shared = undef;
my $zipped:shared = undef;
my $encrypted:shared = undef;
my $fileName:shared = undef;

use Cwd;
use Tkx;
use File::Basename;
use File::Copy;
use File::Find;
use File::Spec;
use IO::Compress::Bzip2 qw(bzip2 $Bzip2Error);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Time::localtime;
use File::Copy::Recursive qw/rcopy dircopy fmove/;
use Win32::Console;
Win32::Console::Free();
#use Net::SFTP;


my $os = $^O;
my $key = PerlApp::extract_bound_file('twopt_gpg_pubkey.txt');
my $img = PerlApp::extract_bound_file('TwoPointLogo.gif'); 
my $gpg;
my ($facility, $user, $passwd);
my %fileHash; #Hash for storing file information
my $cpyDir = 'TwoPtCopies';
my $initialDir = Cwd::getdcwd();
my $sftp;
my $cmdFile = 'SFTPcmds';
my $modulePath;
my $parentDir;

#copy(PerlApp::extract_bound_file('tpconfig.pm.orig', File::Spec->catfile('MODULES', 'tpconfig.pm.orig')) or die "Failed to copy tpconfig. Exiting.";

#my $tpOrig = File::Spec->catfile(qw/mck_sftp MODULES/, 'tpconfig.pm.orig');
my $tpCurr;# = File::Spec->catfile(qw/MODULES/, 'tpconfig.pm'); 

if(!(-e $key)){
	die "'$key' wasn't found.";
}

#Check whether gpg is present
if($os eq "linux"){
	$gpg = `which gpg`;
	$sftp = `which psftp`;
}
elsif($os eq "MSWin32"){
#	$gpg = `where gpg.exe`;
#	$sftp = `where psftp.exe`;
#	$gpg = File::Spec->catfile('GPGDir', 'gpg.exe');
	$gpg = PerlApp::extract_bound_file('gpg.exe'); 
	$sftp = PerlApp::extract_bound_file('sftp_pw.exe');
	$modulePath = File::Spec->catdir((dirname($sftp),'MODULES'));
	mkdir $modulePath or die "failed to create MODULES";
}
else{
	die "OS is neither 'linux' nor 'MSWin32'.";
}

chdir(dirname($sftp));
chomp($gpg);
chomp($sftp);
if(($os eq 'linux' && !$gpg) || ($os eq 'MSWin32' && !(-e $gpg))){
	die "GPG wasn't found.";
}

if(($os eq 'linux' && !$sftp) || ($os eq 'MSWin32' && !(-e $sftp))){
	die "SFTP tool wasn't found.";
}

#Set theme style
#print Tkx::ttk__style_theme_names();
Tkx::ttk__style_theme_use('alt');
#Create main window and configure size, title, etc
my $icon = Tkx::image_create_photo(-file => $img); 

my $mw = Tkx::widget->new(".");
$mw->g_wm_title("Two Point SFTPnator | File Selection");
$mw->g_wm_minsize(500, 300);
$mw->g_wm_geometry("800x300+100+60");
$mw->g_wm_iconphoto($icon);
my $pw = $mw->new_toplevel;
$pw->g_wm_state('withdrawn');
$pw->g_wm_protocol(WM_DELETE_WINDOW => sub{ &onCancel });
$pw->g_wm_title('Two Point SFTPnator | Processing Files');
$pw->g_wm_minsize(500, 300);
$pw->g_wm_maxsize(500, 300);
$pw->g_wm_geometry("500x300+100+60");
$pw->g_wm_iconphoto($icon);

my $lw = $mw->new_toplevel;
$lw->g_wm_state('withdrawn');
$lw->g_wm_protocol(WM_DELETE_WINDOW => sub{ &onCancel });
$lw->g_wm_title('Two Point SFTPnator | SFTP');
$lw->g_wm_minsize(300, 200);
$lw->g_wm_maxsize(300, 200);
$lw->g_wm_geometry("300x200+100+60");
$lw->g_wm_iconphoto($icon);

my $pframe = $pw->new_ttk__labelframe(-text => 'Progress:', -labelanchor => 'n', -padding => '10 0 10 0', -borderwidth => 2, -relief => 'sunken');
$pframe->g_grid(-column => 0, -row => 0, -sticky => 'nwes', -columnspan => 3, -pady => 10);

my $ptext = $pframe->new_tk__text(-wrap => 'none', -state => 'disabled');
$ptext->g_grid(-column => 0, -row => 0, -sticky => 'news', -columnspan => 2);

my $pvSBar = $pframe->new_ttk__scrollbar(-orient => 'vertical', -command => [$ptext, 'yview']);
$pvSBar->g_grid(-column => 2, -row => 0, -sticky => 'news');

my $phSBar = $pframe->new_ttk__scrollbar(-orient => 'horizontal', -command => [$ptext, 'xview']);
$phSBar->g_grid(-column => 0, -row => 1, -sticky => 'nwes', -columnspan => 2);

$ptext->configure(-xscrollcommand => [$phSBar, 'set']);
$ptext->configure(-yscrollcommand => [$pvSBar, 'set']);

my $pPgrBar = $pw->new_ttk__progressbar(-orient => 'horizontal', -length => 500, -mode => 'determinate');
$pPgrBar->g_grid(-column => 0, -row => 1, -sticky => 'n', -columnspan => 2);
 
my $pContButton = $pw->new_ttk__button(-text => 'Continue', -state => 'disabled', -command => sub{ &onContinue });
$pContButton->g_grid(-column => 1, -row => 2, -sticky => 'se');
$pContButton->g_bind('<Return>', sub{ $pContButton->invoke()  });

my $pCancelButton = $pw->new_ttk__button(-text =>'Cancel', -command => sub{ &onCancel });
$pCancelButton->g_grid(-column => 0, -row => 2, -sticky => 'sw');

my $lFLabel = $lw->new_ttk__label(-text => 'Facility Name:');
$lFLabel->g_grid(-column => 0, -row => 0, -sticky => 'ws');

my $lNLabel = $lw->new_ttk__label(-text => 'SFTP Login:');
$lNLabel->g_grid(-column => 0, -row => 2, -sticky => 'ws');

my $lPLabel = $lw->new_ttk__label(-text => 'SFTP Password:');
$lPLabel->g_grid(-column => 0, -row => 4, -sticky => 'ws');

my $lFEntry = $lw->new_ttk__entry(-textvariable => \$facility);
$lFEntry->g_grid(-column => 0, -row => 1, -sticky => 'ew');

my $lNEntry = $lw->new_ttk__entry(-textvariable => \$user);
$lNEntry->g_grid(-column => 0, -row => 3, -sticky => 'ew');

my $lPEntry = $lw->new_ttk__entry(-textvariable => \$passwd, -show => '*');
$lPEntry->g_grid(-column => 0, -row => 5, -sticky => 'ew');

$lFEntry->g_bind('<Return>', sub{ $lNEntry->g_focus() });
$lNEntry->g_bind('<Return>', sub{ $lPEntry->g_focus() });
#$lNEntry->bind('<Return>', $lPEntry->configure(-state => 'focus'));

my $lUpButton = $lw->new_ttk__button(-text => 'Upload', -command => sub{ &uploadFile }); 
$lUpButton->g_grid(-column => 0, -row => 6, -sticky => 'ew');
$lPEntry->g_bind('<Return>', sub{ $lUpButton->invoke() });

#Create a label saying 'Selected Files'
#my $label = $mw->new_ttk__label(-text => 'Selected Files:', -anchor => 'center');
#$label->g_grid(-column => 0, -row => 0, -sticky => 'nwes', -columnspan => 3);

#Create a frame to hold the treeview
my $frame = $mw->new_ttk__labelframe(-text => 'Selected Files', -labelanchor => 'n', -padding => '10 0 10 0', -borderwidth => 2, -relief => 'sunken');
$frame->g_grid(-column => 0, -row => 0, -sticky => 'nwes', -columnspan => 4, -pady => 10);

#Define treeview columns and create the treeview itself
my $tcolumns = 'name path size date';
my $tview = $frame->new_ttk__treeview(-columns => $tcolumns, -show => 'headings');
$tview->tag_configure("directory", -background => "dark grey");
$tview->tag_configure("child", -background => "light grey");

$tview->column('name', -anchor => 'w', -minwidth => 200);
$tview->column('path', -anchor => 'w', -minwidth => 200);
$tview->column('date', -anchor => 'w', -minwidth => 250);
$tview->column('size', -anchor => 'e', -minwidth => 200);
$tview->heading('name', -text => 'Name');
$tview->heading('path', -text => 'Path');
$tview->heading('size', -text => 'Size');
$tview->heading('date', -text => 'Date');
$tview->g_grid(-column => 0, -row => 0, -sticky => 'nwes', -columnspan => 3);


my $vSBar = $frame->new_ttk__scrollbar(-orient => 'vertical', -command => [$tview, 'yview']);
$vSBar->g_grid(-column => 4, -row => 0, -sticky => 'nwes');

my $hSBar = $frame->new_ttk__scrollbar(-orient => 'horizontal', -command => [$tview, 'xview']);
$hSBar->g_grid(-column => 0, -row => 1, -sticky => 'wes', -columnspan => 4);

$tview->configure(-xscrollcommand => [$hSBar, 'set']);
$tview->configure(-yscrollcommand => [$vSBar, 'set']);
#Create 3 buttons for adding files, removing files, and proceeding with the process
my $button1 = $mw->new_ttk__button(-text => 'Add Files', -command => sub{ &select_files(\%fileHash, \$tview, 'file') });
$button1->g_grid(-column => 0, -row => 1, -sticky => 'wes');

my $button2 = $mw->new_ttk__button(-text => 'Add Directory', -command => sub{ &select_files(\%fileHash, \$tview, 'dir') });
$button2->g_grid(-column => 1, -row => 1, -sticky => 'wes');

my $button3 = $mw->new_ttk__button(-text => 'Remove', -command => sub{ &unselect_files(\%fileHash, \$tview) }); 
$button3->g_grid(-column => 2, -row => 1, -sticky => 'wes');

my $button4 = $mw->new_ttk__button(-text => 'Next', -command => sub{ &processFiles(\%fileHash, \$tview, \$cpyDir, \$ptext, \$pPgrBar) }); 
$button4->g_grid(-column => 3, -row => 1, -sticky => 'wes');


#Assign weights to grids' columns and rows

#Main window grid assignments
$mw->g_grid_columnconfigure(0, -weight => 1);
$mw->g_grid_columnconfigure(1, -weight => 1);
$mw->g_grid_columnconfigure(2, -weight => 1);
$mw->g_grid_columnconfigure(3, -weight => 1);

$mw->g_grid_rowconfigure(0, -weight => 1);
$mw->g_grid_rowconfigure(1, -weight => 0);
#$mw->g_grid_rowconfigure(2, -weight => 0);

#Main window's frame grid assignments
$frame->g_grid_columnconfigure(0, -weight => 1);
$frame->g_grid_columnconfigure(1, -weight => 1);
$frame->g_grid_columnconfigure(2, -weight => 1);
$frame->g_grid_columnconfigure(3, -weight => 0);
$frame->g_grid_columnconfigure(4, -weight => 0);


$frame->g_grid_rowconfigure(0, -weight => 1);
$frame->g_grid_rowconfigure(1, -weight => 0);

#Progress window grid assignments
$pw->g_grid_columnconfigure(0, -weight => 1);
$pw->g_grid_columnconfigure(1, -weight => 1);
#$pw->g_grid_columnconfigure(2, -weight => 1);

$pw->g_grid_rowconfigure(0, -weight => 1);
$pw->g_grid_rowconfigure(1, -weight => 0);
$pw->g_grid_rowconfigure(2, -weight => 0);

#Progress window's frame grid assignments
$pframe->g_grid_columnconfigure(0, -weight => 1);
$pframe->g_grid_columnconfigure(1, -weight => 0);
$pframe->g_grid_columnconfigure(2, -weight => 0);
#$pframe->g_grid_columnconfigure(3, -weight => 0);

$pframe->g_grid_rowconfigure(0, -weight => 1);
$pframe->g_grid_rowconfigure(1, -weight => 0);


$lw->g_grid_columnconfigure(0, -weight => 1);

$lw->g_grid_rowconfigure(0, -weight => 1);
$lw->g_grid_rowconfigure(1, -weight => 1);
$lw->g_grid_rowconfigure(2, -weight => 1);
$lw->g_grid_rowconfigure(3, -weight => 1);
$lw->g_grid_rowconfigure(4, -weight => 1);
$lw->g_grid_rowconfigure(5, -weight => 1);
$lw->g_grid_rowconfigure(6, -weight => 1);

$mw->g_raise();
#Run the UI loop
Tkx::MainLoop();

my $lpath = undef;
sub checkThr {
	my @hashKeys = @_;
	if(!$lpath){
		$lpath = shift @hashKeys;
		if(!$lpath && !$doneCopying){
			$doneCopying = 1;
			opendir(my $dir, $cpyDir) or die "Couldn't open $cpyDir";		
			@hashKeys = grep { !/^\.+$/ } readdir($dir);
			closedir($dir);
			$lpath = shift @hashKeys;
			&roInsertText(\$ptext, "All files were copied.\n\nCompressing copied files to bzip2:\n");
			$msg = undef;
		}

		if(!$lpath && $doneCopying){
			&roInsertText(\$ptext, "All files were compressed to bzip2.\n\nCompressing the directory with copies into a zip archive:\n");
			$msg = undef;
			$thr = threads->create(sub{ &thrZip });
			$thr->detach();
			&zipChk;
			return;
		}

		if(!$doneCopying && !$msg){
			&roInsertText(\$ptext, "\tCopying ".$fileHash{$lpath}->[0]."\n");
			$thr = threads->create(sub{ &thrCopy($lpath, $cpyDir, $fileHash{$lpath}->[0]) });
			$thr->detach();
		}
		if($doneCopying && !$msg){
			&roInsertText(\$ptext, "\tCompressing ".&basename($lpath)."\n");
			$thr = threads->create(sub{ &thrBzip(File::Spec->catfile($cpyDir, $lpath), $lpath) });
			$thr->detach();
		}

	}
	if($msg){
		if($msg =~ 'Failed' || $msg =~ 'failed'){
			&onCleanExit(1, $msg);
		}
		&roInsertText(\$ptext, $msg);
		$pPgrBar->step(1);
		$msg = undef;
		$lpath = undef;
		&checkThr(@hashKeys);
	}
	else{
		Tkx::after(500, sub{ &checkThr(@hashKeys) });
	}
}

sub zipChk {
	if($zipped){
		if($zipped == 2){
			&onCleanExit(1, $msg);	
		}
		&roInsertText(\$ptext, "File $fileName generated.\n\n");
		&rmDir($cpyDir);
		$pPgrBar->step(1);
		&roInsertText(\$ptext, "Encrypting $fileName.\n");
		$thr = threads->create(sub{ &thrEncrypt });
		$thr->detach();
		&encrChk;
		$pw->g_raise();
		return;
	}
	else{
		Tkx::after(500, [\&zipChk]);
	}
}

sub thrZip {
	my $zip = Archive::Zip->new();
	$zip->addTree($cpyDir, '');
	$fileName = $cpyDir."_".(localtime->year()+1900).sprintf("%02d",(localtime->mon()+1)).sprintf("%02d",(localtime->mday())).sprintf("%02d",(localtime->hour())).sprintf("%02d",(localtime->min())).sprintf("%02d",(localtime->sec())).".zip"; 
	unless($zip->writeToFileNamed($fileName) == AZ_OK){
		$msg = "Write to ZIP failed.";
		$zipped = 2;
		return;
	}
	$zipped = 1;
}

sub encrChk {
	$pw->g_raise();
	if($encrypted){
		if($encrypted == 2){
			&onCleanExit(1, $msg);
		}
		&roInsertText(\$ptext, "Encryption of $fileName is complete.\n\n");
		&rmDir("gnupg");
		unlink("$fileName");
		$fileName .= '.gpg';
		$pPgrBar->step(1);
		&roInsertText(\$ptext, "Files are ready to be sent.\nPress Continue to upload the the encrypted file.\n");
		$pContButton->configure(-state => 'active');
		$pContButton->g_focus();
		return;
	}
	else{
		Tkx::after(500, [\&encrChk]);
	}
}

sub thrEncrypt {
	unless(mkdir "gnupg"){
		$msg = "Failed to create home directory for gpg.";
		$encrypted = 2;
		return;
	}
	unless(open GPGCONF, ">gnupg/gpg.conf"){
		$msg = "Failed to open gpg.conf for writing.";
		$encrypted = 2;
		return;
		
	}
	print GPGCONF "keyserver hkp://subkeys.pgp.net\n";
	close GPGCONF;

	my $gpgRes = system($gpg, "--homedir", "gnupg", "--batch", "gnupg/gpg.conf");

	$gpgRes = system($gpg, "--homedir", "gnupg", "--batch", "--import", "$key");

	if($gpgRes ne 0){
		$msg = "Failed to import $key.";
		$encrypted = 2;
		return;
	}
	
#	unlink 'runcmd.tmp' if(-e 'runcmd.tmp');
#	unlink "$cpyDir.zip.gpg" if(-f "$cpyDir.zip.gpg");
#	open(TMPCMD, '>runcmd.bat');
#	print TMPCMD "$gpg --homedir gnupg --batch gnupg/gpg.conf\n";
#	print TMPCMD "$gpg --homedir gnupg --batch --import $key\n";
#	print TMPCMD "$gpg --homedir gnupg --batch --always-trust -e -r info\@twopoint.com $cpyDir.zip\n";
#	print TMPCMD "dir > runcmd.tmp\n";
#	print TMPCMD "cls";
#	close(TMPCMD);

#"--always-trust" instead of "--trust-model", "always"
	$gpgRes = system($gpg, "--homedir", "gnupg", "--batch", "--always-trust", "-e", "-r", "info\@twopoint.com", $fileName); 

	if($gpgRes ne 0){
		$msg = "Failed to encrypt '$fileName'";
		$encrypted = 2;
		return;
	}

	$encrypted = 1;

#	system('start /B /MIN cmd /c runcmd.bat');
#	if(-e File::Spec->catfile(dirname($sftp), 'runcmd.tmp')){
#		$encrypted = 1;
#	}
#	else{
#		Tkx::tk___messageBox(-message => "Gpg failed.");
#	}
}

sub rmDir {
	my ($dirToRemove) = @_;
	opendir(my $dirToRem, $dirToRemove) or die "Couldn't open $dirToRemove";
	my @dirContents = grep { !/^\.+$/ } readdir($dirToRem);
	closedir($dirToRem);
	foreach(@dirContents){
		my $fileToUnlink = File::Spec->catfile($dirToRemove, $_);
		if(-f $fileToUnlink ){
			unlink $fileToUnlink;
		}
		elsif(-d $fileToUnlink ){
			&rmDir($fileToUnlink);
		}
		else{
			die "'$_' in '$dirToRemove' is not recognized as either file or directory.";
		}
	}
	rmdir $dirToRemove;
}

sub roInsertText {
	my ($textRef, $str) = @_;

	$$textRef->configure(-state => 'normal');
	$$textRef->insert('end', $str);
	$$textRef->configure(-state => 'disabled');
	$$textRef->see('end wordstart');
}

#Subroutine for browsing directories and adding files to the list
sub select_files {
	my ($fileHashRef, $tviewRef, $seleType)  = @_;
	my $files = undef;
	my @fStats = undef;
	my %dups;
	my ($bsName, $bsPath, $printDups);
	my @types = (["All files", '*'], ["Text Files", [qw/.txt/]], );
	if ($seleType eq 'file'){
		$files = Tkx::tk___getOpenFile(-filetypes => \@types, -multiple => 'true', -initialdir => $initialDir, -parent => $mw);
	}
	else{
		$files = Tkx::tk___chooseDirectory(-initialdir => $initialDir, -parent => $mw, -mustexist => 'true'); 
	}

	#$files = decode('UTF-8', $files);
	#$files = encode('cp1252', $files);
	#Tkx::tk___messageBox(-message => "Selected files: $files") if($files);
	#open(my $wfh, '>weird_text.txt') or die "couldn't create weird_text";
	#print $wfh "$files\n";
	#close $wfh;
	$printDups = 0;
	while(!($files =~ /^\s*$/)){
		if($files =~ s/^{(.+?)} ?//){
			$bsPath = $1;
		@fStats = stat($bsPath);
	}
	elsif($files =~ s/^(\S+) ?//){
		$bsPath = $1;
	@fStats = stat($bsPath);
	}

	$bsName = &basename($bsPath);	
	foreach(keys %$fileHashRef){
		if(($bsName eq $$fileHashRef{$_}->[0]) and ($bsPath ne $_)){
			if(!(exists $dups{$bsName})){
				$dups{$bsName} = ($bsPath);
			}
			else {
				push(@{$dups{$bsName}}, $bsPath);
			}
			$printDups = 1;
		}

	}
	if($printDups eq 1){
		open(my $dupHandle, ">", File::Spec->catfile($initialDir, "TwoPoint_duplicates.txt"));
		foreach(keys %dups){
			if(exists($dups{$_})){
				print $dupHandle "Found duplicates for name '$_'. Duplicate paths:\n";
				foreach my $pdup ($dups{$_}){
					print $dupHandle "$pdup\n";
				}
				print $dupHandle "\n";
			}
		}
		close($dupHandle);
		Tkx::tk___messageBox(-icon => 'warning', -message => "Multiple files found with the same filename, please re-name the files listed in '$initialDir\\TwoPoint_duplicates.txt' and start again.");
		exit 1;

	}


	$$fileHashRef{$bsPath} = [&basename($bsPath), $fStats[7], scalar(ctime($fStats[10]))];
	if ($seleType eq 'file'){
		foreach(keys %$fileHashRef){
			if(!($$tviewRef->exists($_))){
				$$tviewRef->insert("", "end", -id => $_);
			}
			$$tviewRef->set($_, "name", $$fileHashRef{$_}->[0]);
			$$tviewRef->set($_, "path", $_);
			$$tviewRef->set($_, "size", &scale_size($$fileHashRef{$_}->[1]));
			$$tviewRef->set($_, "date", $$fileHashRef{$_}->[2]);
		}
	}
	else{
		if(!($$tviewRef->exists($bsPath))){                   		
			$$tviewRef->insert("", "end", -id => $bsPath, -tags => "directory");
			$$tviewRef->set($bsPath, "name", $$fileHashRef{$bsPath}->[0]);
			$$tviewRef->set($bsPath, "path", $bsPath);
			$$tviewRef->set($bsPath, "size", &scale_size($$fileHashRef{$bsPath}->[1]));
			$$tviewRef->set($bsPath, "date", $$fileHashRef{$bsPath}->[2]);
			$parentDir = $bsPath;
			find(\&add_dir_tree, "$bsPath");
			$$tviewRef->item($bsPath, -open => "true");
		}
	}                                                }
}

sub add_dir_tree {
	if(-f $_){
		$tview->insert("$parentDir", "end", -id => $File::Find::name, -tags => "child");
		$tview->set($File::Find::name, "name", $_);
		$tview->set($File::Find::name, "path", $File::Find::name);
		$tview->set($File::Find::name, "size", &scale_size((stat $_)[7]));
		$tview->set($File::Find::name, "date", scalar(ctime((stat $_)[10])));
	}
}

sub scale_size {
	my ($toScale) = @_;
	my $prefix = 0;
	my @prefixes = qw/B KB MB GB TB PB/;
	while($toScale > 1024) {
		$toScale/=1024;
		$prefix++;
	}

	return sprintf("%.2f%s", $toScale, $prefixes[$prefix]);
}
#Subroutine for removing files from the list (also removes from hash)
sub unselect_files {
	my ($fileHashRef, $tviewRef)  = @_;
	my $selected = $$tviewRef->selection();

	while(!($selected =~ /^\s*$/)){
		if($selected =~ s/^{(.+?)} ?//){
			if($$tviewRef->tag_has("child", "$1")){
				Tkx::tk___messageBox(-icon => 'error', -message => "File '$1' is bound to a directory tree.");
				last;
			}
			$$tviewRef->delete("{$1}");
			delete($$fileHashRef{$1});
		}
		elsif($selected =~ s/^(\S+) ?//){
			if($$tviewRef->tag_has("child", "$1")){
				Tkx::tk___messageBox(-icon => 'error', -message => "File '$1' is bound to a directory tree.");
				last;
			}
			$$tviewRef->delete($1);
			delete($$fileHashRef{$1});
		}
	}
}

sub onCleanExit {
	my ($exitCode, $exitMsg) = @_;
	if(defined($exitMsg)){
		Tkx::tk___messageBox(-icon => 'error', -message => $exitMsg);
	}
	if(-d $cpyDir){
		&rmDir($cpyDir);
	}
	if(-f "$fileName"){
		unlink "$fileName";
	}
	if(-d "gnupg"){
		&rmDir("gnupg");
	}
	$mw->g_destroy();
	exit($exitCode);
}

sub onCancel {
	my $response = Tkx::tk___messageBox(-message => 'Are you sure you want to cancel?', -detail => 'NOTE: This will delete any generated files by the program.', -type => 'yesno', -icon => 'question', -default => 'no', -parent => $pw);
	if($response eq 'yes'){
		&onCleanExit(0);
	}
	else{
		return;
	}

}

sub thrCopy {
	my ($path, $dir, $bName) = @_; 
	unless(rcopy($path, File::Spec->catfile($dir, $bName))){
		$msg = "Failed to copy $path into $dir$bName. Exiting.";
		return;	
	}
	$msg = "\t+File $bName copied.\n";
}

sub thrBzip {
	my ($fPath, $fName) = @_;
	if(-d $fPath){
		finddepth(\&bzipDir, $fPath);
		$msg = "\t+Files in directory $fName compressed.\n";	
	}
	else{
		print "Reg path = $fPath\n";
		unless(bzip2 $fPath => $fPath.".bz2" , BinModeIn => 1, AutoClose => 1){
			$msg = "Compression of file '$fPath' failed: $Bzip2Error";
			return;
		}
		unlink $fPath;
		$msg = "\t+File $fName compressed.\n";
	}
}

sub bzipDir {
	if(-f $_){
		unless(bzip2 $_ => $_.".bz2" , BinModeIn => 1, AutoClose => 1){
			$msg = "Compression of file '$_' failed: $Bzip2Error";
			return;
		}
		unlink $_;
	}
}

sub processFiles {
	my ($fileHashRef, $tviewRef, $cpyDirRef, $ptextRef, $pBarRef)  = @_;
	if(!(keys %$fileHashRef)){ return; }
	$mw->g_wm_state('withdrawn');
	my $pw_g = $mw->g_wm_geometry();
	$pw_g =~ s/\d+x\d+/500x300/;
	$pw->g_wm_deiconify();
	$pw->g_wm_geometry($pw_g);
	$pw->g_wm_state('normal');
	$pw->g_raise();
	my $nameNum = 1;
	&roInsertText($ptextRef, "Creating directory for copies..\n"); 
	while(-d $$cpyDirRef){
		$$cpyDirRef =~ s/^(TwoPtCopies).*$/$1_$nameNum/;
		$nameNum += 1;
	}
	mkdir $$cpyDirRef or die "Couldn't create directory $$cpyDirRef";
	my $fullCpyPath = File::Spec->curdir().$$cpyDirRef;
	$$pBarRef->configure(-maximum => (scalar(keys %$fileHashRef)*2)+2);
	Tkx::update();
	&roInsertText($ptextRef, "\tdirectory $fullCpyPath created.\n\nCopying files into $$cpyDirRef:\n");

	&checkThr(keys %$fileHashRef);
#		foreach(keys %$fileHashRef){	
#			if(-f $_){
#		print "Copying file $source into ".File::Spec->catfile($destination, $sourceBaseName)."\n";
#				my $sourceBaseName = $$fileHashRef{$_}->[0];
#				&roInsertText($ptextRef, "\tcopying $sourceBaseName\n");
#				$thr = threads->create(\&thrCopy($_, $$cpyDirRef, $sourceBaseName));
#				$thr->detach();
#				while(!$msg){
#					Tkx::update();
#				}
#				&roInsertText($ptextRef, $msg);
#				$msg = undef;
#			}
#			else{
#				Tkx::tk___messageBox(-message => "File '$_' not found. Ignoring this file.");
#			}
#			$$pBarRef->step(1);
#			Tkx::update();
#		}
#
#	&roInsertText($ptextRef, "All files copied.\n\nCompressing copied files to bzip2:\n");
#	opendir(my $dir, $$cpyDirRef) or die "Couldn't open $$cpyDirRef";
#	my @dirContents = grep { !/^\.+$/ } readdir($dir);
#	closedir($dir);
#	Tkx::update();
#
#	foreach (@dirContents){
#		my $filePath = File::Spec->catfile($$cpyDirRef, $_);
#		if(-f $filePath){
#			&roInsertText($ptextRef, "\tcompressing $_\n");
#			$thr = threads->create(\&thrBzip($filePath, $_));
#			$thr->detach();
#			#bzip2 $filePath => $filePath.".bz2" or die "Compression of file '$filePath' failed: $Bzip2Error";
#			#unlink $filePath;
#			while(!$msg){
#				Tkx::update();
#			}
#			&roInsertText($ptextRef, $msg);
#			$msg = undef;
#		}
#		else{
#			Tkx::tk___messageBox(-message => "File '$_' not found. Ignoring this file.");
#		}
#		$$pBarRef->step(1);
#		Tkx::update();
#	}
#	
#	&roInsertText($ptextRef, "All files compressed to bzip2.\n\nCompressing the directory with copies into a zip archive:\n");
#	Tkx::update();
#	my $zip = Archive::Zip->new();
#	$zip->addTree($$cpyDirRef,$$cpyDirRef);
#	$zip->writeToFileNamed($$cpyDirRef.".zip");
#	&roInsertText($ptextRef, "Directory $$cpyDirRef.zip generated.\n\n");
#	&rmDir($$cpyDirRef);
#	&roInsertText($ptextRef, "Encrypting $$cpyDirRef.zip.\n");
#	mkdir "gnupg" or die "Failed to create home directory for gpg.";
#	open GPGCONF, ">gnupg/gpg.conf" or die "Failed to open gpg.conf for writing.";
#	print GPGCONF "keyserver hkp://subkeys.pgp.net\n";
#	close GPGCONF;
#
#
#	my $gpgRes = system($gpg, "--homedir", "gnupg", "--batch", "gnupg/gpg.conf");
#
#	$gpgRes = system($gpg, "--homedir", "gnupg", "--batch", "--import", "$key");
#
#	if($gpgRes ne 0){
#		die "Failed to import $key.";
#	}
#	
#	if(-f "$$cpyDirRef.zip.gpg"){
#		unlink "$$cpyDirRef.zip.gpg";
#	}
#
#	$gpgRes = system($gpg, "--homedir", "gnupg", "--batch", "--always-trust", "-e", "-r", "info\@twopoint.com", $$cpyDirRef.".zip"); 
#
#	if($gpgRes ne 0){
#		die "Failed to encrypt '$$cpyDirRef.zip'";
#	}
#	&roInsertText($ptextRef, "Encryption of $$cpyDirRef.zip is complete.\n\n");
#	&rmDir("gnupg");
#	unlink("$$cpyDirRef.zip");	
#	&roInsertText($ptextRef, "Files are ready to be sent.\nPress Continue to upload the the encrypted file.\n");
#	return;

}

sub onContinue {
	$pw->g_wm_state('withdrawn');
	my $lw_g = $pw->g_wm_geometry();
	$lw_g =~ s/\d+x\d+/500x300/;
	$lw->g_wm_deiconify();
	$lw->g_wm_geometry($lw_g);
	$lw->g_wm_state('normal');
	$lw->g_raise();
	$lw->g_focus();
	$lFEntry->g_focus();
}

sub uploadFile {
	$lUpButton->configure(-text => 'Uploading...');
	$lUpButton->configure(-state => 'disabled');
	$msg = undef;
	$thr = threads->create(sub{ &thrUpload });
	$thr->detach();
	&uploadChk;
	$lw->g_raise();
	$lw->g_focus();
}

sub uploadChk {
	$lw->g_raise();
	if($msg){
		Tkx::tk___messageBox(-message => $msg);
		$lw->g_focus();
		if($msg eq 'File upload was successful.'){
			unlink($fileName);
			exit;
		}
		$lUpButton->configure(-text => 'Upload');
		$lUpButton->configure(-state => 'active');
	}
	else{
		Tkx::after(500, [\&uploadChk]);
	}
}

sub thrUpload {
	chomp $facility;
	chomp $user;
	chomp $passwd;
	my $missingField;
	my $fac = $facility;
	$fac =~ s/\s//g;
	if(!$fac){
		$msg = 'Facility was not defined';
		return;
	}
	#$fileName = "$cpyDir.zip.gpg";
	$fileName =~ /^.*(_.*?)$/;
	move("$fileName", "$fac$1");
	$fileName = "$fac$1";
	$tpCurr = File::Spec->catfile($modulePath, 'tpconfig.pm');
	
	unless(open WFILE, ">$tpCurr"){
		$msg = "Failed to open tp file for writing";	
	}
	
	#open RFILE, "<$tpOrig" or die "failed to open tp file for reading";
	foreach(PerlApp::get_bound_file('tpconfig.pm.orig')){
		if($_ =~ /\$SFTP_LOGIN=/){
			print WFILE "\$SFTP_LOGIN='$user';\n";
		}
		elsif($_ =~ /\$SFTP_PASSWD=/){
			print WFILE "\$SFTP_PASSWD='$passwd';\n";
		}
		else{
			print WFILE $_;
		}
	}
	close WFILE;
	#close RFILE;
	my $resFile = File::Spec->catfile(dirname($sftp), 'sftp_log.txt');
	system(qq#$sftp "$fileName" "$user" > $resFile#);
#	open CMDFILE, ">$cmdFile" or die "failed to open cmdfile";
#	print CMDFILE "put $fileName rkim/$fileName";
#	close(CMDFILE);
#	my $res = system("$sftp", "-batch", "-sshlog", "psftplog", "-b", "$cmdFile", "abc\@sftp.twopoint.com");
#	open PSFTPLOG, "<psftplog" or die "failed to open psftplog.";
#	foreach(<PSFTPLOG>){
#		if(/Event Log:\s+ssh-ed/){
#			$_ =~ /.*\s+([a-zA-Z0-9:]+)\s?$/;
#			$hostkey = $1;
#		}
#	}
#	close(PSFTPLOG);
#	unlink("psftplog");
#	chomp($hostkey);
#	$res = system("$sftp", "-b", "$cmdFile", "-hostkey", "$hostkey", "-batch", "-l", "$user", "-pw", "$passwd", "sftp.twopoint.com");
#	unlink("$cmdFile");
	unlink($tpCurr);

	my $res = '';
	
	unless(open RFILE, "<$resFile"){
		$msg = "Failed to open sftp_result file";	
	}
	while(<RFILE>){
		$res .= $_."\n";
	}
	
	close(RFILE);

	unlink($resFile);
	if($res =~ /ERROR:\slogin failed/){
		#Tkx::tk___messageBox(-message => "Login failed.");
		$msg = "Login failed.";
	}
	elsif($res =~ /(ERROR:.*$)/){
		#Tkx::tk__messageBox(-message=> "Upload failed:\n$1");
		$msg = "Upload failed: $1";
	}
	elsif($res =~ /File.*sent to.*successfully/){
		#Tkx::tk___messageBox(-message => "File upload was successful.");
		$msg = "File upload was successful.";
	}
	else{
		#Tkx::tk__messageBox(-message => "Sftp tool is in ambiguous state");
		$msg = "Ambiguous state: $res";
	}
}

#sub uploadFilePSFTP{
#	chomp $user;
#	chomp $passwd;
#	my $hostkey;
#	my @ret = `$psftp -batch -b $cmdFile abc\@sftp.twopoint.com`;
#	foreach(@ret){
#		if(/.*ssh-rsa/){
#			$_ =~ /.*\s+ ([a-zA-Z0-9:]+)\s?$/;
#			$hostkey = $1;
#		}
#	}
#	my $res = system("$psftp", "-b", "$cmdFile", "-hostkey", "$hostkey", "-batch", "-l", "$user", "-pw", "$passwd", "-hostkey", "$hostkey", "sftp.twopoint.com", ">", "psftptemp.txt");
#
#	if($res){
#		Tkx::tk___messageBox(-message => "PSFTP failed.");
#		unlink("psftptemp.txt");
#	}
#	else{
#		Tkx::tk___messageBox(-message => "Upload was successful.");
#		unlink("psftptemp.txt");
#		exit;
#	}
#}
#NET::SFTP VERSION
#sub uploadFile{
#	#Tkx::tk___messageBox(-message => "You still don't have the library");
#	$sftpHost = 'sftp.twopoint.com';
#	chomp $user;
#	chomp $passwd;
#	my %sftpArgs = (user => $user, password => $passwd);
#	my $sftpCon = Net::SFTP->new($sftpHost, %sftpArgs);
#	if(!$sftpCon){
#		Tkx::tk___messageBox(-message => "Login failed.");	
#	}
#	else{
#		$sftpCon->put("/data/rkim/pground/pground/life_advice.orig", "rkim/life_advice.orig");
#		if(scalar($sftpCon->status) ne 0){
#			Tkx::tk___messageBox(-message => "Upload failed");
#		}
#		else{
#			Tkx::tk___messageBox(-message => "File uploaded");
#			exit;
#		}
#	}
#}
