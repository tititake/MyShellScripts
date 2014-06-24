#!/bin/sh
# Author: RA <ravageralpha@gmail.com>
# Author: Chris Yu <chrisyu.gm@gmail.com>

USAGE(){
	echo "Usage:$(basename $0) [-eng] [-suf] [-togbk] [-toutf8] files..."
	echo "OPTIONS"
	echo "  -eng : download English subtitle, default is Chinese"
	echo "  -suf : add language suffix in subtitle file name"
	echo "  -togbk : try to convert file content from big5 to gbk with iconv"
	echo "  -toutf8 : try to convert file encoding to utf8 with enca"
}

[ $# -eq 0 ] && USAGE && exit 0

ERROR(){
	echo "Error:$@" >&2
	exit 1
}

[ -z `which openssl 2>/dev/null` ] || MD5='openssl md5'
[ -z `which md5 2>/dev/null` ] || MD5='md5'
[ -z `which md5sum 2>/dev/null` ] || MD5='md5sum'
[ -z "$MD5" ] && ERROR "No MD5 tools"
[ -z `which curl` ] && ERROR "No curl"
[ -z `which dd` ] && ERROR "No dd :)"
[ -z `which hexdump` ] && ERROR "No hexdump tools"
[ -z `which gunzip` ] && ERROR "No gunzip tools"

TMPDIR="/tmp"
[ -w "$TMPDIR" ] || ERROR  "Cannot write to temp dir $TMPDIR"

USERAGENT="SPlayer Build 1543"
LANGUAGE='chn'
TIMEOUT=5
CRAP="blueray|bluray|blu\-ray|remux|dvdrip|xvid|cd[0-9]|dts|vc1|vc\-1|hdtv|1080p|720p|1080i|x264|limited|ac3|hddvd|repack|@|dts\-hd"
CRAP_MISC="\[|\]|\.|\-|\#|\_|\=|\+|\<|\>|\,"
LANG_SUFFIX=""
TOGBK=0
TOUTF8=0

case `uname` in
	'Linux')
		SED_OPTS='-r -e';;
	'FreeBSD')
		SED_OPTS='-E -e'
		TIMEOUT=5000
        ;;
	'Darwin')
		# Mac Default , if you using GNU sed,edit it
		SED_OPTS='-E -e';;
	*)
		ERROR "unknown OS";;
esac

getFileSize(){
	# Fix Me
	[ -f "$1" ] && ls -nl "$1" | awk '{print $5}' || echo 0
}

getFileHash(){
	dd if="$file" bs=1 count=4096 skip=$1 2> /dev/null | $MD5 | head -c32
}

stripFileName(){
	echo "$(sed $SED_OPTS "s/"$CRAP"//g" -e "s/"$CRAP_MISC"/ /g")"
}

