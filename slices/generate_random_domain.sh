#!/bin/bash

#
# A Bash function that generates a random domain name.
# It combines a randomly generated string with a TLD from a predefined list.
# Domain length does not incl TLDs
#
# Usage:
#   generate_random_domain [min_length] [max_length]
#
# Arguments:
#   min_length: Optional. The minimum length of the domain name. Defaults to 6.
#   max_length: Optional. The maximum length of the domain name. Defaults to 12.
#

generate_random_domain() {
  # Set default lengths, and override them with function arguments if provided.
  local min_len=${1:-6}
  local max_len=${2:-12}

  # --- Input Validation ---
  # If the min length is greater than the max, swap them.
  if (( min_len > max_len )); then
    local temp=$min_len
    min_len=$max_len
    max_len=$temp
  fi

  # Define a list of common Top-Level Domains (TLDs). Feel free to add more.
  local tlds=( "com" "net" "org" "io" "dev" "ai" "co" "app" "xyz" "tech" "info" "me" )

  # Determine a random length for the domain name within the specified range.
  local length_range=$(( max_len - min_len + 1 ))
  local name_length=$(( RANDOM % length_range + min_len ))

  # Generate the random part of the domain name.
  # - /dev/urandom provides a stream of random bytes.
  # - `tr -dc 'a-z0-9'` deletes all characters except for lowercase letters and numbers.
  # - `head -c` takes the specified number of characters from the stream.
  # - LC_ALL=C is set for compatibility and to ensure tr works with bytes.
  local domain_name
  domain_name=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c "$name_length")

  # Pick a random TLD from the tlds array.
  # - ${#tlds[@]} gets the total number of elements in the array.
  # - RANDOM % ... gives a random number from 0 to (count - 1), which is a valid index.
  local chosen_tld=${tlds[$(( RANDOM % ${#tlds[@]} ))]}

  # Combine the name and the TLD and print the final result.
  echo "${domain_name}.${chosen_tld}"
}

# --- Main execution part to demonstrate the function ---

echo "6-12 chars (default) random domain:"
# Call the function without arguments
generate_random_domain

echo
echo "15-20 chars random domain:"
# Call the function with min and max length arguments
generate_random_domain 15 20

echo
echo "3-5 chars random domains *5:"
for i in {1..5}; do
  generate_random_domain 3 5
done

