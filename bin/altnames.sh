#!/bin/bash 

FN=$1 

#Define the string value
text=$(openssl x509 -text -noout -in "$FN" | grep DNS)

# Set space as the delimiter
IFS=', DNS:'

#Read the split words into an array based on space delimiter
read -a names <<< "$text"

# Print each value of the array by using the loop
for host in "${names[@]}";
do
    if [[ -n "$host" ]]
    then
        echo $host
    fi
done