while [ -n "$1" ];do

	[ "$1" = '--help' ] && USAGE && exit 0

	if [ "$1" = '-eng' ]; then
		LANGUAGE='eng'
		shift
	fi

    if [ "$1" = '-suf' ]; then
        LANG_SUFFIX=".${LANGUAGE}"
        shift
    fi

	if [ "$1" = '-togbk' ]; then
		TOGBK=1
		shift
	fi

	if [ "$1" = '-toutf8' ]; then
		TOUTF8=1
		shift
	fi
	

	oriname="$1"
	file="`realpath \"$1\"`"
	[ ! -f "$file" ] && {
		echo "Cannot locate the target" >&2
		shift
		continue
	}

	filesize=$(getFileSize "$file")

	[ $filesize -le 8192 ] && ERROR "Serious?"

	filepath="E:\\$(dirname "$file" | sed 's/\//\\\\/g')" # it's just work
	filename="$(echo "$(dirname "$oriname")/$(basename "$oriname")" | sed 's/\.[^\.]*$//')"
	moviename="$(basename "$filename" | tr [A-Z] [a-z] | stripFileName | xargs -0)"

	bin="${TMPDIR}/$(basename "$filename").bin"

	first=4096
	second=$(($filesize/3*2))
	third=$(($filesize/3))
	fourth=$(($filesize-8192))

	filehash="$(getFileHash $first);$(getFileHash $second);$(getFileHash $third);$(getFileHash $fourth)"
	serverseq="$(( $RANDOM % 9 + 1 )) $(( $RANDOM % 9 + 1 )) $(( $RANDOM % 9 + 1 ))"
	for i in $serverseq
	do
		SERVER="http://splayer$i.shooter.cn/api/subapi.php"

		echo -n "Sending request to $SERVER..."
		
		#send request
		curl -s --connect-timeout $TIMEOUT -A "$USERAGENT" \
		-F "pathinfo=$filepath" -F "filehash=$filehash" -F "shortname=$moviename" -F "lang=$LANGUAGE" \
		-o "$bin" "$SERVER"

		# sometimes shooter.cn give zero fuck about your request , so try other
		# suck code
		if [ $? -eq 0 -a $(getFileSize "$bin") -gt 1024 ]; then
			echo "OK,Extracting"
			FLAG="DONE"
		else
			[ -f "$bin" ] && rm "$bin"
			echo "Fail" >&2
			FLAG="FAIL"
			sleep 2
			continue
		fi

		# get the subtitle filetype, srt ass ssa or smi
		matches=`grep -aboU -E "srt|ass|ssa|smi|sub" "$bin"`
		validmatches=""
		validcount=0
		for extgrep in $matches; do
			extpos=${extgrep%:*}
			extname="${extgrep##*:}"
			matched=1
			
			if [ $validcount -gt 0 ] ; then
				extflagpos=$(( $extpos - 4 ))
				extflag=`dd if="$bin" bs=1 count=8 skip=$extflagpos 2> /dev/null | hexdump -x |awk '{print $2$3}' 2> /dev/null`
				if [ "$extflag" = '00000300' ] || [ "$extflag" = '00000003' ] ;then
					subendpos=$(( $extpos - 21 ))
					validmatches="$validmatches$subendpos "
				else
					matched=0
				fi
			fi
			
			if [ $matched -eq 1 ] ; then
				subbeginpos=$(( $extpos + 7 ))
				validmatches="$validmatches$extname-$subbeginpos-"
				validcount=$(( $validcount + 1 ))
			fi
		done

		if [ $validcount == 0 ];then
			FLAG="FAIL"
			echo "No subtitle found, shouldn't happend!"
			break;
		else
			echo "Got $validcount subtitle(s)"
		fi

		subcount=0;
		for ii in $validmatches; do 
			extname=$(echo $ii | cut -f1 -d-)
			subbegin=$(echo $ii | cut -f2 -d-)
			subend=$(echo $ii | cut -f3 -d-)

			#echo "$extname , $subbegin, $subend .  "

			sub="${oriname%.*}${LANG_SUFFIX}.$extname"
			if [ $subcount -gt 0 ]; then
				sub="${oriname%.*}.${LANGUAGE}${subcount}.$extname"
			fi
		
			if [ "$subend" == "" ];then
				dd if="$bin" of="$sub" bs=1 skip=$subbegin 2> /dev/null
			else
				count=$(( $subend - $subbegin ))
				dd if="$bin" of="$sub" bs=1 skip=$subbegin count=$count 2> /dev/null
			fi

			# maybe not handle well , fix me
			gzip=`dd if="$sub" bs=1 count=2 2> /dev/null | hexdump -x | awk '{print $2}'`
			([ "$gzip" = '8b1f' ] || [ "$gzip" = '1f8b' ]) && {
				#echo "Got gzip here,unzipping..."
				mv "$sub" "${sub}.tgz"
				gunzip -c "${sub}.tgz" > "$sub" 2>/dev/null
				rm "${sub}.tgz"
			}

			subcount=$(( $subcount + 1 ))
			echo "#$subcount : [$(basename "$sub")]"

			# try to convert to gbk and utf-8
			if [ $TOGBK == 1 ] && [ ! -z `which iconv 2>/dev/null` ]; then
				iconv -f big5 -t gbk "$sub" -o "$sub".tmp_iconv 2>/dev/null \
				&& mv "$sub".tmp_iconv "$sub"
				rm "$sub".tmp_iconv 2>/dev/null
			fi
			if [ $TOUTF8 == 1 ] && [ ! -z `which enca 2>/dev/null` ]; then
				enca -L zh_CN -x utf-8 "$sub" 2>/dev/null
			fi
		done

		rm "$bin"
		break
	done

	[ "$FLAG" = "FAIL" ] && echo "Cannot find the subtitle:[$(basename "$file")]" >&2
	shift
done