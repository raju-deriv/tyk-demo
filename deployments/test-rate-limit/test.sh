#!/bin/bash

source scripts/common.sh

readonly dashboard_base_url="http://tyk-dashboard.localhost:$(jq -r '.listen_port' deployments/tyk/volumes/tyk-dashboard/tyk_analytics.conf)"
readonly gateway_base_url="$(get_context_data "1" "gateway" "1" "base-url")"
readonly gateway_api_credentials=$(cat deployments/tyk/volumes/tyk-gateway/tyk.conf | jq -r .secret)
readonly TYK_DASHBOARD_API_KEY="$(cat .context-data/1-dashboard-user-1-api-key)"
readonly TEST_SUMMARY_PATH=".context-data/rl-test-output-summary"
readonly TEST_DETAIL_PATH=".context-data/rl-test-output-detail"
export_analytics=false

while getopts ":e" opt; do
  case $opt in
    e) export_analytics=true
      ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1
      ;;
  esac
done

# Function to convert timestamp to milliseconds since epoch
timestamp_to_epoch_ms() {
    local timestamp="$1"
    local epoch="$(date -jf "%Y-%m-%dT%H:%M:%S" "$timestamp" "+%s" 2>/dev/null)"
    # Use parameter expansion with a character class to capture digits only
    milliseconds=${timestamp##*.}  # Double ## removes everything before the last dot
    milliseconds=${milliseconds%[!0-9]}  # Remove everything except digits from the end
    # Add trailing 0 padding to ms values that only have 1 or 2 digits
    case ${#milliseconds} in
        1) milliseconds="${milliseconds}00" ;;
        2) milliseconds="${milliseconds}0" ;;
        *) ;;
    esac
    echo "$epoch$milliseconds"
}

append_to_test_summary() {
    sed -i '' "$ s/$/ $1/" $TEST_SUMMARY_PATH
}

append_to_test_detail() {
    sed -i '' "$ s/$/ $1/" $TEST_DETAIL_PATH
}

# Analyses analytics data to validate whether rate limits were correctly enforced
analyse_rate_limit_enforcement() {
    local analytics_data="$1"
    local rate_limit="$2"
    local rate_period="$3"
    local test_plan_name="$4"
    local analytics_record_count=$(jq '[.data[]] | length' <<< "$analytics_data")
    local rate_limit_window_ms=$((rate_period * 1000))
    local code_429_count=0
    local code_200_count=0
    local code_other_count=0
    local rl_enforce_ok_count=0
    local rl_enforce_error_count=0
    local result=0

    append_to_test_summary $analytics_record_count

    echo -e "Analysing $analytics_record_count analytics records using rate limit window of ${rate_limit_window_ms}ms"
    
    for (( i=0; i<$analytics_record_count; i++ )); do
        printf "\rCompleted: %d/%d" "$((i+1))" "$analytics_record_count"
        local current=$(jq -r ".data[$i]" <<< "$analytics_data")
        local response_code=$(jq -r '.ResponseCode' <<< "$current")

        # Move to next record if not a 429
        case $response_code in
            200)  
                code_200_count=$((code_200_count+1))
                continue  
                ;;
            429)  
                code_429_count=$((code_429_count+1)) 
                ;;
            *)  
                code_other_count=$((code_other_count+1))
                continue 
                ;;  
        esac 

        echo "$test_plan_name" >> $TEST_DETAIL_PATH
        local success=true
        local current_timestamp=$(jq -r '.TimeStamp' <<< "$current")
        local next_index=$((i + rate_limit))

        # Check if next index is within array bounds
        if [ "$next_index" -ge "$analytics_record_count" ]; then
            next_timestamp="-"
            diff_ms="-"
            rl_error=$((rl_error+1))
            success=false
        else
            local next=$(jq -r ".data[$next_index]" <<< "$analytics_data")
            local next_timestamp=$(jq -r '.TimeStamp' <<< "$next")

            local current_epoch=$(timestamp_to_epoch_ms "$current_timestamp")
            local next_epoch=$(timestamp_to_epoch_ms "$next_timestamp")

            local diff_ms=$((current_epoch - next_epoch))
            success=$(( diff_ms <= rate_limit_window_ms ))
        fi

        append_to_test_detail "$code_429_count $i $next_index $current_timestamp $next_timestamp $diff_ms $rate_limit_window_ms"

        if [[ $success -eq 1 ]]; then
            rl_enforce_ok_count=$((rl_enforce_ok_count+1))
            append_to_test_detail "pass"
        else 
            rl_enforce_error_count=$((rl_enforce_error_count+1))
            append_to_test_detail "fail"
            result=1
        fi
    done
    printf "\n" # new line needed after progress meter completed
    
    append_to_test_summary "$code_200_count $code_429_count $code_other_count $rl_enforce_ok_count $rl_enforce_error_count"

    case $code_429_count in
        0)  
            echo "Rate limit not triggered" 
            append_to_test_summary "-"
            ;;
        *)  
            local rl_success=$(echo "scale=2; ($rl_enforce_ok_count / $code_429_count) * 100" | bc)
            echo "Rate limit $rl_success% successfully enforced" 
            append_to_test_summary "$rl_success"
            ;;
    esac

    return $result
}

