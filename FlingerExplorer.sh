#!/usr/bin/env bash
set -o pipefail

readonly FE_VERSION="3.6.0-Stable"
readonly FE_TARGET="Android 11-16"
readonly FE_LOGDIR="/data/local/tmp/flinger_explorer"
readonly FE_BACKUP="${FE_LOGDIR}/backup"
readonly FE_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    FE_COLOR_SUPPORT=1
    C_R=$'\033[0;31m'
    C_G=$'\033[0;32m'
    C_Y=$'\033[1;33m'
    C_B=$'\033[0;34m'
    C_C=$'\033[0;36m'
    C_M=$'\033[0;35m'
    C_W=$'\033[1;37m'
    C_O=$'\033[38;5;208m'
    C_P=$'\033[38;5;165m'
    C_T=$'\033[38;5;51m'
    C_GR=$'\033[38;5;245m'
    C_BOLD=$'\033[1m'
    C_N=$'\033[0m'
else
    FE_COLOR_SUPPORT=0
    C_R=""
    C_G=""
    C_Y=""
    C_B=""
    C_C=""
    C_M=""
    C_W=""
    C_O=""
    C_P=""
    C_T=""
    C_GR=""
    C_BOLD=""
    C_N=""
fi

declare -g FE_HAS_ROOT=0
declare -g FE_HAS_MAGISK=0
declare -g FE_HAS_RESETROP=0
declare -g FE_SELINUX="Unknown"
declare -g FE_CAN_WRITE=0
declare -g FE_ANDROID_SDK=0
declare -g FE_ROOT_METHOD=""

fe_safe_exec() {
    local cmd="$1"
    local output=""
    local ret=0
    
    if [[ ${FE_HAS_ROOT} -eq 1 && -n "${FE_ROOT_METHOD}" ]]; then
        output="$(${FE_ROOT_METHOD} "${cmd}" 2>/dev/null)" || ret=$?
    else
        output="$(eval "${cmd}" 2>/dev/null)" || ret=$?
    fi
    
    printf "%s" "${output}"
    return ${ret}
}

fe_safe_exec_noerr() {
    local cmd="$1"
    if [[ ${FE_HAS_ROOT} -eq 1 && -n "${FE_ROOT_METHOD}" ]]; then
        ${FE_ROOT_METHOD} "${cmd}" >/dev/null 2>&1 || true
    else
        eval "${cmd}" >/dev/null 2>&1 || true
    fi
}

fe_detect_root() {
    FE_HAS_ROOT=0
    FE_CAN_WRITE=0
    FE_ROOT_METHOD=""
    
    local test_cmd='id'
    local result=""
    
    if command -v su >/dev/null 2>&1; then
        result="$(su -c "${test_cmd}" 2>/dev/null || true)"
        if printf "%s" "${result}" | grep -q 'uid=0'; then
            FE_HAS_ROOT=1
            FE_ROOT_METHOD="su -c"
        fi
    fi
    
    if [[ ${FE_HAS_ROOT} -eq 0 ]] && command -v magisk >/dev/null 2>&1; then
        result="$(magisk su -c "${test_cmd}" 2>/dev/null || true)"
        if printf "%s" "${result}" | grep -q 'uid=0'; then
            FE_HAS_ROOT=1
            FE_ROOT_METHOD="magisk su -c"
            FE_HAS_MAGISK=1
        fi
    fi
    
    if [[ ${FE_HAS_ROOT} -eq 1 ]]; then
        FE_CAN_WRITE=1
        if fe_safe_exec "command -v resetprop" | grep -q "resetprop"; then
            FE_HAS_RESETROP=1
        fi
    fi
    
    FE_SELINUX="$(getenforce 2>/dev/null || echo "Unknown")"
    FE_ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null || echo 0)"
    
    mkdir -p "${FE_LOGDIR}" "${FE_BACKUP}" >/dev/null 2>&1 || true
}

fe_print_header() {
    printf "\n"
    printf "${C_T}${C_BOLD}FlingerExplorer${C_N} ${C_GR}v${FE_VERSION}${C_N}\n"
    printf "${C_GR}Android system services research toolkit${C_N}\n"
    printf "${C_GR}Target platform: ${FE_TARGET}${C_N}\n"
    printf "\n"
    
    printf "${C_W}Device model:${C_N} %s\n" "$(getprop ro.product.model 2>/dev/null || echo "Unknown")"
    printf "${C_W}Android SDK:${C_N} %s\n" "${FE_ANDROID_SDK}"
    printf "${C_W}Build fingerprint:${C_N} %s\n" "$(getprop ro.build.fingerprint 2>/dev/null | head -c 60 || echo "Unknown")"
    printf "\n"
    
    printf "${C_W}Root access:${C_N} "
    if [[ ${FE_HAS_ROOT} -eq 1 ]]; then
        printf "${C_G}Available - full access mode${C_N}"
        [[ ${FE_HAS_MAGISK} -eq 1 ]] && printf " ${C_M}[Magisk]${C_N}"
        [[ ${FE_HAS_RESETROP} -eq 1 ]] && printf " ${C_O}[resetprop]${C_N}"
    else
        printf "${C_Y}Not detected - read-only mode${C_N}"
    fi
    printf "\n"
    
    printf "${C_W}SELinux status:${C_N} %s\n" "${FE_SELINUX}"
    printf "${C_W}Log directory:${C_N} %s\n" "${FE_LOGDIR}"
    printf "${C_W}Color support:${C_N} "
    if [[ ${FE_COLOR_SUPPORT} -eq 1 ]]; then
        printf "${C_G}Enabled${C_N}\n"
    else
        printf "${C_GR}Disabled${C_N}\n"
    fi
    printf "\n"
}

fe_check_write() {
    if [[ ${FE_CAN_WRITE} -eq 0 ]]; then
        printf "\n"
        printf "${C_R}Operation denied${C_N}\n"
        printf "${C_Y}Root access is required for write and modify operations.${C_N}\n"
        printf "${C_GR}You are in read-only mode. Only viewing and analysis functions are available.${C_N}\n"
        return 1
    fi
    return 0
}

fe_backup_prop() {
    local prop="$1"
    local backup_file="${FE_BACKUP}/props_${FE_TIMESTAMP}.bak"
    local current_val
    current_val="$(fe_safe_exec "getprop '${prop}'")"
    printf "%s=%s\n" "${prop}" "${current_val}" >> "${backup_file}" 2>/dev/null || true
}

fe_set_prop_safe() {
    local prop="$1"
    local value="$2"
    local risk="${3:-LOW}"
    
    if ! fe_check_write; then
        return 1
    fi
    
    fe_backup_prop "${prop}"
    
    printf "  ${C_Y}[${risk}]${C_N} Setting ${C_W}%s${C_N} = ${C_O}%s${C_N}\n" "${prop}" "${value}"
    
    if [[ "${prop}" == ro.* ]]; then
        if [[ ${FE_HAS_RESETROP} -eq 1 ]]; then
            fe_safe_exec_noerr "resetprop '${prop}' '${value}'"
        else
            printf "  ${C_R}Error: Cannot set ro.* property without resetprop.${C_N}\n"
            return 1
        fi
    else
        fe_safe_exec_noerr "setprop '${prop}' '${value}'"
    fi
    
    local verify
    verify="$(fe_safe_exec "getprop '${prop}'")"
    if [[ "${verify}" == "${value}" ]]; then
        printf "  ${C_G}Success: Property applied and verified.${C_N}\n"
    else
        printf "  ${C_R}Warning: Property may not have applied correctly.${C_N}\n"
        printf "  ${C_GR}Current value reads as: '%s'${C_N}\n" "${verify}"
        return 1
    fi
    return 0
}

fe_print_title() {
    local title="$1"
    local color="${2:-$C_C}"
    printf "\n"
    printf "${color}${C_BOLD}%s${C_N}\n" "${title}"
    printf "${color}%s${C_N}\n" "$(printf "%s" "${title}" | sed 's/./-/g')"
}

fe_print_subtitle() {
    local title="$1"
    printf "\n"
    printf "${C_M}%s${C_N}\n" "${title}"
    printf "${C_GR}%s${C_N}\n" "$(printf "%s" "${title}" | sed 's/./~/g')"
}

fe_pause() {
    printf "\n"
    read -rp "${C_GR}Press Enter to continue...${C_N} " _
}

fe_array_len() {
    local -n arr=$1
    printf "%d" "${#arr[@]}"
}

fe_array_get() {
    local -n arr=$1
    local idx=$2
    printf "%s" "${arr[${idx}]:-}"
}

fe_collect_sf() {
    local outfile="${FE_LOGDIR}/surfaceflinger_${FE_TIMESTAMP}.log"
    printf "${C_B}Collecting SurfaceFlinger state...${C_N}\n"
    
    {
        printf "SurfaceFlinger Explorer Report\n"
        printf "Generated: %s\n" "$(date)"
        printf "Device: %s\n" "$(getprop ro.product.model 2>/dev/null)"
        printf "Android SDK: %s\n" "${FE_ANDROID_SDK}"
        printf "\n"
        printf "Full dumpsys\n"
        fe_safe_exec "dumpsys SurfaceFlinger"
        printf "\n"
        printf "Latency statistics\n"
        fe_safe_exec "dumpsys SurfaceFlinger --latency"
        printf "\n"
        printf "Frame timestats\n"
        fe_safe_exec "dumpsys SurfaceFlinger timestats"
        printf "\n"
        printf "VSYNC information\n"
        fe_safe_exec "dumpsys SurfaceFlinger --vsync"
        printf "\n"
        printf "Layer list\n"
        fe_safe_exec "dumpsys SurfaceFlinger --list"
        printf "\n"
        printf "Relevant properties\n"
        fe_safe_exec "getprop | grep -E '(debug.sf|debug.egl|debug.renderengine|debug.composition|hwui|ro.surface_flinger|sf\\.|graphics\\.display|persist\\.sys\\.sf)'"
        printf "\n"
        printf "Process information\n"
        fe_safe_exec "ps -A | grep -i surfaceflinger"
    } > "${outfile}" 2>/dev/null
    
    local lines
    lines="$(wc -l < "${outfile}" 2>/dev/null || echo 0)"
    printf "${C_G}Completed. Saved to %s (%s lines)${C_N}\n" "${outfile}" "${lines}"
}

