#!/bin/ash

##there's probably a better way to do this, but i dont know it...
MONTH_ENUM="Jan:01 Feb:02 Mar:03 Apr:04 May:05 Jun:06 Jul:07 Aug:08 Sept:09 Oct:10 Nov:11 Dec:12"

getMonth()
{
##$1 here is the short-string representation of a month
	for month in $MONTH_ENUM; do
		echo $month | grep $1 | awk -F ':' '{print $2}'
	done ;

}

##to sort dates properly, we need leading 0's on any single digit value
doPadding()
{
##$1 will be the int value to be padded with a leading 0, if needed
	if [ ${#1} == 1 ] ; then
		echo "0$1";
	else
		echo $1;
	fi
}

##this will return the date that is most recent
##the order the dates are put in matters very much, as
##the log and vim-cmd date formats differ. this function
##takes $1 from the log and $2 from vim-cmd, converts them
##into the standard comparison format, runs that through sort -rn,
##and finally returns the original ($1 or $2, raw from their sources)
##as the 'most recent event'
cmptimes()
{
	cmp_offtime_month="`echo $1 | awk '{print $1}'`" ##strip the month
	cmp_offtime_month=`getMonth $cmp_offtime_month` ##convert to int
	##the log files have more sane dates, requiring no padding effort
	##so all we had to do was convert string month to int, then rebuild
	##in the proper format
	cmp_offtime="`echo $1 | awk '{print $NF}'`-$cmp_offtime_month-`echo $1 | awk '{print $2" "$3}'`"
	##snapshot dates from vim-cmd are much more of a beating as a
	##number of different values arent padded, the below rectifies that
	cmp_shottime_date="`echo $2 | awk '{print $1}' | awk -F '/' '{print $3" "$1" "$2}'`"
	cmp_shottime_year=`echo $cmp_shottime_date | awk '{print $1}'`
	cmp_shottime_month=`doPadding \`echo $cmp_shottime_date | awk '{print $2}'\``
	cmp_shottime_day=`doPadding \`echo $cmp_shottime_date | awk '{print $3}'\``
	cmp_shottime_date="$cmp_shottime_year-$cmp_shottime_month-$cmp_shottime_day"
	cmp_shottime_time=`echo $2 | awk '{print $2}'`
	cmp_shottime_time_tmp=""
	##this is to avoid doing what i did with the date with the time
	##except in this case we wanted it done to all 3 values
	for part in `echo $cmp_shottime_time | awk -F ':' '{print $1" "$2" "$3}'`; do
		cmp_shottime_time_tmp="$cmp_shottime_time_tmp:`doPadding $part`";
	done ;
	cmp_shottime_time=`echo $cmp_shottime_time_tmp | awk -F ':' '{print $2":"$3":"$4}'`
	##final rebuild
	cmp_shottime="$cmp_shottime_date $cmp_shottime_time"
	##reverse sort on the strings to get the most recent
	most_recent=`echo -e "$cmp_shottime\n$cmp_offtime" | sort -nr | head -n 1`
	##print out the original value that was most recent
	if [ "$most_recent" == "$cmp_offtime" ]; then
		echo $1;
	else
		echo $2;
	fi

}

echo "Beginning run on `date`"
##let's grab all the VMids
vmids=`vim-cmd vmsvc/getallvms | grep -v 'Vmid'| awk '{print $1}'`

##main loop, check out each vm
for vmid in $vmids;

do

	name=`vim-cmd vmsvc/get.summary $vmid | grep "name =" | awk -F '"' '{print $2}'`
	echo "Assessing $name ($vmid)...";
	##we need this vm's logfile to get the powered off time's year

	logpath=`find /vmfs/ | grep "/$name/vmware.log"`
	##the logfile doesnt include year in the datestamp, so we get that
	##from the last modified timestamp. if that doesnt exist (eg, modified
	##this year, so instead it shows time), we grab the current year from
	##`date`
	year=`ls -l $logpath | awk '{print $8}' | grep -v ':'`
	if [ ! -n "$year" ] ; then
		year=`date | awk '{print $6}`;

	fi
	##grab the offtime from the log
	#the sed-bit below is from unix.com - 10133/remove last character line forum post
	offtime=`tail -n 1 $logpath | grep "has left the building" | awk -F "|" '{print $1}' |  sed "s/.\{9\}$//"`

	##if the vm was powered off
	if [ -n "$offtime" ] ; then
		echo "This VM was powered off on " $offtime $year;
		##grab the most recent snapshot's timestamp
		lastshot=`vim-cmd vmsvc/snapshot.get $vmid | tail -n 2 | grep 'Created' | awk -F ': ' '{print $2}'`
		##now we sort out if the snapshot or poweroff event was most recent

		last_event=`cmptimes "$offtime $year" "$lastshot"`

		echo "The last snapshot was take on $lastshot"
		##if we've turned the vm off since the last snapshot,
		##it means we ran it for some time without getting a backup
		##so we'll do it now
		if [ "$last_event" == "$offtime $year" ] ; then
			echo "VM's last snapshot was prior to powering off, taking a snapshot now";
			vim-cmd vmsvc/snapshot.create $vmid "Auto-shot on `date`" "Automated snapshot, host was off" false;
			echo "Snapshot complete"
		fi

	##the vm was on
	else
		echo "VM is still on, taking a snapshot";
		##if this is on, we definitely want a snapshot, with a side of memory
		vim-cmd vmsvc/snapshot.create $vmid "Auto-shot on `date`" "Automated snapshot with memory, host was on" true;
		echo "Snapshot complete"
	fi


	echo -ne "Done with $name.\n\n"
done;







