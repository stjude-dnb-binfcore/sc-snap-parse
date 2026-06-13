#!/bin/bash

########################################################################
# Helper functions
########################################################################

get_yaml_value() {
  local key="$1"
  local value
  value=$(grep "^${key}:" "$config_file" | awk '{print $2}')
  value=${value//\"/}
  echo "$value"
}

get_yaml_value_or_default() {
  local key="$1"
  local default="$2"
  local value
  value=$(get_yaml_value "$key")
  if [[ -z "$value" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}

trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  echo "$s"
}