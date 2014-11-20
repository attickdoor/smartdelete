#!/bin/bash
# COMP4262 project - smartdelete
# by Ben Murphy, Kieran Blazier, and Evan
# check if user is root or not, and assign recycle bin path accordingly

if [ $HOME = "/" ]; then
	bin_path="/.recycle_bin"
else
	bin_path="$HOME/.recycle_bin"
fi 

# if recycle bin does not already exist, then we create it and the file that stores all path data

if [ ! -d ${bin_path} ];then
	mkdir "${bin_path}"
	touch "${bin_path}/.smartdelete"
fi

# mandatory global declarations

numargs=
raw_path=
declare -a files
num=0

# what we do with the passed in args depends on what option was passed
# if it's -d, we need to locate all files with the CURRENT directory as a reference point
# if it's -r or -o, we need to locate all files from the recycle bin instead

function find_proper_function(){
	case $1 in
		\-d)
			shift
			make_raw_path $@
			expand_args d
			minus_d 
			;;
		\-r)
			shift
			make_raw_path "$@"
			expand_args r
			restore_operations r
			;;
		\-o)
			shift
			make_raw_path "$@"
			expand_args r
			restore_operations o
			;;
		\-c)
			minus_c
			;;
		\-l)
			minus_l
			;;
		*)
			make_raw_path $@
			expand_args d
			minus_d
			;;
	esac
}
# small, but gets used multiple times. numargs is -1 because we start seq from 0
# real programming is too deeply infused in my blood to make it start anywhere else

function make_raw_path(){
	let numargs=$#-1
	raw_path=("$@")
}

# if doing a [r]estoration operation, we must expand args from the recycle bin path
# this comes with a little extra work because all files in the recycle bin have _[0-9]* appended to the filename
# so we have to include that in our searches
# if it's a deletion, then we can just expand globs from the current directory

