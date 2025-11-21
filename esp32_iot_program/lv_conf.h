/**
 * LVGL Configuration for ESP32 IoT Display
 */

#ifndef LV_CONF_H
#define LV_CONF_H

#include <stdint.h>

/* Color settings */
#define LV_COLOR_DEPTH 16
#define LV_COLOR_16_SWAP 0

/* Memory settings */
#define LV_MEM_CUSTOM 0
#define LV_MEM_SIZE (48 * 1024U)

/* Display settings */
#define LV_HOR_RES_MAX 172
#define LV_VER_RES_MAX 320
#define LV_DPI_DEF 130

/* Rendering */
#define LV_USE_REFR_DEBUG 0
#define LV_REFR_PERIOD 33

/* Input device settings */
#define LV_INDEV_DEF_READ_PERIOD 30

/* Feature usage */
#define LV_USE_ANIMATION 1
#define LV_USE_SHADOW 1
#define LV_USE_BLEND_MODES 1
#define LV_USE_OPA_SCALE 1
#define LV_USE_IMG_TRANSFORM 1
#define LV_USE_GROUP 1
#define LV_USE_GPU 0
#define LV_USE_FILESYSTEM 0
#define LV_USE_USER_DATA 1

/* Font usage */
#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_18 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_24 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_MONTSERRAT_32 0
#define LV_FONT_MONTSERRAT_36 0
#define LV_FONT_MONTSERRAT_40 0
#define LV_FONT_MONTSERRAT_48 0

#define LV_FONT_DEFAULT &lv_font_montserrat_16

/* Widgets */
#define LV_USE_ARC 1
#define LV_USE_BAR 1
#define LV_USE_BTN 1
#define LV_USE_BTNMATRIX 1
#define LV_USE_CANVAS 1
#define LV_USE_CHECKBOX 1
#define LV_USE_DROPDOWN 1
#define LV_USE_IMG 1
#define LV_USE_LABEL 1
#define LV_USE_LINE 1
#define LV_USE_ROLLER 1
#define LV_USE_SLIDER 1
#define LV_USE_SWITCH 1
#define LV_USE_TEXTAREA 1
#define LV_USE_TABLE 1

/* Themes */
#define LV_USE_THEME_DEFAULT 1
#define LV_USE_THEME_BASIC 1

/* Logging */
#define LV_USE_LOG 1
#if LV_USE_LOG
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN
#define LV_LOG_PRINTF 1
#endif

/* Others */
#define LV_SPRINTF_CUSTOM 0
#define LV_TICK_CUSTOM 1
#define LV_USE_PERF_MONITOR 0
#define LV_USE_MEM_MONITOR 0

#endif /*LV_CONF_H*/
