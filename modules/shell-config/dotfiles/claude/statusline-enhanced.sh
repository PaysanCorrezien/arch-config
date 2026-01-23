#!/bin/bash

# Read stdin JSON input without blocking if the pipe stays open
input="{}"
if [ ! -t 0 ]; then
    if IFS= read -r -t 0.05 first_line; then
        input="$first_line"
        while IFS= read -r -t 0.01 line; do
            input="${input}"$'\n'"$line"
        done
    fi
fi

# Extract basic session info
model=$(echo "$input" | jq -r '.model.display_name // empty' | sed -E 's/Claude ([0-9.]+) /\1 /; s/Claude //')
model_id=$(echo "$input" | jq -r '.model.id // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

if [ -z "$cwd" ] || [ "$cwd" = "null" ]; then
    cwd="$PWD"
fi
if [ -z "$model" ]; then
    model="Claude"
fi
if [ -z "$model_id" ]; then
    model_id="claude-sonnet-4-5-20250929"
fi

# Extract context window info
usage=$(echo "$input" | jq '.context_window.current_usage')
size=$(echo "$input" | jq '.context_window.context_window_size')

# Calculate context usage bar
if [ "$usage" != "null" ] && [ "$size" != "null" ] && [ "$size" -gt 0 ] 2>/dev/null; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    pct=$((current * 100 / size))
    filled=$((pct / 10))
    empty=$((10 - filled))
    bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}="; done
    for ((i=0; i<empty; i++)); do bar="${bar} "; done
    current_k=$((current / 1000))
    size_k=$((size / 1000))
else
    pct=0
    bar="          "
    current_k=0
    size_k=200
fi

# Get git branch with FIXED color escaping
git_branch=$(cd "$cwd" 2>/dev/null && git --no-optional-locks branch --show-current 2>/dev/null)
if [ -n "$git_branch" ]; then
    git_part=" | $(printf '\033[32m%s\033[0m' "$git_branch")"
else
    git_part=""
fi

# Get project name
project=$(basename "$cwd")

# Model pricing (per million tokens)
get_model_pricing() {
    local model_id="$1"
    case "$model_id" in
        claude-opus-4-5-20251101)
            echo "15.00 75.00 18.75 1.50" ;;
        claude-sonnet-4-5-20251101|claude-sonnet-4-5-20250929)
            echo "3.00 15.00 3.75 0.30" ;;
        claude-haiku-4-5-20251101|claude-haiku-4-5-20250110)
            echo "0.80 4.00 1.00 0.08" ;;
        *)
            echo "3.00 15.00 3.75 0.30" ;;
    esac
}

# Calculate cost for token counts
calculate_cost() {
    local model_id="$1"
    local input_tokens="$2"
    local output_tokens="$3"
    local cache_write="$4"
    local cache_read="$5"

    local pricing=($(get_model_pricing "$model_id"))
    local input_price="${pricing[0]}"
    local output_price="${pricing[1]}"
    local cache_write_price="${pricing[2]}"
    local cache_read_price="${pricing[3]}"

    # Use LC_NUMERIC=C to force period decimal separator
    LC_NUMERIC=C awk -v it="$input_tokens" -v ot="$output_tokens" \
        -v cw="$cache_write" -v cr="$cache_read" \
        -v ip="$input_price" -v op="$output_price" \
        -v cwp="$cache_write_price" -v crp="$cache_read_price" \
        'BEGIN {
            cost = (it * ip + ot * op + cw * cwp + cr * crp) / 1000000
            printf "%.4f", cost
        }'
}

