#!/bin/sh
# T92P board adapter, run as root by its init script.
# T92P 板级适配脚本由初始化脚本以 root 执行。
set -eu
light_pwm=/sys/class/pwm/pwmchip0/pwm0
light_chip=/sys/class/pwm/pwmchip0
ir_gpio=/sys/class/gpio/gpio24
rgb_camera=/dev/video31
ir_camera=/dev/v4l/by-path/platform-rkisp-vir0-video-index0

board_check() {
    [ "$(readlink -f "$light_chip/device")" = /sys/devices/platform/20700000.pwm ] &&
        grep -q pwm-light /proc/device-tree/sys-light-pwm/compatible || return 1
    # Check the vendor IR pin offset/polarity before touching GPIO0_D0.
    # 操作 GPIO0_D0 前先核对厂商红外引脚偏移与极性。
    case "$(od -An -tx1 /proc/device-tree/sys-dev/ir_led_pin | tr -d ' \n')" in
        ????????0000001800000000) ;;
        *) return 1 ;;
    esac
}

white_off() {
    if [ -d "$light_pwm" ]; then
        # An exported but disabled PWM has no period until first configured.
        # The driver rejects enable and duty writes until the period is set.
        if [ "$(cat "$light_pwm/period")" = 0 ] && [ "$(cat "$light_pwm/enable")" = 0 ]; then
            return 0
        fi
        white_failed=0
        echo 0 > "$light_pwm/enable" || white_failed=1
        echo 0 > "$light_pwm/duty_cycle" || white_failed=1
        return "$white_failed"
    fi
}

ir_off() {
    [ -d "$ir_gpio" ] || echo 24 > /sys/class/gpio/export || return 1
    revoked=0
    chown root:root "$ir_gpio/value" || revoked=1
    echo low > "$ir_gpio/direction" || return 1
    return "$revoked"
}

rgb_off() {
    # Vendor rgb_led_set_ctrl() drives the selected color high and the other
    # 厂商 rgb_led_set_ctrl() 将选中颜色拉高，其他颜色拉低。
    # colors low. All three low is off; no relay/door GPIO is touched.
    # 三个颜色全低即关闭；不操作继电器或门控 GPIO。
    rgb_failed=0
    for entry in rgb_red_pin:200:0000000800000001 rgb_green_pin:202:0000000a00000001 rgb_blue_pin:203:0000000b00000000; do
        pin_name=${entry%%:*}; remaining=${entry#*:}
        gpio=${remaining%%:*}; suffix=${remaining#*:}
        raw=$(od -An -tx1 "/proc/device-tree/sys-dev/$pin_name" | tr -d ' \n')
        pin=/sys/class/gpio/gpio$gpio
        if [ "${raw#????????}" != "$suffix" ] ||
            { [ ! -d "$pin" ] && ! echo "$gpio" > /sys/class/gpio/export; }; then
            rgb_failed=1
            continue
        fi
        chown root:root "$pin/value" || rgb_failed=1
        echo low > "$pin/direction" || rgb_failed=1
    done
    return "$rgb_failed"
}

case "${1:-status}" in
    prepare)
        case "${2:-}" in ''|rgbir) ;; *) exit 2 ;; esac
        board_check || { echo 'Unsupported white/IR light wiring' >&2; exit 1; }
        ir_off
        rgb_off
        [ -d "$light_pwm" ] || echo 0 > "$light_chip/export"
        white_off
        echo 1000000 > "$light_pwm/period"
        echo normal > "$light_pwm/polarity"
        chown root:video "$light_pwm/duty_cycle" "$light_pwm/enable"
        chmod 660 "$light_pwm/duty_cycle" "$light_pwm/enable"
        if [ "${2:-}" = rgbir ]; then
            [ "$(cat "$ir_gpio/active_low")" = 0 ]
            chmod 0644 "$ir_gpio/value"
            chown hiface:root "$ir_gpio/value"
            for gpio in 200 202 203; do
                pin=/sys/class/gpio/gpio$gpio
                [ "$(cat "$pin/active_low")" = 0 ]
                chmod 0644 "$pin/value"
                chown hiface:root "$pin/value"
            done
        fi
        # Stdout carries only the settings for the unprivileged Demo.
        printf '%s\n' "HIFACE_LIGHT_PWM_PATH=$light_pwm" "HIFACE_LIGHT_CAMERA_DEVICE=$rgb_camera"
        if [ "${2:-}" = rgbir ]; then
            printf '%s\n' "HIFACE_IR_LIGHT_GPIO_VALUE=$ir_gpio/value" "HIFACE_IR_LIGHT_CAMERA_DEVICE=$ir_camera"
            printf '%s\n' 'HIFACE_RGBIR_LED_RED=/sys/class/gpio/gpio200/value' \
                'HIFACE_RGBIR_LED_GREEN=/sys/class/gpio/gpio202/value' 'HIFACE_RGBIR_LED_BLUE=/sys/class/gpio/gpio203/value'
        fi
        ;;
    off)
        board_check
        failed=0
        ir_off || failed=1
        white_off || failed=1
        rgb_off || failed=1
        exit "$failed"
        ;;
    status)
        if [ -d "$light_pwm" ]; then
            for item in period duty_cycle enable; do
                printf 'white_%s=' "$item"; cat "$light_pwm/$item"
            done
        else echo white_pwm=unconfigured; fi
        if [ -e "$ir_gpio/value" ]; then
            printf 'ir_gpio='; cat "$ir_gpio/value"
        else echo ir_gpio=unconfigured; fi
        for channel in red:200 green:202 blue:203; do
            pin=/sys/class/gpio/gpio${channel#*:}/value
            printf 'status_%s=' "${channel%%:*}"
            if [ -e "$pin" ]; then cat "$pin"; else echo unconfigured; fi
        done
        ;;
    *) echo 'Usage: t92p-lighting.sh {prepare [rgbir]|off|status}' >&2; exit 2 ;;
esac