fe_collect_af() {
    local outfile="${FE_LOGDIR}/audioflinger_${FE_TIMESTAMP}.log"
    printf "${C_B}Collecting AudioFlinger state...${C_N}\n"
    
    {
        printf "AudioFlinger Explorer Report\n"
        printf "Generated: %s\n" "$(date)"
        printf "\n"
        printf "Full dumpsys\n"
        fe_safe_exec "dumpsys media.audio_flinger"
        printf "\n"
        printf "Audio policy\n"
        fe_safe_exec "dumpsys media.audio_policy"
        printf "\n"
        printf "Relevant properties\n"
        fe_safe_exec "getprop | grep -E '(audio|af\\.|vendor.audio|persist.audio|ro.audio|media.audio)'"
        printf "\n"
        printf "Process information\n"
        fe_safe_exec "ps -A | grep -iE '(audioserver|audioflinger)'"
    } > "${outfile}" 2>/dev/null
    
    local lines
    lines="$(wc -l < "${outfile}" 2>/dev/null || echo 0)"
    printf "${C_G}Completed. Saved to %s (%s lines)${C_N}\n" "${outfile}" "${lines}"
}

fe_collect_if() {
    local outfile="${FE_LOGDIR}/inputflinger_${FE_TIMESTAMP}.log"
    printf "${C_B}Collecting InputFlinger state...${C_N}\n"
    
    {
        printf "InputFlinger Explorer Report\n"
        printf "Generated: %s\n" "$(date)"
        printf "\n"
        printf "Full dumpsys\n"
        fe_safe_exec "dumpsys input"
        printf "\n"
        printf "Device nodes\n"
        fe_safe_exec "ls -la /dev/input/"
        printf "\n"
        printf "Relevant properties\n"
        fe_safe_exec "getprop | grep -E '(input|touch|pointer|gesture|keyboard|stylus)'"
    } > "${outfile}" 2>/dev/null
    
    local lines
    lines="$(wc -l < "${outfile}" 2>/dev/null || echo 0)"
    printf "${C_G}Completed. Saved to %s (%s lines)${C_N}\n" "${outfile}" "${lines}"
}

fe_collect_am() {
    local outfile="${FE_LOGDIR}/activitymanager_${FE_TIMESTAMP}.log"
    printf "${C_B}Collecting ActivityManager state...${C_N}\n"
    
    {
        printf "ActivityManager Explorer Report\n"
        printf "Generated: %s\n" "$(date)"
        printf "\n"
        printf "Activities\n"
        fe_safe_exec "dumpsys activity activities"
        printf "\n"
        printf "Stacks\n"
        fe_safe_exec "am stack list"
        printf "\n"
        printf "OOM adjustments\n"
        fe_safe_exec "dumpsys activity oom"
        printf "\n"
        printf "Processes (first 100)\n"
        fe_safe_exec "dumpsys activity processes | head -100"
        printf "\n"
        printf "Services (first 80)\n"
        fe_safe_exec "dumpsys activity services | head -80"
        printf "\n"
        printf "Settings\n"
        fe_safe_exec "dumpsys activity settings"
        printf "\n"
        printf "Relevant properties\n"
        fe_safe_exec "getprop | grep -E '(am\\.|dalvik\\.|lmk\\.|ro\\.FOREGROUND|ro\\.VISIBLE|ro\\.PERCEPTIBLE|ro\\.HOME|ro\\.EMPTY|ro\\.config.max|persist\\.sys\\.am|window_animation|transition_animation|animator_duration)'"
    } > "${outfile}" 2>/dev/null
    
    local lines
    lines="$(wc -l < "${outfile}" 2>/dev/null || echo 0)"
    printf "${C_G}Completed. Saved to %s (%s lines)${C_N}\n" "${outfile}" "${lines}"
}

declare -ga SF_PROPS=()
declare -ga SF_PROPS_DESC=()
declare -ga SF_PROPS_VALUES=()
declare -ga SF_PROPS_RISK=()

fe_init_sf_props() {
    SF_PROPS=(
        "debug.sf.hw"
        "debug.sf.log"
        "debug.sf.log_transactions"
        "debug.sf.log_composition_type"
        "debug.sf.showfps"
        "debug.sf.showupdates"
        "debug.sf.show_layers"
        "debug.sf.disable_hwc"
        "debug.sf.disable_client_composition_cache"
        "debug.sf.latch_unsignaled"
        "debug.sf.auto_latch_unsignaled"
        "debug.sf.enable_gl_backpressure"
        "debug.sf.disable_backpressure"
        "debug.sf.predict_hwc_composition_strategy"
        "debug.sf.enable_hwc_vds"
        "debug.sf.disable_hwc_virtual"
        "debug.sf.set_idle_timer_ms"
        "debug.sf.enable_skipped_frame_log"
        "debug.sf.enable_transaction_tracing"
        "debug.sf.vsync_event_phase_offset_ns"
        "debug.sf.early_phase_offset_ns"
        "debug.sf.early_gl_phase_offset_ns"
        "debug.sf.enable_adpf_cpu_hint"
        "debug.sf.ddms"
        "debug.egl.profiler"
        "debug.egl.hw"
        "debug.egl.force_msaa"
        "debug.egl.swapinterval"
        "debug.egl.force_software"
        "debug.composition.type"
        "debug.renderengine.backend"
        "debug.renderengine.skia_capture"
        "debug.renderengine.force_cpu"
        "hwui.renderer"
        "hwui.disable_vsync"
        "hwui.profile"
        "hwui.debug_layers"
        "hwui.force_blackground"
        "hwui.use_gpu_pixel_buffers"
        "hwui.compiler_thread_count"
        "hwui.shader_cache_size"
        "hwui.drop_shadow_cache_size"
        "hwui.gradient_cache_size"
        "hwui.path_cache_size"
        "hwui.circle_properties_cache_size"
        "hwui.tessellation_cache_size"
        "hwui.vertex_buffer_object_size"
        "hwui.debug_level"
        "hwui.show_dirty_regions"
        "hwui.show_overdraw"
        "hwui.show_non_rect_clip"
        "hwui.disable_atlas"
        "ro.surface_flinger.vsync_event_phase_offset_ns"
        "ro.surface_flinger.vsync_sf_event_phase_offset_ns"
        "ro.surface_flinger.present_time_offset_from_vsync_ns"
        "ro.surface_flinger.max_frame_buffer_acquired_buffers"
        "ro.surface_flinger.running_without_sync_framework"
        "ro.surface_flinger.start_graphics_allocator_service"
        "ro.surface_flinger.use_context_priority"
        "ro.surface_flinger.use_vr_flinger"
        "ro.surface_flinger.force_hwc_copy_for_virtual_displays"
        "ro.surface_flinger.has_HDR_display"
        "ro.surface_flinger.has_wide_color_display"
        "ro.surface_flinger.use_color_management"
        "ro.surface_flinger.wcg_composition_dataspace"
        "ro.surface_flinger.default_composition_dataspace"
        "ro.surface_flinger.default_composition_pixel_format"
        "ro.surface_flinger.protected_contents"
        "ro.surface_flinger.display_update_imminent_timeout_ms"
        "ro.surface_flinger.support_kernel_idle_timer"
        "ro.surface_flinger.use_content_detection_for_refresh_rate"
        "ro.surface_flinger.refresh_rate_switching"
        "ro.surface_flinger.set_display_power_timer_ms"
        "ro.surface_flinger.set_touch_timer_ms"
        "ro.surface_flinger.ignore_hdr_camera_layers"
        "sf.vsync_offset"
        "sf.early_phase_offset"
        "sf.disable_backpressure"
        "graphics.display.kernel_idle_timer.enabled"
        "persist.sys.sf.color_mode"
        "persist.sys.sf.native_mode"
        "persist.sys.sf.peak_refresh_rate"
        "persist.sys.sf.min_refresh_rate"
        "persist.sys.brightness.low_power_mode"
        "persist.traced.enable"
    )
    
    SF_PROPS_DESC=(
        "Enable hardware composition acceleration"
        "SurfaceFlinger debug logging verbosity level"
        "Log all transaction operations in detail"
        "Log composition type changes when they occur"
        "Show FPS counter overlay on the display"
        "Highlight surface updates with visual markers"
        "Show layer boundary rectangles for debugging"
        "Disable Hardware Composer, force GPU composition"
        "Disable client composition caching mechanism"
        "Latch buffer without waiting for release fence"
        "Auto Single Layer latch unsignaled mode"
        "Enable GL backpressure propagation system"
        "Disable backpressure propagation entirely"
        "Predict HWC composition strategy for optimization"
        "Enable HWC virtual display support"
        "Disable HWC virtual display functionality"
        "Set display idle timer duration in milliseconds"
        "Enable logging of skipped frames to logcat"
        "Enable transaction tracing for debugging"
        "VSYNC event phase offset in nanoseconds"
        "Early composition phase offset in nanoseconds"
        "Early GL composition phase offset in nanoseconds"
        "Enable ADPF CPU performance hint system"
        "DDMS integration support toggle"
        "Enable EGL profiling and timing"
        "Enable EGL hardware acceleration path"
        "Force MSAA anti-aliasing sample count"
        "EGL swap interval, 0 disables VSYNC"
        "Force software EGL rendering path"
        "Force specific composition type"
        "RenderEngine backend graphics library"
        "Capture Skia drawing commands to file"
        "Force CPU rendering in RenderEngine"
        "HWUI rendering backend selection"
        "Disable HWUI VSYNC synchronization"
        "Enable HWUI profiling bars overlay"
        "Debug HWUI layer operations"
        "Force all backgrounds to render black"
        "Use GPU pixel buffers for texture uploads"
        "Number of HWUI compiler threads"
        "Shader cache size in kilobytes"
        "Drop shadow cache size configuration"
        "Gradient cache size configuration"
        "Path rendering cache size"
        "Circle properties cache size"
        "Tessellation cache size in bytes"
        "Vertex buffer object size in megabytes"
        "HWUI debug output verbosity"
        "Visualize dirty regions during redraw"
        "Show overdraw visualization overlay"
        "Show non-rectangular clip regions"
        "Disable font atlas texture caching"
        "Boot-time VSYNC event phase offset"
        "Boot-time SF VSYNC event phase offset"
        "Present time offset from VSYNC in ns"
        "Maximum acquired frame buffer count"
        "Run without sync framework support"
        "Start graphics allocator service on boot"
        "Use context priority for scheduling"
        "Enable VR flinger display mode"
        "Force HWC copy for virtual displays"
        "Device has HDR display capability flag"
        "Device has wide color gamut support"
        "Enable color management pipeline"
        "Wide color gamut composition dataspace"
        "Default composition dataspace value"
        "Default composition pixel format"
        "Protected content support capability"
        "Display update imminent timeout in ms"
        "Support kernel idle timer feature"
        "Content detection for refresh rate control"
        "Enable dynamic refresh rate switching"
        "Display power timer in milliseconds"
        "Touch activity timer in milliseconds"
        "Ignore HDR camera layers flag"
        "VSYNC offset shorthand property"
        "Early phase offset shorthand property"
        "Disable backpressure shorthand property"
        "Kernel idle timer enable flag"
        "SurfaceFlinger color mode selection"
        "SurfaceFlinger native display mode"
        "Peak display refresh rate in Hz"
        "Minimum display refresh rate in Hz"
        "Low power brightness mode enable"
        "System tracing functionality enable"
    )
    
    SF_PROPS_VALUES=(
        "1=HW on, 0=force CPU composition"
        "0-3, higher value = more verbose output"
        "1=enable detailed logging, 0=disable"
        "1=enable logging, 0=disable"
        "1=show FPS overlay, 0=hide"
        "1=show visual updates, 0=hide"
        "1=show layer borders, 0=hide"
        "1=force GPU, 0=normal operation"
        "1=disable cache, 0=enable cache"
        "1=enable, may reduce latency"
        "1=enable AutoSingleLayer mode"
        "1=on, affects frame pacing behavior"
        "1=disable, may cause frame jank"
        "0=off, 1=predictive strategy"
        "1=enable, 0=disable"
        "1=disable, 0=enable"
        "milliseconds integer value"
        "1=enable frame skip logging"
        "1=enable transaction tracing"
        "nanoseconds integer value"
        "nanoseconds integer value"
        "nanoseconds integer value"
        "true or false boolean"
        "0=disable, 1=enable"
        "1=enable, adds rendering overhead"
        "1=enable HW EGL path"
        "sample count integer, performance cost"
        "0=no VSYNC, 1=sync to VSYNC"
        "1=force software rendering"
        "gpu, cpu, hwc, mdp, or d2d"
        "skiagl, skiavk, angle, or gles"
        "1=enable, generates large debug files"
        "1=force CPU, severe performance impact"
        "opengl, skiagl, skiavk, or angle"
        "true=disable, screen tearing risk"
        "true=show profiling overlay"
        "true=enable layer debugging"
        "true or false boolean"
        "true or false boolean"
        "integer from 0 to 4"
        "integer kilobyte value"
        "integer cache size"
        "integer cache size"
        "integer cache size"
        "integer cache size"
        "integer cache size"
        "integer megabyte value"
        "0=off, 1=verbose, 2=more verbose"
        "true=visualize dirty regions"
        "true=show overdraw visualization"
        "true=show non-rect clips"
        "true=disable, performance impact"
        "nanoseconds, ro.* read-only property"
        "nanoseconds, ro.* read-only property"
        "nanoseconds, ro.* read-only property"
        "integer, affects display smoothness"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "integer dataspace value, ro.*"
        "integer dataspace value, ro.*"
        "integer pixel format, ro.*"
        "true/false, ro.* read-only property"
        "milliseconds, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "true/false, ro.* read-only property"
        "milliseconds, ro.* read-only property"
        "milliseconds, ro.* read-only property"
        "true/false, ro.* read-only property"
        "nanoseconds value"
        "nanoseconds value"
        "1=disable backpressure system"
        "true or false boolean"
        "integer color space identifier"
        "integer display mode selection"
        "float value in Hertz"
        "float value in Hertz"
        "true or false boolean"
        "1=enable system tracing"
    )
    
    SF_PROPS_RISK=(
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "MEDIUM" "LOW" "MEDIUM"
        "MEDIUM" "LOW" "MEDIUM" "LOW" "LOW" "MEDIUM" "LOW" "LOW" "LOW" "HIGH"
        "HIGH" "HIGH" "LOW" "LOW" "LOW" "LOW" "HIGH" "HIGH" "HIGH" "MEDIUM"
        "MEDIUM" "LOW" "HIGH" "MEDIUM" "HIGH" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "MEDIUM" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "MEDIUM" "MEDIUM" "MEDIUM"
        "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "LOW"
        "MEDIUM" "MEDIUM" "MEDIUM" "LOW" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "LOW" "LOW"
    )
}

