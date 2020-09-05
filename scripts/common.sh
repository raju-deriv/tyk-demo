#!/bin/bash

# Contains functions useful for bootstrap scripts

# this array defines the hostnames that the bootstrap script will verify, and that the update-hosts script will use to modify /etc/hosts
declare -a tyk_demo_hostnames=("tyk-dashboard.localhost" "tyk-portal.localhost" "tyk-gateway.localhost" "tyk-gateway-2.localhost" "tyk-custom-domain.localhost" "tyk-worker-gateway.localhost" "acme-portal.localhost")

function bootstrap_progress {
  dot_count=$((dot_count+1))
  dots=$(printf "%-${dot_count}s" ".")
  echo -ne "  Bootstrapping $deployment ${dots// /.} \r"
}

function log_http_result {
  if [ "$1" = "200" ] || [ "$1" = "201" ]
  then 
    log_ok
  else 
    log_message "  ERROR: $1"
    flag_error
  fi
}

function log_json_result {
  status=$(echo $1 | jq -r '.Status')
  if [ "$status" = "OK" ] || [ "$status" = "Ok" ]
  then
    log_ok
  else
    log_message "  ERROR: $(echo $1 | jq -r '.Message')"
    flag_error
  fi
}

function flag_error {
  touch .bootstrap_error_occurred
}

function log_ok {
  log_message "  Ok"
}

function log_message {
  echo "$(date -u) $1" >> bootstrap.log
}

function log_start_deployment {
  log_message "START ▶ $deployment deployment bootstrap"
}

function log_end_deployment {
  log_message "END ▶ $deployment deployment bootstrap"
}

function set_docker_environment_value {
  setting_current_value=$(grep "$1" .env)
  setting_desired_value="$1=$2"
  if [ "$setting_current_value" == "" ]
  then
    # make sure .env file has an empty line before adding docker env var
    if [ ! -z "$(tail -c 1 .env)" ]
    then
      echo "" >> .env
    fi
    log_message "Adding Docker environment variable: $setting_desired_value"
    echo "$setting_desired_value" >> .env  
  else
    if [ "$setting_current_value" != "$setting_desired_value" ]
    then
      log_message "Updating Docker environment variable: $setting_desired_value"
      sed -i.bak 's/'"$setting_current_value"'/'"$setting_desired_value"'/g' .env
      rm .env.bak
    fi
  fi
}

function wait_for_response {
  url="$1"
  status=""
  desired_status="$2"
  header="$3"
  attempt_max="$4"
  attempt_count=0
  
  while [ "$status" != "$desired_status" ]
  do
    attempt_count=$((attempt_count+1))
    # header can be provided if auth is needed
    if [ "$header" != "" ]
    then
      status=$(curl -k -I -s -m5 $url -H "$header" 2>> bootstrap.log | head -n 1 | cut -d$' ' -f2)
    else
      status=$(curl -k -I -s -m5 $url $header 2>> bootstrap.log | head -n 1 | cut -d$' ' -f2)
    fi
    if [ "$status" != "$desired_status" ]
    then
      log_message "  Request unsuccessful: called '$url' wanted '$desired_status' but got '$status'."
      echo "att=$attempt_count max=$attempt_max"
      # if we reached max attempts, then exit with non-zero result
      if [ "$attempt_count" = "$attempt_max" ]
      then
        log_message "  Maximum retry count reached. Aborting."
        return 1
      else
        log_message "  Retrying..."
      fi
      sleep 2
    fi
    bootstrap_progress    
  done
  
  log_ok
  return 0
}

function hot_reload {
  gateway_host="$1"
  gateway_secret="$2"
  group="$3"
  result=""

  if [ "$group" = "group" ]
  then
    result=$(curl $1/tyk/reload/group?block=true -s \
      -H "x-tyk-authorization: $2" | jq -r '.status')
  else
    result=$(curl $1/tyk/reload?block=true -s \
      -H "x-tyk-authorization: $2" | jq -r '.status')
  fi

  return $result
}
