# common.pl
# This is a library of commonly used functions
# Developed by Wilson Farrell for use within the Town of Cary.
#
#    Copyright (C) 2013 Town of Cary, NC (Wilson Farrell, Developer)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

####### Standard functions #######
sub posixTimeToDB {
    my ($ptime) = @_;
    my ($lsec,$lmin,$lhour,$lday,$lmon,$lyear) = localtime($ptime);
    return sprintf "%d-%02d-%02d %02d:%02d:%02d", $lyear + 1900, $lmon + 1,$lday,$lhour,$lmin,$lsec;
    
}

sub posixTimeToReg {
    my ($ptime) = @_;
    my ($lsec,$lmin,$lhour,$lday,$lmon,$lyear) = localtime($ptime);
    return sprintf "%02d/%02d/%d %02d:%02d:%02d", $lmon + 1,$lday,$lyear + 1900, $lhour,$lmin,$lsec;
    
}

sub DBTimetoPosix {
    my ($dbtime) = @_;
    if ($dbtime =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) { 
	my $year = $1 - 1900;
	my $month = $2 - 1;
	my $day = $3;
	my $hour = $4;
	my $min = $5;
	my $sec = $6;
	return timelocal($sec,$min,$hour,$day,$month,$year);
    } 
    return 0;
}

sub waitFor {
    my ($waitForSecs) = @_;
    return if ($waitForSecs == 0);
	
    my $startTime = 0;
    my $time = time();
    waitUntil($time + $waitForSecs);
}

sub waitUntil {
    my ($startTime) = @_;
    my $notTime = 1;
    
    sayErr("Will Run again at " . time2str('%c',$startTime));
    $waiting = 1;
    while ($notTime == 1) {
        $time = time();
        if ($time < $startTime) {
            if (($startTime - $time) <= 60) {
                #sayErr ("Waiting for " . ($startTime - $time) . " secs");
                &pauseFor($startTime - $time);
            } else {
                #sayErr ("Waiting for " . (($startTime - $time) / 2) . " secs");
                &pauseFor(($startTime - $time) / 2);
            }
        } else {
            $notTime = 0;
        }
    }
    $waiting = 0;
}

sub pauseFor {
    my ($secs) =@_;
    select(undef, undef, undef, $secs);
} 


sub trim($) {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

sub setupStdout {
    ($filename_prefix) = @_;
}

sub sayErr {
    my ($msg) = @_;
    $pre = (defined $filename_prefix && $filename_prefix ne "") ? $filename_prefix : "stdout_";
    if (1) {
	my $outFile = $pre . time2str("%Y%m",time()) .".txt";
	open (LOGFILE, ">> $outFile") or die "Log File not available";
	print LOGFILE time2str("%c",time()) . ": " . $msg . $eol;
	close(LOGFILE);
    } else {
	print $msg . $eol;
	$|++;
    }
}

sub sayDie {
    my ($msg) = @_;
    sayErr($msg);
    exit;
}

sub print_CSV_of_a_of_h {
    my ($file, $a_ref) = @_;
    my @array = @$a_ref;
    my @fields = keys %{$array[0]};
    my $csv = Text::CSV_XS->new({always_quote => 1,binary => 1, eol => "\r\n"});
    $csv->combine(@fields);
    print $file $csv->string();
    for (my $i = 0; $i < scalar(@array); $i++) {    
        my @tmparray = ();
        foreach my $field (@fields) {
            push @tmparray, $array[$i]{$field};
        }
        $csv->combine(@tmparray);
        print $file $csv->string();
    }
}

sub read_csv {
    my ($filename) = @_;
    my $csv = Text::CSV_XS->new ({ binary => 1, eol => "\n" });
    open my $io, "<", $filename or die "$filename: $!";
    $csv->column_names($csv->getline($io));
    my @returnme = ();
    while (my $hr = $csv->getline_hr($io)) {
        push @returnme, {%$hr};
#	print $hr;
    }
    close $io;
    return @returnme;
}



1;