fe_list_generic_props() {
    local title="$1"
    local -n props=$2
    local -n descs=$3
    local -n values=$4
    local -n risks=$5
    
    fe_print_title "${title}" "$C_C"
    
    local total=${#props[@]}
    printf "${C_GR}Total properties: %d${C_N}\n\n" "${total}"
    
    printf "${C_W}%-6s %-50s %-8s %s${C_N}\n" "Num" "Property name" "Risk" "Current value"
    printf "${C_GR}%-6s %-50s %-8s %s${C_N}\n" "---" "--------------------------------------------------" "--------" "-------------"
    
    local i
    for ((i=0; i<total; i++)); do
        local num=$((i+1))
        local prop="${props[${i}]}"
        local desc="${descs[${i}]}"
        local risk="${risks[${i}]}"
        local current
        current="$(fe_safe_exec "getprop '${prop}'")"
        
        local risk_color="${C_G}"
        [[ "${risk}" == "MEDIUM" ]] && risk_color="${C_Y}"
        [[ "${risk}" == "HIGH" ]] && risk_color="${C_R}"
        
        printf "${C_O}%-6s${C_N} ${C_T}%-50s${C_N} ${risk_color}%-8s${C_N} ${C_O}%s${C_N}\n" \
            "${num}" "${prop:0:50}" "${risk}" "${current:-<not set>}"
        
        if (( (i+1) % 20 == 0 && i < total-1 )); then
            printf "\n"
            read -rp "${C_GR}Press Enter to continue browsing...${C_N} " _
            printf "\n"
            printf "${C_W}%-6s %-50s %-8s %s${C_N}\n" "Num" "Property name" "Risk" "Current value"
            printf "${C_GR}%-6s %-50s %-8s %s${C_N}\n" "---" "--------------------------------------------------" "--------" "-------------"
        fi
    done
}

fe_tune_generic_props() {
    local title="$1"
    local -n props=$2
    local -n descs=$3
    local -n values=$4
    local -n risks=$5
    
    if ! fe_check_write; then
        return
    fi
    
    fe_print_title "${title}" "$C_C"
    
    local total=${#props[@]}
    printf "${C_GR}Enter property number to modify (1-%d), or 0 to return${C_N}\n" "${total}"
    
    while true; do
        printf "\n"
        read -rp "${C_W}Property number: ${C_N}" sel
        
        if [[ "${sel}" == "0" || -z "${sel}" ]]; then
            break
        fi
        
        if ! [[ "${sel}" =~ ^[0-9]+$ ]]; then
            printf "${C_R}Please enter a valid number.${C_N}\n"
            continue
        fi
        
        local idx=$((sel-1))
        if (( idx < 0 || idx >= total )); then
            printf "${C_R}Number out of valid range (1-%d).${C_N}\n" "${total}"
            continue
        fi
        
        local prop="${props[${idx}]}"
        local desc="${descs[${idx}]}"
        local val_range="${values[${idx}]}"
        local risk="${risks[${idx}]}"
        local current
        current="$(fe_safe_exec "getprop '${prop}'")"
        
        printf "\n"
        printf "${C_W}Property:${C_N} ${C_T}%s${C_N}\n" "${prop}"
        printf "${C_W}Description:${C_N} %s\n" "${desc}"
        printf "${C_W}Current value:${C_N} ${C_O}%s${C_N}\n" "${current:-<not set>}"
        printf "${C_W}Allowed values:${C_N} %s\n" "${val_range}"
        printf "${C_W}Risk level:${C_N} "
        case "${risk}" in
            "LOW") printf "${C_G}%s${C_N}" "${risk}" ;;
            "MEDIUM") printf "${C_Y}%s${C_N}" "${risk}" ;;
            "HIGH") printf "${C_R}%s${C_N}" "${risk}" ;;
        esac
        printf "\n"
        
        if [[ "${prop}" == ro.* ]]; then
            printf "${C_M}Note: This is a read-only (ro.*) property and requires resetprop.${C_N}\n"
        fi
        
        printf "\n"
        read -rp "${C_Y}New value (leave empty to cancel): ${C_N}" newval
        
        if [[ -n "${newval}" ]]; then
            printf "\n"
            fe_set_prop_safe "${prop}" "${newval}" "${risk}"
        else
            printf "${C_GR}Operation cancelled.${C_N}\n"
        fi
    done
}