generate_requests() {
    local clients="$1"
    local requests_per_second="$2"
    local requests_total="$3"
    local target_url="$4"
    local api_key="$5"
    hey -c "$clients" -q "$requests_per_second" -n "$requests_total" -H "Authorization: $api_key" "$target_url" 1> /dev/null
}

get_key_test_data() {
    local key_path="$1"
    echo "$(jq '.access_rights[] | { rate: .limit.rate, per: .limit.per }' $keypath)"
}

get_analytics_data() {
    local api_id="$1"
    local from_epoch="$2"
    local request_count="$3"
    local url="$dashboard_base_url/api/logs/?start=$from_epoch&p=-1&api=$api_id"
    local data=""
    local done=false
    
    while ! $done; do
        data=$(curl -s -H "Authorization: $TYK_DASHBOARD_API_KEY" $url)
        analytics_count=$(jq '.data | length' <<< "$data")
        
        # check that there is equivalent amount of analytics records to API requests sent
        if [ $analytics_count -eq $request_count ]; then
            done=true
        else
            # pause, to allow time for analytics data to be processed
            sleep 1
        fi
    done

    echo "$data"
}

# clear the test output files
> $TEST_SUMMARY_PATH
> $TEST_DETAIL_PATH

for test_plan_path in deployments/test-rate-limit/data/script/test-plans/*; do
    test_plan_file_name=$(basename "${test_plan_path%.*}")
    text_plan_enabled=$(jq -r '.enabled' $test_plan_path)

    if [ "$text_plan_enabled" != "true" ]; then
        echo -e "\nSkipping test plan \"$test_plan_file_name\": not enabled"
        continue
    fi

    test_data_source=$(jq -r '.dataSource' $test_plan_path)
    key_file_path=$(jq -r '.key.filePath' $test_plan_path)
    key_rate=$(jq '.access_rights[] | .limit.rate' $key_file_path)
    key_rate_period=$(jq '.access_rights[] | .limit.per' $key_file_path)
    analytics_data=""

    echo "$test_plan_file_name" >> $TEST_SUMMARY_PATH
    echo -e "\nRunning test plan \"$test_plan_file_name\" using \"$test_data_source\" data source"

    case $test_data_source in
        "requests")
            target_authorization=$(jq -r '.requests.target.authorization' $test_plan_path)
            target_url=$(jq -r '.requests.target.url' $test_plan_path)
            target_api_id=$(jq -r '.requests.target.apiId' $test_plan_path)
            load_clients=$(jq '.requests.load.clients' $test_plan_path)
            load_rate=$(jq '.requests.load.rate' $test_plan_path)
            load_total=$(jq '.requests.load.total' $test_plan_path)
            current_time=$(date +%s)
            create_bearer_token $key_file_path $gateway_api_credentials
            echo "Generating $load_total requests @ ${load_rate}rps at $target_url"
            generate_requests $load_clients $load_rate $load_total $target_url $target_authorization
            delete_bearer_token_dash $target_authorization $target_api_id $TYK_DASHBOARD_API_KEY
            analytics_data=$(get_analytics_data $target_api_id $current_time $load_total)
            ;;
        "file")
            analytics_data_path=$(jq '.file.analyticsDataPath' -r $test_plan_path)
            if [ ! -f $analytics_data_path ]; then
                echo "ERROR: Analytics data file does not exist: $analytics_data_path"
                exit 1
            fi
            echo "Loading analytics data from $analytics_data_path"
            analytics_data=$(cat $analytics_data_path)
            ;;
        *) 
            echo "ERROR: unknown data source: $test_data_source"
            exit 1 
            ;;
    esac

    # save analytics data to file
    # echo "$analytics_data" > .context-data/rl-analytics-data-$test_plan_file_name.csv
#START
    log_message "START PARSE $(date)"
    parsed_data_file_path=".context-data/rl-parsed-data-$test_plan_file_name.csv"
    jq -r '.data[] | [.ResponseCode, .TimeStamp] | join(" ")' <<< "$analytics_data" > $parsed_data_file_path
    log_message "END PARSE $(date)"

    log_message "START ANALYSIS $(date)"
    # log_message "kr:$key_rate kp:$key_per"
    awk -v test_plan_file_name="$test_plan_file_name" \
        -v rate_limit="$key_rate" \
        -v rate_limit_period="$key_rate_period" \
        -f deployments/test-rate-limit/data/script/rl-analysis-template.awk $parsed_data_file_path >> $TEST_DETAIL_PATH
    log_message "END ANALYSIS $(date)"

#END

    # append_to_test_detail "$code_429_count $i $next_index $current_timestamp $next_timestamp $diff_ms $rate_limit_window_ms"

    if [ "$export_analytics" == "true" ]; then
        echo "$analytics_data" > .context-data/rl-test-analytics-export-$test_plan_file_name.json
    fi

    # analyse_rate_limit_enforcement "$analytics_data" $key_rate $key_rate_period $test_plan_file_name
    # if [ $? -eq 0 ]; then
    #     append_to_test_summary "pass"
    # else
    #     append_to_test_summary "fail"
    # fi
done

echo -e "\nTest plans complete"

echo -e "\nRate Limit Analysis"
awk -f deployments/test-rate-limit/data/script/test-output-detail-template.awk $TEST_DETAIL_PATH

echo -e "\nSummary Results"
awk -f deployments/test-rate-limit/data/script/test-output-summary-template.awk $TEST_SUMMARY_PATH
