#!/bin/bash
if [ $HOME = "/" ]; then
	bin_path="/.recycle_bin"
else
	bin_path="$HOME/.recycle_bin"
fi 
if [ ! -d ${bin_path} ];then
	mkdir "${bin_path}"
	touch "${bin_path}/.smartdelete"
fi
numargs=
raw_path=
declare -a files
num=0
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
function make_raw_path(){
	let numargs=$#-1
	raw_path=("$@")
}
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
function ask_for_file_selection(){
	read input
	while [[ $input == "" ]] || (( input > num )) || (( input < 1 )); do
		echo "Please pick a valid number"
		read input
	done
	num=$input
}
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
function minus_l(){
	if [ ! "$(ls -A ${bin_path})" ]; then
		echo "Recycle bin is empty!"
	else
		echo "Files inside the recycle bin are: "
		find ${bin_path}/* | sed "s/_[0-9]*$//g" | sed "s|^${bin_path}/||g" | uniq
	fi
}
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
find_proper_function "$@"
exit 0