fe_sf_service_codes() {
    fe_print_title "SurfaceFlinger binder service codes" "$C_O"
    
    printf "${C_GR}Note: Code numbers vary between Android versions. These are reference values.${C_N}\n\n"
    
    printf "${C_W}%-8s %-45s${C_N}\n" "Code" "Method name"
    printf "${C_GR}%-8s %-45s${C_N}\n" "--------" "---------------------------------------------"
    
    local -a codes=(
        "1000:createConnection"
        "1001:createDisplay"
        "1002:destroyDisplay"
        "1003:getDisplayInfo"
        "1004:getDisplayConfigs"
        "1005:getActiveConfig"
        "1006:setActiveConfig"
        "1007:getDisplayColorModes"
        "1008:getActiveColorMode"
        "1009:setActiveColorMode"
        "1010:createLayer"
        "1011:createBufferQueueLayer"
        "1012:createContainerLayer"
        "1013:mirrorLayer"
        "1014:setTransactionState"
        "1015:getSupportedFrameTimestamps"
        "1016:getCompositionDisplayPreferredBrightness"
        "1017:getHdrCapabilities"
        "1018:getDisplayedContentSamplingAttributes"
        "1019:getDisplayContentSamplingEnabled"
        "1020:setDisplayContentSamplingEnabled"
        "1021:getProtectedContentSupport"
        "1022:getDisplayNativePrimaries"
        "1023:notifyPowerBoost"
        "1024:getDisplayBrightnessSupport"
        "1025:setDisplayBrightness"
        "1026:addRegionSamplingListener"
        "1027:removeRegionSamplingListener"
        "1028:addFpsListener"
        "1029:removeFpsListener"
        "1030:getLayerDebugInfo"
        "1031:captureScreen"
        "1032:captureLayers"
        "1033:setAutoLowLatencyMode"
        "1034:getGameModeSupport"
        "1035:notifyExpectedPresent"
        "1036:getDisplayBrightness"
        "1037:addHdrLayerInfoListener"
        "1038:removeHdrLayerInfoListener"
        "1039:notifyPowerHint"
        "1040:setRefreshRateSwitching"
        "1041:getFrameRateOverride"
        "1042:clearFrameRateOverride"
        "1043:setFrameRateOverride"
        "1044:getDisplayConnectionType"
        "1045:getSupportedDisplayBrightness"
    )
    
    for entry in "${codes[@]}"; do
        local code="${entry%%:*}"
        local method="${entry##*:}"
        printf "${C_O}%-8s${C_N} ${C_T}%-45s${C_N}\n" "${code}" "${method}"
    done
    
    printf "\n${C_GR}Usage: service call SurfaceFlinger <code> [arguments]${C_N}\n"
}

fe_sf_layer_analysis() {
    fe_print_title "SurfaceFlinger layer analysis" "$C_M"
    
    fe_print_subtitle "Layer hierarchy"
    local layer_list
    layer_list="$(fe_safe_exec "dumpsys SurfaceFlinger --list")"
    if [[ -n "${layer_list}" ]]; then
        printf "%s\n" "${layer_list}" | head -60
        local total
        total="$(printf "%s\n" "${layer_list}" | wc -l)"
        if (( total > 60 )); then
            printf "${C_GR}... and %d more layers${C_N}\n" "$((total-60))"
        fi
    else
        fe_safe_exec "dumpsys SurfaceFlinger | grep -E '^[[:space:]]+[a-zA-Z].*#' | head -60"
    fi
    
    fe_print_subtitle "Composition type summary"
    local dev_count client_count
    dev_count="$(fe_safe_exec "dumpsys SurfaceFlinger | grep -c 'DEVICE' || echo 0")"
    client_count="$(fe_safe_exec "dumpsys SurfaceFlinger | grep -c 'CLIENT' || echo 0")"
    printf "  DEVICE (HWC accelerated) layers: ${C_G}%s${C_N}\n" "${dev_count}"
    printf "  CLIENT (GPU rendered) layers:    ${C_Y}%s${C_N}\n" "${client_count}"
    
    fe_print_subtitle "VSYNC and DispSync information"
    fe_safe_exec "dumpsys SurfaceFlinger | grep -A5 -i 'vsync\\|disp sync\\|DispSync' | head -15"
    
    fe_print_subtitle "Frame timestats"
    local timestats
    timestats="$(fe_safe_exec "dumpsys SurfaceFlinger timestats | head -25")"
    if [[ -n "${timestats}" ]]; then
        printf "%s\n" "${timestats}"
    else
        printf "${C_GR}Timestats not available on this Android version.${C_N}\n"
    fi
}

declare -ga AF_PROPS=()
declare -ga AF_PROPS_DESC=()
declare -ga AF_PROPS_VALUES=()
declare -ga AF_PROPS_RISK=()

fe_init_af_props() {
    AF_PROPS=(
        "vendor.audio.record"
        "vendor.audio.record.in"
        "vendor.audio.record.af"
        "vendor.audio.record.out"
        "vendor.audio.hal.dump"
        "vendor.audio.fluence.speaker"
        "vendor.audio.fluence.voicecall"
        "vendor.audio.fluence.voicerec"
        "vendor.audio.fluence.audiorec"
        "vendor.audio.ambisonic.capture"
        "vendor.audio.ambisonic.playback"
        "vendor.audio.spatializer.enabled"
        "vendor.audio.haptic.enabled"
        "vendor.audio.dualmic.config"
        "vendor.audio.handset.mic.type"
        "vendor.audio.duplex.rec"
        "ro.audio.silent"
        "ro.audio.output.sample_rate"
        "ro.audio.output.bit_depth"
        "ro.audio.input.sample_rate"
        "ro.audio.input.bit_depth"
        "af.tee"
        "af.fast_mixer_enabled"
        "af.fast_track_multiplier"
        "af.thread_priority"
        "af.mixer_buffer_size_ms"
        "af.resampler_quality"
        "af.disable_effects"
        "af.hw_av_sync"
        "af.deep_buffer.enabled"
        "af.offload.enabled"
        "af.offload.video"
        "af.offload.gapless.enabled"
        "media.audio.flinger.debug.level"
        "persist.audio.fluence.speaker"
        "persist.audio.fluence.voicecall"
        "persist.audio.dualmic.config"
        "persist.audio.handset.mic.type"
        "persist.audio.duplex.rec"
        "persist.vendor.audio.ambisonic.capture"
        "persist.vendor.audio.ambisonic.playback"
        "persist.vendor.audio.spatializer.enabled"
        "persist.vendor.audio.haptic.enabled"
        "audio.offload.disable"
        "audio.deep_buffer.media"
        "audio.offload.min.duration.secs"
        "audio.offload.video.min.duration.secs"
        "audio.offload.multiple.enabled"
        "audio.offload.gapless.enabled"
        "audio.dolby.dap.enabled"
        "audio.dolby.ds1.enabled"
        "audio.dolby.ds2.enabled"
        "ro.config.media_vol_steps"
        "ro.config.vc_call_vol_steps"
        "ro.config.alarm_vol_steps"
        "persist.sys.audio.focus.timeout"
        "media.stagefright.enable-player"
        "media.stagefright.enable-http"
        "media.stagefright.enable-record"
        "media.stagefright.enable-scan"
        "media.stagefright.omx_default_rank"
        "tunnel.audio.encode"
        "tunnel.audio.decode"
        "af.playback_thread_priority"
        "af.record_thread_priority"
        "af.fast_capture_enabled"
        "af.max_normal_tracks"
        "af.max_fast_tracks"
        "af.frame_count"
        "af.hal_buffer_size"
        "persist.audio.safetymedia.enabled"
        "ro.audio.monitorRotation"
        "vendor.audio.snd_monitor.enabled"
        "vendor.audio.speaker.prot.enable"
        "vendor.audio.thermal.throttle"
    )
    
    AF_PROPS_DESC=(
        "Audio recording debug output level"
        "Input path audio recording debug"
        "AudioFlinger mixer output PCM dump"
        "Output path audio recording debug"
        "Audio HAL debug dump enable"
        "Speaker fluence echo cancellation"
        "Voice call fluence processing"
        "Voice recording fluence processing"
        "Audio recording fluence processing"
        "Ambisonic audio capture enable"
        "Ambisonic audio playback enable"
        "Spatializer audio processing enable"
        "Haptic audio feedback enable"
        "Dual microphone configuration mode"
        "Handset microphone interface type"
        "Duplex simultaneous recording enable"
        "Global audio silent mode master switch"
        "Audio output sample rate in Hertz"
        "Audio output bit depth configuration"
        "Audio input sample rate in Hertz"
        "Audio input bit depth configuration"
        "Audio TEE sink debug bitmask value"
        "Fast mixer low-latency path enable"
        "Fast audio track count multiplier"
        "Audio processing thread priority"
        "Audio mixer buffer size in milliseconds"
        "Audio resampler quality setting"
        "Disable all audio effects processing"
        "Hardware audio-video sync enable"
        "Deep audio buffering mode enable"
        "Audio hardware offload enable"
        "Video audio offload enable flag"
        "Gapless audio offload playback enable"
        "AudioFlinger debug logging level"
        "Persistent speaker fluence setting"
        "Persistent voice call fluence setting"
        "Persistent dual mic configuration"
        "Persistent handset mic type setting"
        "Persistent duplex recording setting"
        "Persistent ambisonic capture setting"
        "Persistent ambisonic playback setting"
        "Persistent spatializer enable setting"
        "Persistent haptic audio enable setting"
        "Disable all audio offload paths"
        "Deep buffer for media audio path"
        "Minimum duration for audio offload"
        "Minimum duration for video offload"
        "Multiple simultaneous offload streams"
        "Gapless offload playback support"
        "Dolby audio processing enable"
        "Dolby Surround processing 1 enable"
        "Dolby Surround processing 2 enable"
        "Media volume step count setting"
        "Voice call volume step count"
        "Alarm volume step count setting"
        "Audio focus timeout in milliseconds"
        "Stagefright media player enable"
        "Stagefright HTTP streaming enable"
        "Stagefright recording support enable"
        "Stagefright media scanner enable"
        "OMX component default rank value"
        "Tunnel mode audio encoding enable"
        "Tunnel mode audio decoding enable"
        "Audio playback thread priority level"
        "Audio record thread priority level"
        "Fast audio capture path enable"
        "Maximum normal audio track count"
        "Maximum fast audio track count"
        "Audio frame count per buffer"
        "Audio HAL buffer size in bytes"
        "Safety media feature enable flag"
        "Monitor rotation for audio routing"
        "Audio sound monitoring enable"
        "Speaker protection circuit enable"
        "Thermal throttling protection enable"
    )
    
    AF_PROPS_VALUES=(
        "0=off, 1=input, 2=FastMixer, 4=per-track"
        "debug level integer 0-4"
        "0-4, dumps PCM data to /data/misc/audio"
        "debug level integer 0-4"
        "1=enable HAL debug dump output"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "endfire, broadside, or voice"
        "digital or analog interface"
        "true or false boolean value"
        "true=mute all audio globally"
        "44100, 48000, 96000, or 192000 Hz"
        "16, 24, or 32 bits per sample"
        "8000 to 192000 Hz range"
        "16, 24, or 32 bits per sample"
        "bitmask 0-7: 1=input, 2=output, 4=tracks"
        "1=enable low-latency fast path"
        "integer multiplier value"
        "nice level from -20 to 19"
        "milliseconds buffer duration"
        "0=fastest, 1=high, 2=very high quality"
        "1=disable all audio effects"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "verbosity level 0-3"
        "true or false boolean value"
        "true or false boolean value"
        "endfire, broadside, or voice"
        "digital or analog interface"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "1=disable all audio offload"
        "true or false boolean value"
        "seconds threshold value"
        "seconds threshold value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "integer e.g. 15, 25, or 30 steps"
        "integer step count value"
        "integer step count value"
        "timeout in milliseconds"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "integer priority rank value"
        "true or false boolean value"
        "true or false boolean value"
        "nice level priority value"
        "nice level priority value"
        "1=enable low-latency capture"
        "integer track count limit"
        "integer track count limit"
        "buffer size in audio frames"
        "buffer size in bytes, affects latency"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
    )
    
    AF_PROPS_RISK=(
        "LOW" "LOW" "MEDIUM" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "MEDIUM" "HIGH" "HIGH" "HIGH"
        "HIGH" "LOW" "MEDIUM" "MEDIUM" "MEDIUM" "HIGH" "LOW" "MEDIUM" "LOW" "MEDIUM"
        "MEDIUM" "MEDIUM" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "MEDIUM" "MEDIUM" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "MEDIUM" "MEDIUM" "MEDIUM" "LOW" "LOW" "HIGH" "HIGH" "LOW"
        "LOW" "LOW" "LOW" "LOW"
    )
}

