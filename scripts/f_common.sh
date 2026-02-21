#!/bin/sh

function_extract(){
  EXPORT_NAME=${1:-function_extract}
  FILE=${2:-scripts/common.sh}

  sed -n '/'"${EXPORT_NAME}"'(){/,/^}/p' "${FILE}"
}

function_list(){
  FILE=${1:-scripts/common.sh}
  sed -n '/(){/ {/^_/d; s/(){$//p}' "${FILE}" | sort -u
}

function_sort_file(){
  FILE=${1:-scripts/common.sh}

  # create new script
  sed -n '1,/(){/ {/(){/d; p}' "${FILE}" > tmp

  for function in $(function_list "${FILE}")
  do
    function_extract "$function" "${FILE}" >> tmp
    echo >> tmp
  done

  mv tmp "${FILE}"
}