# Get cost tracking info
get_cost_info() {
    local session_id="$1"
    local model_id="$2"
    local cache_file="$HOME/.claude/statusline-cost-cache.json"
    local cache_ttl=120

    # Find all JSONL files in ~/.claude/projects
    local projects_dir="$HOME/.claude/projects"

    if [ ! -d "$projects_dir" ]; then
        echo ""
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=""
    fi

    # Calculate session cost (current 5-hour window)
    local session_cost="0.0000"
    local session_input=0 session_output=0 session_cache_write=0 session_cache_read=0
    local window_start_time="" window_end_time=""

    # Find session JSONL file (search recursively, exclude subagents)
    local session_file=$(find "$projects_dir" -name "${session_id}.jsonl" -type f ! -path "*/subagents/*" 2>/dev/null | head -1)

    if [ -f "$session_file" ]; then
        # Read all entries and sum token usage (FIXED: correct field paths)
        while IFS= read -r line; do
            # Skip lines without usage data
            echo "$line" | jq -e '.message.usage // .usage' >/dev/null 2>&1 || continue

            # Try both .message.usage and .usage paths
            local msg_model=$(echo "$line" | jq -r '.message.model // .model // empty' 2>/dev/null)
            local msg_input=$(echo "$line" | jq -r '.message.usage.input_tokens // .usage.input_tokens // 0' 2>/dev/null)
            local msg_output=$(echo "$line" | jq -r '.message.usage.output_tokens // .usage.output_tokens // 0' 2>/dev/null)
            local msg_cache_write=$(echo "$line" | jq -r '.message.usage.cache_creation_input_tokens // .usage.cache_creation_input_tokens // 0' 2>/dev/null)
            local msg_cache_read=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // .usage.cache_read_input_tokens // 0' 2>/dev/null)
            local msg_time=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null)

            # Track time window
            if [ -z "$window_start_time" ] && [ -n "$msg_time" ]; then
                window_start_time="$msg_time"
            fi
            if [ -n "$msg_time" ]; then
                window_end_time="$msg_time"
            fi

            # Use message model or fall back to session model
            local current_model="${msg_model:-$model_id}"

            # Calculate cost for this message
            if [ "$msg_input" != "0" ] || [ "$msg_output" != "0" ]; then
                local msg_cost=$(calculate_cost "$current_model" "$msg_input" "$msg_output" "$msg_cache_write" "$msg_cache_read")
                session_cost=$(LC_NUMERIC=C awk -v a="$session_cost" -v b="$msg_cost" 'BEGIN {printf "%.4f", a + b}')

                session_input=$((session_input + msg_input))
                session_output=$((session_output + msg_output))
                session_cache_write=$((session_cache_write + msg_cache_write))
                session_cache_read=$((session_cache_read + msg_cache_read))
            fi
        done < "$session_file"
    fi

    # Calculate daily and monthly totals (cached to avoid heavy scans)
    local daily_cost="0.0000"
    local monthly_cost="0.0000"
    local current_day=$(date +%Y-%m-%d)
    local current_month=$(date +%Y-%m)
    local now_epoch=$(date +%s)
    local cache_ok=0

    if [ -f "$cache_file" ]; then
        local cache_day cache_month cache_updated cache_daily cache_monthly
        cache_day=$(jq -r '.day // empty' "$cache_file" 2>/dev/null)
        cache_month=$(jq -r '.month // empty' "$cache_file" 2>/dev/null)
        cache_updated=$(jq -r '.updated_at // 0' "$cache_file" 2>/dev/null)
        cache_daily=$(jq -r '.daily_cost // empty' "$cache_file" 2>/dev/null)
        cache_monthly=$(jq -r '.monthly_cost // empty' "$cache_file" 2>/dev/null)

        if [ "$cache_day" = "$current_day" ] && [ "$cache_month" = "$current_month" ]; then
            if [ $((now_epoch - cache_updated)) -lt "$cache_ttl" ]; then
                daily_cost="${cache_daily:-0.0000}"
                monthly_cost="${cache_monthly:-0.0000}"
                cache_ok=1
            fi
        fi
    fi

    if [ "$cache_ok" -ne 1 ]; then
        # Find all JSONL files modified this month (recursive, exclude subagents)
        while IFS= read -r jsonl_file; do
            [ -f "$jsonl_file" ] || continue

            # Check if file was modified this month
            local file_month=$(date -r "$jsonl_file" +%Y-%m 2>/dev/null)
            if [ "$file_month" = "$current_month" ]; then
                local file_totals
                file_totals=$(jq -r \
                    'select(.message.usage or .usage) |
                     [.timestamp,
                      (.message.model // .model // ""),
                      (.message.usage.input_tokens // .usage.input_tokens // 0),
                      (.message.usage.output_tokens // .usage.output_tokens // 0),
                      (.message.usage.cache_creation_input_tokens // .usage.cache_creation_input_tokens // 0),
                      (.message.usage.cache_read_input_tokens // .usage.cache_read_input_tokens // 0)] | @tsv' \
                    "$jsonl_file" 2>/dev/null | \
                    LC_NUMERIC=C awk -v day="$current_day" -v month="$current_month" -v default_model="$model_id" '
                    function prices(model, p,    ip, op, cwp, crp) {
                        if (model == "claude-opus-4-5-20251101") {
                            ip=15.00; op=75.00; cwp=18.75; crp=1.50
                        } else if (model == "claude-sonnet-4-5-20251101" || model == "claude-sonnet-4-5-20250929") {
                            ip=3.00; op=15.00; cwp=3.75; crp=0.30
                        } else if (model == "claude-haiku-4-5-20251101" || model == "claude-haiku-4-5-20250110") {
                            ip=0.80; op=4.00; cwp=1.00; crp=0.08
                        } else {
                            ip=3.00; op=15.00; cwp=3.75; crp=0.30
                        }
                        p["ip"]=ip; p["op"]=op; p["cwp"]=cwp; p["crp"]=crp
                    }
                    {
                        ts=$1; model=$2; it=$3; ot=$4; cw=$5; cr=$6
                        if (model == "") model = default_model
                        if (ts == "") next
                        msg_day = substr(ts,1,10)
                        msg_month = substr(ts,1,7)
                        prices(model, p)
                        cost = (it * p["ip"] + ot * p["op"] + cw * p["cwp"] + cr * p["crp"]) / 1000000
                        if (msg_month == month) monthly += cost
                        if (msg_day == day) daily += cost
                    }
                    END {printf "%.4f %.4f", daily, monthly}')

                if [ -n "$file_totals" ]; then
                    local file_daily file_monthly
                    file_daily=$(echo "$file_totals" | awk '{print $1}')
                    file_monthly=$(echo "$file_totals" | awk '{print $2}')
                    daily_cost=$(LC_NUMERIC=C awk -v a="$daily_cost" -v b="$file_daily" 'BEGIN {printf "%.4f", a + b}')
                    monthly_cost=$(LC_NUMERIC=C awk -v a="$monthly_cost" -v b="$file_monthly" 'BEGIN {printf "%.4f", a + b}')
                fi
            fi
        done < <(find "$projects_dir" -name "*.jsonl" -type f ! -path "*/subagents/*" 2>/dev/null)

        printf '{"updated_at":%s,"day":"%s","month":"%s","daily_cost":"%s","monthly_cost":"%s"}\n' \
            "$now_epoch" "$current_day" "$current_month" "$daily_cost" "$monthly_cost" > "$cache_file"
    fi

    # Calculate burn rate since last reset (total cost, not per hour)
    # Get reset info from API (simplified - may not work without proper OAuth)
    local reset_str=""
    local last_reset_str=""
    # Try to read from Claude Code's internal data if available
    local resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)

    if [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
        local reset_epoch=$(date -d "$resets_at" +%s 2>/dev/null || echo 0)
        local last_reset_epoch=$((reset_epoch - 18000))
        local time_to_reset=$(( (reset_epoch - now_epoch) / 60 ))

        if [ "$time_to_reset" -gt 0 ]; then
            local hours=$((time_to_reset / 60))
            local mins=$((time_to_reset % 60))
            local last_reset_time=$(date -d "@$last_reset_epoch" +%H:%M 2>/dev/null)
            last_reset_str=" | Last reset: ${last_reset_time}"
            reset_str=" | Reset in: ${hours}h${mins}m"
        fi
    fi

    # Format output
    local output=""

    # Session cost
    output=" | $(LC_NUMERIC=C printf '\033[33mS:\$%.4f\033[0m' "$session_cost")"

    # Daily and monthly cost
    output="${output} | $(LC_NUMERIC=C printf '\033[32mD:\$%.4f\033[0m' "$daily_cost")"
    output="${output} | $(LC_NUMERIC=C printf '\033[36mM:\$%.2f\033[0m' "$monthly_cost")"

    # Reset info
    output="${output}${last_reset_str}${reset_str}"

    echo "$output"
}

# Get cost tracking info
cost_info=$(get_cost_info "$session_id" "$model_id")

# Print status line
printf '\033[35m%s\033[0m \033[34m%s\033[0m%s | \033[36m[%s]\033[0m \033[33m%s%%\033[0m \033[35m%sk/%sk\033[0m%s\n' \
    "$model" "$project" "$git_part" "$bar" "$pct" "$current_k" "$size_k" "$cost_info"