fe_af_thread_analysis() {
    fe_print_title "AudioFlinger thread analysis" "$C_M"
    
    fe_print_subtitle "Output mixer threads"
    fe_safe_exec "dumpsys media.audio_flinger | grep -A10 'Output thread' | head -40"
    
    fe_print_subtitle "Input capture threads"
    fe_safe_exec "dumpsys media.audio_flinger | grep -A8 'Input thread' | head -30"
    
    fe_print_subtitle "Fast mixer status"
    fe_safe_exec "dumpsys media.audio_flinger | grep -A5 'FastMixer\\|Fast mixer' | head -20"
    
    fe_print_subtitle "Active audio effects"
    fe_safe_exec "dumpsys media.audio_flinger | grep -A15 'Effects' | head -30"
}

declare -ga IF_PROPS=()
declare -ga IF_PROPS_DESC=()
declare -ga IF_PROPS_VALUES=()
declare -ga IF_PROPS_RISK=()

fe_init_if_props() {
    IF_PROPS=(
        "ro.input.max_events_per_second"
        "ro.input.key_repeat_delay"
        "ro.input.key_repeat_timeout"
        "ro.inputreader.pointer_gesture_enabled"
        "ro.inputreader.wheel_velocity_scale"
        "ro.inputdispatcher.timeout"
        "persist.sys.input.touch_rotation"
        "persist.sys.input.touch.size_compensation"
        "persist.sys.input.touch.pressure_compensation"
        "persist.sys.inputfilter.enabled"
        "debug.input.trace"
        "debug.input.show_touches"
        "debug.input.pointer_speed"
        "debug.input.gesture.quiescent"
        "debug.input.dispatcher.timeout"
        "debug.input.reader.log_level"
        "debug.input.dispatcher.log_level"
        "persist.sys.pointer.gesture.enabled"
        "persist.sys.pointer.quiet_interval"
        "persist.sys.pointer.drag_min_switch_speed"
        "persist.sys.pointer.tap_interval"
        "persist.sys.pointer.tap_slop"
        "persist.sys.pointer.multitouch_settle_interval"
        "persist.sys.pointer.multitouch_min_distance"
        "persist.sys.keyboard.layout"
        "persist.sys.keyboard.auto_repeat"
        "persist.sys.keyboard.virtual_key_quiet_time"
        "debug.stylus.gesture.enabled"
        "debug.stylus.hover.enabled"
        "debug.touchpad.gesture.enabled"
        "debug.touchpad.natural_scrolling"
        "debug.touchpad.tap_to_click"
        "debug.touchpad.two_finger_scroll"
        "persist.sys.accessibility.touch_exploration"
        "persist.sys.accessibility.magnification"
        "persist.sys.accessibility.auto_rotate"
        "touch.orientationAware"
        "touch.size.calibration"
        "touch.pressure.calibration"
        "touch.wakeup"
        "persist.sys.touch_filter"
        "persist.sys.touch_jitter_filter"
        "persist.sys.touch_sensitivity"
        "persist.sys.edge_filter"
        "persist.sys.palm_rejection"
        "persist.sys.palm_rejection_level"
        "debug.motionevent.log_level"
        "debug.keyevent.log_level"
        "persist.sys.virtual_key_quiet_time"
        "persist.sys.show_ime_with_hard_keyboard"
        "persist.sys.keyrepeat.delay"
        "persist.sys.keyrepeat.period"
        "persist.sys.long_press.timeout"
        "persist.sys.tap_timeout"
        "persist.sys.double_tap_timeout"
        "persist.sys.windows.touch_slop"
        "persist.sys.minimum_fling_velocity"
        "persist.sys.maximum_fling_velocity"
        "persist.sys.gesture_scroll_friction"
        "persist.sys.input.force_mouse_as_touch"
        "persist.sys.input.disable_touchpad"
        "persist.sys.input.disable_keyboard"
        "persist.sys.input.disable_stylus"
        "debug.input.ANR"
        "debug.input.focus"
        "debug.input.monitor"
        "persist.sys.touch.hover.enabled"
        "persist.sys.gamepad.enabled"
        "persist.sys.joystick.enabled"
    )
    
    IF_PROPS_DESC=(
        "Maximum input events processed per second"
        "Delay before key repeat begins"
        "Timeout between key repeat events"
        "Pointer gesture enable at boot time"
        "Mouse wheel velocity scale factor"
        "Input event dispatching timeout"
        "Touch coordinate rotation angle"
        "Touch reported size compensation"
        "Touch pressure value compensation"
        "Input event filter system enable"
        "Input event tracing enable flag"
        "Show visual touch indicators on screen"
        "Pointer speed multiplier factor"
        "Gesture quiescent quiet period"
        "Dispatcher timeout override value"
        "Input reader logging verbosity"
        "Input dispatcher logging verbosity"
        "Pointer gesture recognition enable"
        "Pointer quiet interval in milliseconds"
        "Minimum drag switch speed in px/s"
        "Tap detection interval in ms"
        "Tap movement tolerance in pixels"
        "Multitouch settle interval in ms"
        "Multitouch minimum distance in px"
        "Keyboard layout identifier string"
        "Keyboard auto repeat feature enable"
        "Virtual key quiet time in ms"
        "Stylus gesture recognition enable"
        "Stylus hover detection enable"
        "Touchpad gesture support enable"
        "Touchpad natural scrolling direction"
        "Touchpad tap to click feature"
        "Touchpad two-finger scroll enable"
        "Accessibility touch exploration mode"
        "Display magnification gestures enable"
        "Auto-rotate screen accessibility"
        "Touch orientation awareness flag"
        "Touch size calibration method"
        "Touch pressure calibration method"
        "Touch wakeup from sleep enable"
        "Touch noise filter level setting"
        "Touch jitter smoothing filter"
        "Touch sensitivity boost level"
        "Edge touch filter width in pixels"
        "Palm rejection system enable"
        "Palm rejection sensitivity level"
        "MotionEvent logging verbosity"
        "KeyEvent logging verbosity level"
        "Virtual key quiet period in ms"
        "Show IME with hardware keyboard"
        "Key repeat delay override in ms"
        "Key repeat period override in ms"
        "Long press detection timeout in ms"
        "Single tap detection timeout in ms"
        "Double tap detection timeout in ms"
        "Window touch slop distance in px"
        "Minimum fling velocity in px/s"
        "Maximum fling velocity in px/s"
        "Scroll friction coefficient value"
        "Force mouse input as touch events"
        "Disable touchpad input devices"
        "Disable keyboard input devices"
        "Disable stylus input devices"
        "Input ANR debugging enable flag"
        "Input focus change debug logging"
        "Input monitor channels enable"
        "Touch hover detection enable flag"
        "Gamepad input device support enable"
        "Joystick input device support enable"
    )
    
    IF_PROPS_VALUES=(
        "integer value, default approximately 90"
        "milliseconds, default is 50ms"
        "milliseconds, default is 500ms"
        "true or false, ro.* property"
        "float multiplier value"
        "milliseconds, default 5000ms"
        "0, 90, 180, or 270 degrees"
        "compensation scale 0-100"
        "compensation scale 0-100"
        "true or false boolean value"
        "1=enable event trace output"
        "1=show indicators, 0=hide"
        "float multiplier, default 1.0"
        "milliseconds time value"
        "milliseconds timeout value"
        "verbosity level from 0 to 3"
        "verbosity level from 0 to 3"
        "true or false boolean value"
        "milliseconds time value"
        "pixels per second velocity"
        "milliseconds interval value"
        "distance in pixels integer"
        "milliseconds time value"
        "distance in pixels integer"
        "keyboard layout identifier string"
        "true or false boolean value"
        "milliseconds time value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "0=disabled, 1=orientation aware"
        "none, geometric, diameter, or area"
        "none or physical calibration"
        "0=disabled, 1=wake on touch"
        "filter level integer 0-10"
        "true or false boolean value"
        "sensitivity boost integer 0-100"
        "filter width in pixels 0-50"
        "true or false boolean value"
        "sensitivity level integer 0-10"
        "verbosity level from 0 to 3"
        "verbosity level from 0 to 3"
        "milliseconds time value"
        "true or false boolean value"
        "milliseconds delay value"
        "milliseconds period value"
        "milliseconds, default is 500ms"
        "milliseconds, default is 100ms"
        "milliseconds, default is 300ms"
        "distance in pixels integer"
        "velocity in pixels per second"
        "velocity in pixels per second"
        "float friction coefficient"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "1=enable ANR debug output"
        "1=enable focus debug logging"
        "1=enable input monitoring"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
    )
    
    IF_PROPS_RISK=(
        "MEDIUM" "LOW" "LOW" "HIGH" "MEDIUM" "HIGH" "MEDIUM" "LOW" "LOW" "MEDIUM"
        "LOW" "LOW" "LOW" "LOW" "HIGH" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "MEDIUM" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "MEDIUM"
        "MEDIUM" "MEDIUM" "MEDIUM" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW"
    )
}