function expand_args(){
	if [ $1 = 'r' ]; then
		for i in `seq 0 1 $numargs`; do
			stuff=${bin_path}/${raw_path[$i]}
			find ${stuff}_[0-9]* -maxdepth 1 >> .tmp
		done
		readarray raw_path < .tmp
		rm -f .tmp
		let numargs=${#raw_path[*]}-1
		for i in `seq 0 1 $numargs`; do
			readlink -f ${raw_path[$i]} | sed "s/\//\n/g" | tail -1 >> .tmp
		done
		files=(`sed "s/_[0-9]*$//g" .tmp | sed "s/\n/ /g" | uniq`)
		rm -f .tmp
	else
		for i in `seq 0 1 $numargs`; do
			if [ -f ${raw_path[$i]} ]; then
				find ${raw_path[$i]} -maxdepth 1 >> .tmp
			else
				echo "File ${raw_path[$i]} does not exist."
			fi
		done
		if [ -f .tmp ]; then
			readarray raw_path < .tmp
		else
			exit 0
		fi
		rm -f .tmp
		let numargs=${#raw_path[*]}-1
		for i in `seq 0 1 $numargs`; do
			files[$i]=`readlink -f ${raw_path[$i]} | sed "s/\//\n/g" | tail -1`
		done	
	fi
}

# the easiest option by far
# we simply grab each matching filename existing in this directory
# begin by appending _1 to it
# if that filename with _1 already exists in recycle bin, we go to _2, etc
# we then write the path that the file came from with its matching appended number to a hidden reference file
# which is used for file restoration purposes

function minus_d(){
	for i in `seq 0 1 $numargs`; do
		fname=${files[$i]%$'\n'}
		let appendnum=1
		while [ -f ${bin_path}/${fname}_${appendnum} ]; do
			let appendnum=$appendnum+1
		done
		mv ${raw_path[$i]} ${bin_path}/${fname}_$appendnum
		echo "File ${fname} successfully moved to recycle bin." | sed "s/\\n/ /g"
		echo "`readlink -f ${raw_path[$i]}`_${appendnum}" >> ${bin_path}/.smartdelete
	done
}

# this operation is exactly the same for -o and -r, with one exception
# if we pass "r" to this, indicating -r, then the restore path is the current directory
# if it's anything else (we only ever pass r or o), then we grep the smartdelete for the line ENDING in the chosen path + filename + append number
# and that becomes the directory we restore to

function restore_operations(){
	let numargs=${#files[*]}-1
	for i in `seq 0 1 ${numargs}`; do
		filename=${files[$i]}
		if [ -f ${bin_path}/${filename}_2 ]; then
			print_dupes $filename
			ask_for_file_selection
		elif [ -f ${bin_path}/${filename}_1 ]; then
			num=1
		else
		       	echo "File ${filename} does not exist in the recycle bin." >&2
			exit 1
		fi
		if [ $1 = 'r' ]; then
			restore_path=`pwd`
		else
			restore_path=`grep -e "${files[$i]}_${num}$" ${bin_path}/.smartdelete | sed "s/${files[$i]}_${num}$//g"`
		fi
		if [ -f ${restore_path}/${files[$i]} ]; then
			echo "File ${files[$i]} already exists, appending _restored to end of file..."
			while [ -f ${restore_path}/${filename} ]; do
				filename=${filename}_restored
			done
		fi
		move_text_values_down ${files[$i]} $num
		mv ${bin_path}/${files[$i]}_${num} ${restore_path}/$filename
		echo "File ${filename} successfully restored to ${restore_path}."
		move_file_values_down ${files[$i]} $num
	done
}

# prints all possibilities if multiple files exist
# reducing num by one at the end because we need to maintain that number later

function print_dupes(){
	let num=1
	echo "Multiple files exist. Please choose the number next to the correct file."
	while [ -f ${bin_path}/$1_$num ]; do
		echo -n "$num) $1 from `grep -e "${1}_${num}$" ${bin_path}/.smartdelete | sed "s/${1}_${num}$//g"`,"
	        echo " recycled on `stat -c%y "${bin_path}/${1}_${num}" | cut -d '.' -f 1`"
		let num=$num+1
	done
	let num=num-1
}

# nothing really to write about this
# we reduced num by one in the above method so it can be an easy reference for the maximum number

function ask_for_file_selection(){
	read input
	while [[ $input == "" ]] || (( input > num )) || (( input < 1 )); do
		echo "Please pick a valid number"
		read input
	done
	num=$input
}

# args passed: file name (without path or append number), append number chosen by user (or 1 if no dupes)
# loop through until we find the highest appended number for the file name
# grep the inverse of the file to be restored, effectively removing that line from .smartdelete
# grep the line of the file matching the highest number, sed the appended number so that it matches the restored file's number
# rewrite to file, and then grep the inverse of the highest number to remove it
# write back from .tmp to .smartdelete

function move_text_values_down(){
	file=$1
	let k=$2
	let l=$k+1
	while [ -f ${bin_path}/${file}_${l} ]; do
		let l=$l+1
	done
	let l=$l-1
	grep -v -e "\/${file}_${k}$" ${bin_path}/.smartdelete >> ${bin_path}/.tmp
	grep -e "\/${file}_${l}$" ${bin_path}/.tmp | sed "s/${file}_${l}/${file}_${k}/g" >> ${bin_path}/.tmp
	grep -v -e "\/${file}_${l}$" ${bin_path}/.tmp > ${bin_path}/.smartdelete
	rm -f ${bin_path}/.tmp
}


# args passed: file name (without path or append number), append number chosen by user (or 1 if no dupes)
# same incrementation as above, but dealing with files, so no grepping
# if there is no other append number file, then we do nothing, hence the conditional

function move_file_values_down(){
	let i=$2
	let j=$i+1
	while [ -f ${bin_path}/${1}_${j} ]; do
		let j=${j}+1
	done
	let j=${j}-1
	if [ -f ${bin_path}/${1}_${j} ]; then
		cp -p ${bin_path}/${1}_${j} ${bin_path}/${1}_${i}
		rm -f ${bin_path}/${1}_${j}
	fi
}

# icing on the cake, not required or extra credit
# lists all files, stripped of the append number and passed through uniq, for easy reference

function minus_l(){
	if [ ! "$(ls -A ${bin_path})" ]; then
		echo "Recycle bin is empty!"
	else
		echo "Files inside the recycle bin are: "
		find ${bin_path}/* | sed "s/_[0-9]*$//g" | sed "s|^${bin_path}/||g" | uniq
		find ${bin_path}/.* -maxdepth 0 | sed "s/_[0-9]*$//g" | sed "s|^${bin_path}/||g" | uniq
	fi
}

# more icing on the cake
# completely empties the recycle bin iff user enters "y" or "yes"

function minus_c(){
	if [ ! "$(ls -A ${bin_path})" ]; then
		echo "Recycle bin is already empty."
	else
		echo -n "Are you SURE you want to empty the recycle bin? "
		input=""
		while [[ $input == "" ]]; do
			read input
		done
		if [[ $input == "yes" ]] || [[ $input == "y" ]]; then
			rm -f ${bin_path}/*
			rm -f ${bin_path}/.smartdelete
			touch ${bin_path}/.smartdelete
			echo "Recycle bin successfully emptied!"
		else
			echo "Recycle bin not emptied."
		fi
	fi
}

# what a long main()

find_proper_function "$@"
exit 0