fe_if_device_list() {
    fe_print_title "Input device listing" "$C_M"
    
    fe_print_subtitle "Device nodes"
    fe_safe_exec "ls -la /dev/input/"
    
    fe_print_subtitle "Device details"
    for dev in /dev/input/event*; do
        [[ -e "${dev}" ]] || continue
        local devinfo
        devinfo="$(fe_safe_exec "getevent -i '${dev}' | grep -i 'name' | head -1")"
        printf "  ${C_G}%s${C_N}: %s\n" "${dev}" "${devinfo:-Unknown device}"
    done
}

fe_if_dispatcher_state() {
    fe_print_title "Input dispatcher state" "$C_M"
    fe_safe_exec "dumpsys input | grep -A40 'Input Dispatcher State'"
}

fe_if_monitor() {
    fe_print_title "Input event monitor" "$C_Y"
    printf "${C_GR}Monitoring input events in real-time. Press Ctrl+C to stop.${C_N}\n"
    printf "${C_GR}Format: [device] [type] [code] [value]${C_N}\n\n"
    fe_safe_exec_noerr "getevent -l"
}

declare -ga AM_PROPS=()
declare -ga AM_PROPS_DESC=()
declare -ga AM_PROPS_VALUES=()
declare -ga AM_PROPS_RISK=()

fe_init_am_props() {
    AM_PROPS=(
        "ro.am.crash.loop.threshold"
        "ro.am.crash.loop.window"
        "ro.am.anr.debugger_delay"
        "persist.sys.am.relax_priority_check"
        "persist.sys.am.memory_level_step"
        "persist.sys.am.foreground_service_timeout"
        "persist.sys.am.background_service_timeout"
        "persist.sys.am.process_limit"
        "persist.sys.am.always_finish_activities"
        "persist.sys.am.strict_mode"
        "persist.sys.am.multiwindow.enabled"
        "persist.sys.am.freeform.enabled"
        "persist.sys.am.pip.enabled"
        "persist.sys.am.split_screen.enabled"
        "debug.am.always_create_process"
        "debug.am.track_activities"
        "debug.am.dont_keep_activities"
        "debug.am.background_check"
        "debug.am.anr"
        "debug.am.crash"
        "debug.am.service"
        "debug.am.broadcast"
        "debug.am.provider"
        "debug.am.process"
        "debug.am.oom"
        "debug.am.lru"
        "debug.am.pss"
        "debug.am.lock"
        "ro.config.max_cached_processes"
        "ro.config.max_empty_processes"
        "ro.FOREGROUND_APP_ADJ"
        "ro.VISIBLE_APP_ADJ"
        "ro.PERCEPTIBLE_APP_ADJ"
        "ro.HEAVY_WEIGHT_APP_ADJ"
        "ro.SERVICE_ADJ"
        "ro.HOME_APP_ADJ"
        "ro.PREVIOUS_APP_ADJ"
        "ro.BACKUP_APP_ADJ"
        "ro.HIDDEN_APP_MIN_ADJ"
        "ro.HIDDEN_APP_MAX_ADJ"
        "ro.EMPTY_APP_ADJ"
        "ro.CACHED_APP_MIN_ADJ"
        "ro.CACHED_APP_MAX_ADJ"
        "ro.lmk.use_minfree_levels"
        "ro.lmk.low"
        "ro.lmk.medium"
        "ro.lmk.critical"
        "ro.lmk.kill_heaviest_task"
        "ro.lmk.swap_free_low_percentage"
        "ro.lmk.psi_partial_stall_ms"
        "ro.lmk.psi_complete_stall_ms"
        "ro.lmk.thrashing_limit"
        "ro.lmk.debug"
        "dalvik.vm.heapstartsize"
        "dalvik.vm.heapgrowthlimit"
        "dalvik.vm.heapsize"
        "dalvik.vm.heaptargetutilization"
        "dalvik.vm.heapminfree"
        "dalvik.vm.heapmaxfree"
        "dalvik.vm.usejit"
        "dalvik.vm.jit.codecachesize"
        "dalvik.vm.jit.threshold"
        "dalvik.vm.dex2oat-filter"
        "dalvik.vm.checkjni"
        "dalvik.vm.check-dex-file"
        "dalvik.vm.execution-mode"
        "dalvik.vm.lockprof.threshold"
        "dalvik.vm.gc.parallel.threads"
        "dalvik.vm.gc.concurrent.threads"
        "persist.sys.use_dedicated_gc_thread"
        "persist.sys.dalvik.vm.lib"
        "persist.sys.dalvik.vm.lib.2"
        "window_animation_scale"
        "transition_animation_scale"
        "animator_duration_scale"
        "persist.sys.wm.disable_animations"
        "persist.sys.wm.keep_screen_on"
        "persist.sys.wm.force_desktop_mode"
        "debug.wm.show_ime_layers"
        "debug.wm.show_surface_layers"
        "debug.wm.show_window_layers"
        "debug.wm.trace"
        "debug.wm.focus"
        "debug.wm.orientation"
        "debug.wm.anim"
        "debug.wm.screen_rotation"
        "persist.sys.rotation.allow_180"
        "persist.sys.rotation.lock"
        "persist.sys.rotation.accelerometer"
        "persist.sys.ui.mode"
        "persist.sys.font.scale"
        "persist.sys.density"
        "persist.sys.smallest_width"
    )
    
    AM_PROPS_DESC=(
        "Crash loop detection count threshold"
        "Crash loop detection time window"
        "ANR debugger attach delay in ms"
        "Relax priority checking behavior"
        "Memory pressure level step size"
        "Foreground service timeout seconds"
        "Background service timeout seconds"
        "Maximum background process limit"
        "Always finish activities on leave"
        "Strict mode checking enable flag"
        "Multi-window display support enable"
        "Freeform window mode support enable"
        "Picture-in-picture mode support enable"
        "Split-screen multi-window enable"
        "Always create new process for apps"
        "Track activity lifecycle events"
        "Do not keep activities in background"
        "Background operation check debug"
        "ANR event debug logging enable"
        "Application crash debug logging"
        "Service lifecycle debug logging"
        "Broadcast delivery debug logging"
        "Content provider debug logging"
        "Process management debug logging"
        "OOM adjustment debug logging"
        "LRU list management debug logging"
        "PSS memory calculation debug"
        "Lock contention debug logging enable"
        "Maximum cached process count limit"
        "Maximum empty process count limit"
        "Foreground app OOM adjustment value"
        "Visible app OOM adjustment value"
        "Perceptible app OOM adjustment value"
        "Heavy weight app OOM adjustment value"
        "Service process OOM adjustment value"
        "Home launcher app OOM adj value"
        "Previous app OOM adjustment value"
        "Backup app OOM adjustment value"
        "Hidden app minimum OOM adj value"
        "Hidden app maximum OOM adj value"
        "Empty app OOM adjustment value"
        "Cached app minimum OOM adj value"
        "Cached app maximum OOM adj value"
        "Use minfree levels for LMK decisions"
        "Low memory pressure kill threshold"
        "Medium memory pressure threshold"
        "Critical memory pressure threshold"
        "Kill heaviest memory task first"
        "Swap free low percentage threshold"
        "PSI partial stall threshold in ms"
        "PSI complete stall threshold in ms"
        "Thrashing detection limit in pages"
        "Low memory killer debug enable"
        "Dalvik VM initial heap size"
        "Dalvik per-app heap growth limit"
        "Dalvik VM maximum heap size"
        "Dalvik heap target utilization ratio"
        "Dalvik heap minimum free memory"
        "Dalvik heap maximum free memory"
        "Use JIT compiler for bytecode"
        "JIT compiler code cache size"
        "JIT compilation threshold count"
        "DEX ahead-of-time compilation filter"
        "Check JNI calls for correctness"
        "Check DEX file integrity on load"
        "VM execution mode selection"
        "Lock profiling threshold in ms"
        "Parallel garbage collection threads"
        "Concurrent garbage collection threads"
        "Use dedicated GC thread for cleanup"
        "Dalvik VM library selection path"
        "ART runtime VM library path"
        "Window animation speed scale factor"
        "Transition animation speed scale"
        "Animator duration speed scale"
        "Disable all window animations"
        "Keep screen always on setting"
        "Force desktop windowing mode"
        "Show IME window layers debug"
        "Show surface layers debug view"
        "Show window layers debug view"
        "Window manager trace enable flag"
        "Window focus change debug logging"
        "Orientation change debug logging"
        "Window animation debug logging"
        "Screen rotation debug logging"
        "Allow 180 degree rotation angle"
        "Lock rotation to specific mode"
        "Accelerometer-based rotation enable"
        "UI mode override selection"
        "Global font scale factor value"
        "Display density DPI override"
        "Smallest width DP override value"
    )
    
    AM_PROPS_VALUES=(
        "integer crash count threshold"
        "time window in seconds"
        "milliseconds delay value"
        "true or false boolean value"
        "integer step size value"
        "timeout in seconds integer"
        "timeout in seconds integer"
        "integer process count limit"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "integer maximum count value"
        "integer maximum count value"
        "integer OOM adj, default 0"
        "integer OOM adj, default 100"
        "integer OOM adj, default 200"
        "integer OOM adj, default 300"
        "integer OOM adj, default 500"
        "integer OOM adj, default 600"
        "integer OOM adj, default 700"
        "integer OOM adj, default 800"
        "integer OOM adj, default 900"
        "integer OOM adj, default 999"
        "integer OOM adj, default 999"
        "integer OOM adj, default 900"
        "integer OOM adj, default 999"
        "true or false boolean value"
        "OOM adj score, default 1001"
        "OOM adj score, default 800"
        "OOM adj score, default 0"
        "true or false boolean value"
        "integer percentage value"
        "milliseconds, default 70ms"
        "milliseconds, default 700ms"
        "integer page count value"
        "true or false boolean value"
        "size value e.g. 8m or 16m"
        "size value e.g. 192m or 256m"
        "size value e.g. 512m or 1g"
        "float 0.xx, default is 0.75"
        "size value e.g. 2m or 4m"
        "size value e.g. 8m or 16m"
        "true or false boolean value"
        "size value e.g. 64k or 128k"
        "integer threshold, default 10000"
        "speed, speed-profile, space, everything"
        "true or false boolean value"
        "true or false boolean value"
        "int:jit, int:fast, int:portable"
        "threshold in milliseconds value"
        "integer thread count value"
        "integer thread count value"
        "true or false boolean value"
        "libdvm.so or libart.so path"
        "libart.so runtime library path"
        "float 0-10 scale, 0=disabled"
        "float 0-10 scale, 0=disabled"
        "float 0-10 scale, 0=disabled"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "true or false boolean value"
        "rotation mode integer 0-3"
        "true or false boolean value"
        "integer UI mode identifier"
        "float scale, default is 1.0"
        "DPI value integer override"
        "DP value smallest width"
    )
    
    AM_PROPS_RISK=(
        "MEDIUM" "MEDIUM" "LOW" "MEDIUM" "MEDIUM" "MEDIUM" "MEDIUM" "HIGH" "MEDIUM" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "MEDIUM" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "HIGH" "HIGH"
        "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH"
        "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "HIGH" "MEDIUM" "MEDIUM" "MEDIUM"
        "MEDIUM" "LOW" "MEDIUM" "MEDIUM" "MEDIUM" "LOW" "MEDIUM" "MEDIUM" "LOW" "LOW"
        "MEDIUM" "LOW" "LOW" "MEDIUM" "LOW" "LOW" "LOW" "LOW" "LOW" "HIGH"
        "HIGH" "LOW" "LOW" "LOW" "MEDIUM" "LOW" "LOW" "LOW" "LOW" "LOW"
        "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "LOW" "MEDIUM" "LOW"
        "MEDIUM" "MEDIUM"
    )
}

fe_am_stack_analysis() {
    fe_print_title "Activity stack analysis" "$C_M"
    
    fe_print_subtitle "Activity stack list"
    local stacks
    stacks="$(fe_safe_exec "am stack list")"
    if [[ -n "${stacks}" ]]; then
        printf "%s\n" "${stacks}"
    else
        printf "${C_GR}am stack command not available on this Android version.${C_N}\n"
    fi
    
    fe_print_subtitle "Currently resumed activity"
    fe_safe_exec "dumpsys activity activities | grep -A3 'mResumedActivity\\|mFocusedActivity' | head -10"
}

fe_am_oom_analysis() {
    fe_print_title "OOM and memory analysis" "$C_M"
    
    fe_print_subtitle "OOM adjustment thresholds"
    local adj_props=(
        "FOREGROUND_APP_ADJ" "VISIBLE_APP_ADJ" "PERCEPTIBLE_APP_ADJ"
        "HEAVY_WEIGHT_APP_ADJ" "SERVICE_ADJ" "HOME_APP_ADJ"
        "PREVIOUS_APP_ADJ" "BACKUP_APP_ADJ" "HIDDEN_APP_MIN_ADJ"
        "CACHED_APP_MIN_ADJ" "EMPTY_APP_ADJ"
    )
    
    for prop in "${adj_props[@]}"; do
        local val
        val="$(fe_safe_exec "getprop ro.${prop}")"
        printf "  ro.%s = ${C_O}%s${C_N}\n" "${prop}" "${val:-<not set>}"
    done
    
    fe_print_subtitle "Low memory killer daemon configuration"
    local lmk_props=("low" "medium" "critical" "kill_heaviest_task" "swap_free_low_percentage" "psi_partial_stall_ms" "psi_complete_stall_ms")
    for prop in "${lmk_props[@]}"; do
        local val
        val="$(fe_safe_exec "getprop ro.lmk.${prop}")"
        printf "  ro.lmk.%s = ${C_O}%s${C_N}\n" "${prop}" "${val:-<not set>}"
    done
    
    fe_print_subtitle "Kernel LMK parameters"
    if [[ -r "/sys/module/lowmemorykiller/parameters/minfree" ]]; then
        printf "  minfree: ${C_O}%s${C_N}\n" "$(cat /sys/module/lowmemorykiller/parameters/minfree)"
    else
        printf "  ${C_GR}minfree: Using userspace lmkd daemon${C_N}\n"
    fi
    
    if [[ -r "/sys/module/lowmemorykiller/parameters/adj" ]]; then
        printf "  adj: ${C_O}%s${C_N}\n" "$(cat /sys/module/lowmemorykiller/parameters/adj)"
    fi
}

fe_am_service_analysis() {
    fe_print_title "Running services analysis" "$C_M"
    
    fe_print_subtitle "Foreground services"
    fe_safe_exec "dumpsys activity services | grep -B1 -A3 'isForeground=true' | head -40"
    
    fe_print_subtitle "Active services summary"
    fe_safe_exec "dumpsys activity services | grep '^  Service' | head -30"
}

fe_system_integrity() {
    fe_print_title "System integrity check" "$C_P"
    
    printf "${C_W}Build fingerprint:${C_N} %s\n" "$(fe_safe_exec "getprop ro.build.fingerprint")"
    printf "${C_W}Security patch level:${C_N} %s\n" "$(fe_safe_exec "getprop ro.build.version.security_patch")"
    printf "${C_W}Bootloader verified state:${C_N} %s\n" "$(fe_safe_exec "getprop ro.boot.verifiedbootstate")"
    printf "${C_W}DM-Verity mode:${C_N} %s\n" "$(fe_safe_exec "getprop ro.boot.veritymode")"
    printf "${C_W}Debuggable flag:${C_N} %s\n" "$(fe_safe_exec "getprop ro.debuggable")"
    printf "${C_W}Build signature tags:${C_N} %s\n" "$(fe_safe_exec "getprop ro.build.tags")"
    printf "${C_W}Project Treble support:${C_N} %s\n" "$(fe_safe_exec "getprop ro.treble.enabled")"
    printf "${C_W}Dynamic partitions:${C_N} %s\n" "$(fe_safe_exec "getprop ro.boot.dynamic_partitions")"
    printf "${C_W}Virtual A/B updates:${C_N} %s\n" "$(fe_safe_exec "getprop ro.virtual_ab.enabled")"
    printf "${C_W}Kernel version:${C_N} %s\n" "$(fe_safe_exec "uname -r")"
    
    fe_print_subtitle "SafetyNet and Play Integrity indicators"
    local issues=0
    
    if [[ "$(fe_safe_exec "getprop ro.boot.verifiedbootstate")" == "green" ]]; then
        printf "  ${C_G}PASS${C_N} Verified boot state is green\n"
    else
        printf "  ${C_R}FAIL${C_N} Verified boot state not green\n"
        issues=$((issues+1))
    fi
    
    if [[ "$(fe_safe_exec "getprop ro.debuggable")" == "0" ]]; then
        printf "  ${C_G}PASS${C_N} Device is not debuggable\n"
    else
        printf "  ${C_R}FAIL${C_N} Device is marked as debuggable\n"
        issues=$((issues+1))
    fi
    
    if [[ "$(fe_safe_exec "getprop ro.build.tags")" == *"release-keys"* ]]; then
        printf "  ${C_G}PASS${C_N} Build signed with release keys\n"
    else
        printf "  ${C_R}FAIL${C_N} Build not signed with release keys\n"
        issues=$((issues+1))
    fi
    
    printf "\n  ${C_W}Total integrity issues:${C_N} ${C_O}%d${C_N}\n" "${issues}"
}

fe_selinux_control() {
    fe_print_title "SELinux control" "$C_P"
    
    printf "${C_W}Current status:${C_N} %s\n" "${FE_SELINUX}"
    printf "${C_W}Policy version:${C_N} %s\n" "$(cat /sys/fs/selinux/policyvers 2>/dev/null || echo "Unknown")"
    
    if ! fe_check_write; then
        return
    fi
    
    printf "\n"
    printf "${C_R}WARNING: Disabling SELinux significantly reduces system security.${C_N}\n"
    printf "${C_R}Only perform this action in isolated research environments.${C_N}\n"
    printf "\n"
    
    printf "  1. Set SELinux to Permissive mode (temporary)\n"
    printf "  2. Set SELinux to Enforcing mode (temporary)\n"
    printf "  3. View recent AVC denial messages\n"
    printf "  4. View SELinux boolean settings (first 40)\n"
    printf "  0. Return to previous menu\n\n"
    
    read -rp "  ${C_W}Select option:${C_N} " choice
    
    case "${choice}" in
        1)
            printf "  ${C_Y}Setting SELinux to Permissive mode...${C_N}\n"
            fe_safe_exec_noerr "setenforce 0"
            FE_SELINUX="$(fe_safe_exec "getenforce")"
            printf "  New status: %s\n" "${FE_SELINUX}"
            ;;
        2)
            fe_safe_exec_noerr "setenforce 1"
            FE_SELINUX="$(fe_safe_exec "getenforce")"
            printf "  New status: %s\n" "${FE_SELINUX}"
            ;;
        3)
            printf "  Recent AVC denial messages:\n"
            fe_safe_exec "dmesg | grep -i 'avc: denied' | tail -30" || printf "  ${C_GR}No denials found or dmesg not accessible${C_N}\n"
            ;;
        4)
            printf "  SELinux booleans:\n"
            fe_safe_exec "getsebool -a | head -40" || printf "  ${C_GR}getsebool command not available${C_N}\n"
            ;;
        0) return ;;
        *) printf "  ${C_R}Invalid option selected.${C_N}\n" ;;
    esac
}

fe_restore_backup() {
    fe_print_title "Restore property backup" "$C_P"
    
    if ! fe_check_write; then
        return
    fi
    
    local backups
    backups="$(ls -1 "${FE_BACKUP}"/props_*.bak 2>/dev/null)"
    
    if [[ -z "${backups}" ]]; then
        printf "${C_GR}No backup files found in %s${C_N}\n" "${FE_BACKUP}"
        return
    fi
    
    printf "${C_W}Available backup files:${C_N}\n"
    local i=1
    local -a backup_array=()
    while IFS= read -r bk; do
        printf "  %d) %s\n" "${i}" "$(basename "${bk}")"
        backup_array+=("${bk}")
        i=$((i+1))
    done <<< "${backups}"
    
    printf "\n"
    read -rp "${C_W}Select backup to restore (0=cancel): ${C_N}" sel
    
    if [[ "${sel}" == "0" || -z "${sel}" ]]; then
        printf "${C_GR}Restore operation cancelled.${C_N}\n"
        return
    fi
    
    local idx=$((sel-1))
    local selected="${backup_array[${idx}]:-}"
    
    if [[ -z "${selected}" ]]; then
        printf "${C_R}Invalid selection number.${C_N}\n"
        return
    fi
    
    printf "${C_Y}Restoring properties from: %s${C_N}\n" "${selected}"
    
    while IFS='=' read -r prop value; do
        [[ -z "${prop}" || "${prop}" == \#* ]] && continue
        printf "  Restoring ${C_T}%s${C_N} = ${C_O}%s${C_N}\n" "${prop}" "${value}"
        if [[ "${prop}" == ro.* ]]; then
            fe_safe_exec_noerr "resetprop '${prop}' '${value}'"
        else
            fe_safe_exec_noerr "setprop '${prop}' '${value}'"
        fi
    done < "${selected}"
    
    printf "\n${C_G}Property restore operation completed.${C_N}\n"
}

fe_quick_collect() {
    fe_print_title "Quick collect all modules" "$C_B"
    fe_collect_sf
    fe_collect_af
    fe_collect_if
    fe_collect_am
    printf "\n${C_G}All module dumps saved to: %s${C_N}\n" "${FE_LOGDIR}"
}

fe_view_logs() {
    fe_print_title "Log directory contents" "$C_GR"
    printf "${C_W}Location:${C_N} %s\n\n" "${FE_LOGDIR}"
    ls -la "${FE_LOGDIR}" 2>/dev/null || printf "${C_GR}Directory is empty or not accessible.${C_N}\n"
}

fe_menu_sf() {
    while true; do
        fe_print_title "SurfaceFlinger module" "$C_C"
        
        printf "  ${C_O}1${C_N}. Collect full state dump to file\n"
        printf "  ${C_O}2${C_N}. Browse all properties (read-only list)\n"
        printf "  ${C_O}3${C_N}. Tune properties by number selection\n"
        printf "  ${C_O}4${C_N}. Binder service codes reference\n"
        printf "  ${C_O}5${C_N}. Layer composition analysis\n"
        printf "  ${C_O}6${C_N}. VSYNC and frame timing analysis\n"
        printf "  ${C_O}0${C_N}. Return to main menu\n\n"
        
        read -rp "  ${C_W}Select option:${C_N} " opt
        
        case "${opt}" in
            1) fe_collect_sf ;;
            2) fe_list_generic_props "SurfaceFlinger properties" SF_PROPS SF_PROPS_DESC SF_PROPS_VALUES SF_PROPS_RISK ;;
            3) fe_tune_generic_props "SurfaceFlinger property tuner" SF_PROPS SF_PROPS_DESC SF_PROPS_VALUES SF_PROPS_RISK ;;
            4) fe_sf_service_codes ;;
            5) fe_sf_layer_analysis ;;
            6) fe_safe_exec "dumpsys SurfaceFlinger timestats | head -25" || printf "${C_GR}Timestats not available${C_N}\n" ;;
            0) break ;;
            *) printf "  ${C_R}Invalid option selected.${C_N}\n" ;;
        esac
        
        fe_pause
    done
}

fe_menu_af() {
    while true; do
        fe_print_title "AudioFlinger module" "$C_C"
        
        printf "  ${C_O}1${C_N}. Collect full state dump to file\n"
        printf "  ${C_O}2${C_N}. Browse all properties (read-only list)\n"
        printf "  ${C_O}3${C_N}. Tune properties by number selection\n"
        printf "  ${C_O}4${C_N}. Audio thread analysis\n"
        printf "  ${C_O}5${C_N}. Audio HAL information\n"
        printf "  ${C_O}0${C_N}. Return to main menu\n\n"
        
        read -rp "  ${C_W}Select option:${C_N} " opt
        
        case "${opt}" in
            1) fe_collect_af ;;
            2) fe_list_generic_props "AudioFlinger properties" AF_PROPS AF_PROPS_DESC AF_PROPS_VALUES AF_PROPS_RISK ;;
            3) fe_tune_generic_props "AudioFlinger property tuner" AF_PROPS AF_PROPS_DESC AF_PROPS_VALUES AF_PROPS_RISK ;;
            4) fe_af_thread_analysis ;;
            5) fe_safe_exec "dumpsys media.audio_flinger | grep -A15 'HAL'" ;;
            0) break ;;
            *) printf "  ${C_R}Invalid option selected.${C_N}\n" ;;
        esac
        
        fe_pause
    done
}

fe_menu_if() {
    while true; do
        fe_print_title "InputFlinger module" "$C_C"
        
        printf "  ${C_O}1${C_N}. Collect full state dump to file\n"
        printf "  ${C_O}2${C_N}. Browse all properties (read-only list)\n"
        printf "  ${C_O}3${C_N}. Tune properties by number selection\n"
        printf "  ${C_O}4${C_N}. List connected input devices\n"
        printf "  ${C_O}5${C_N}. Input dispatcher state view\n"
        printf "  ${C_O}6${C_N}. Monitor input events (real-time)\n"
        printf "  ${C_O}0${C_N}. Return to main menu\n\n"
        
        read -rp "  ${C_W}Select option:${C_N} " opt
        
        case "${opt}" in
            1) fe_collect_if ;;
            2) fe_list_generic_props "InputFlinger properties" IF_PROPS IF_PROPS_DESC IF_PROPS_VALUES IF_PROPS_RISK ;;
            3) fe_tune_generic_props "InputFlinger property tuner" IF_PROPS IF_PROPS_DESC IF_PROPS_VALUES IF_PROPS_RISK ;;
            4) fe_if_device_list ;;
            5) fe_if_dispatcher_state ;;
            6) fe_if_monitor ;;
            0) break ;;
            *) printf "  ${C_R}Invalid option selected.${C_N}\n" ;;
        esac
        
        [[ "${opt}" != "6" ]] && fe_pause
    done
}

fe_menu_am() {
    while true; do
        fe_print_title "ActivityManager module" "$C_C"
        
        printf "  ${C_O}1${C_N}. Collect full state dump to file\n"
        printf "  ${C_O}2${C_N}. Browse all properties (read-only list)\n"
        printf "  ${C_O}3${C_N}. Tune properties by number selection\n"
        printf "  ${C_O}4${C_N}. Activity stack analysis\n"
        printf "  ${C_O}5${C_N}. OOM and memory analysis\n"
        printf "  ${C_O}6${C_N}. Running services analysis\n"
        printf "  ${C_O}7${C_N}. View current foreground activity\n"
        printf "  ${C_O}0${C_N}. Return to main menu\n\n"
        
        read -rp "  ${C_W}Select option:${C_N} " opt
        
        case "${opt}" in
            1) fe_collect_am ;;
            2) fe_list_generic_props "ActivityManager properties" AM_PROPS AM_PROPS_DESC AM_PROPS_VALUES AM_PROPS_RISK ;;
            3) fe_tune_generic_props "ActivityManager property tuner" AM_PROPS AM_PROPS_DESC AM_PROPS_VALUES AM_PROPS_RISK ;;
            4) fe_am_stack_analysis ;;
            5) fe_am_oom_analysis ;;
            6) fe_am_service_analysis ;;
            7) fe_safe_exec "dumpsys activity activities | grep -A5 'mResumedActivity\\|mFocusedActivity'" ;;
            0) break ;;
            *) printf "  ${C_R}Invalid option selected.${C_N}\n" ;;
        esac
        
        fe_pause
    done
}

fe_main() {
    fe_init_sf_props
    fe_init_af_props
    fe_init_if_props
    fe_init_am_props
    
    fe_detect_root
    fe_print_header
    
    while true; do
        printf "\n"
        printf "${C_T}${C_BOLD}Main menu${C_N}\n"
        if [[ ${FE_CAN_WRITE} -eq 1 ]]; then
            printf "${C_G}Mode: Full access (root detected)${C_N}\n"
        else
            printf "${C_Y}Mode: Read-only (no root detected)${C_N}\n"
        fi
        printf "\n"
        
        printf "  ${C_O}1${C_N}. SurfaceFlinger module\n"
        printf "  ${C_O}2${C_N}. AudioFlinger module\n"
        printf "  ${C_O}3${C_N}. InputFlinger module\n"
        printf "  ${C_O}4${C_N}. ActivityManager module\n"
        printf "  ${C_O}5${C_N}. System integrity check\n"
        printf "  ${C_O}6${C_N}. SELinux control panel\n"
        printf "  ${C_O}7${C_N}. Restore property backup\n"
        printf "  ${C_O}8${C_N}. Quick collect all (read-only snapshot)\n"
        printf "  ${C_O}9${C_N}. View log directory\n"
        printf "  ${C_O}0${C_N}. Exit program\n\n"
        
        read -rp "  ${C_W}Select module:${C_N} " choice
        
        case "${choice}" in
            1) fe_menu_sf ;;
            2) fe_menu_af ;;
            3) fe_menu_if ;;
            4) fe_menu_am ;;
            5) fe_system_integrity ;;
            6) fe_selinux_control ;;
            7) fe_restore_backup ;;
            8) fe_quick_collect ;;
            9) fe_view_logs ;;
            0)
                printf "\n${C_T}Thank you for using FlingerExplorer.${C_N}\n"
                printf "${C_GR}All logs and backups preserved at: %s${C_N}\n" "${FE_LOGDIR}"
                exit 0
                ;;
            *) printf "  ${C_R}Invalid option selected.${C_N}\n" ;;
        esac
    done
}

fe_main "$@"

