/*
 * ESP32 IoT BLE Device with LCD Control
 * Commands via BLE:
 * - Set screen color (RGB565 format)
 * - Display text on screen
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_main.h"
#include "esp_gatt_common_api.h"

// LCD includes
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_lcd_panel_ops.h"
#include "driver/gpio.h"
#include "driver/spi_master.h"

// LVGL includes
#include "lvgl.h"

// Pin definitions for ST7789 display
#define LCD_HOST       SPI2_HOST
#define LCD_PIXEL_CLOCK_HZ (40 * 1000 * 1000)
#define LCD_BK_LIGHT_ON_LEVEL  1
#define LCD_BK_LIGHT_OFF_LEVEL !LCD_BK_LIGHT_ON_LEVEL

#define PIN_NUM_MOSI   6
#define PIN_NUM_CLK    7
#define PIN_NUM_CS     14
#define PIN_NUM_DC     15
#define PIN_NUM_RST    21
#define PIN_NUM_BK_LIGHT 22

// Display size for 1.47" ST7789 (rotated 90 degrees)
#define LCD_H_RES      320
#define LCD_V_RES      172

static const char *TAG = "BLE_LCD";

// RGB565 color definitions
#define COLOR_BLACK   0x0000
#define COLOR_WHITE   0xFFFF
#define COLOR_RED     0xF800
#define COLOR_GREEN   0x07E0
#define COLOR_BLUE    0x001F
#define COLOR_YELLOW  0xFFE0
#define COLOR_CYAN    0x07FF
#define COLOR_MAGENTA 0xF81F

// Global LCD handle
static esp_lcd_panel_handle_t panel_handle = NULL;
static uint16_t current_color = COLOR_BLACK;

// LVGL globals
static lv_disp_draw_buf_t disp_buf;
static lv_disp_drv_t disp_drv;
static lv_color_t *buf1 = NULL;
static lv_color_t *buf2 = NULL;
static lv_obj_t *text_label = NULL;
static lv_obj_t *screen_obj = NULL;

// BLE Definitions
#define GATTS_SERVICE_UUID   0x00FF
#define GATTS_CHAR_UUID_COLOR 0xFF01
#define GATTS_CHAR_UUID_TEXT  0xFF02
#define GATTS_NUM_HANDLE     8

#define DEVICE_NAME          "ESP32_IoT_Display"
#define GATTS_DEMO_CHAR_VAL_LEN_MAX 100

static uint8_t adv_config_done = 0;
#define ADV_CONFIG_FLAG      (1 << 0)
#define SCAN_RSP_CONFIG_FLAG (1 << 1)

static uint8_t service_uuid[16] = {
    0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
    0x00, 0x10, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00,
};

static esp_ble_adv_data_t adv_data = {
    .set_scan_rsp = false,
    .include_name = true,
    .include_txpower = true,
    .min_interval = 0x0006,
    .max_interval = 0x0010,
    .appearance = 0x00,
    .manufacturer_len = 0,
    .p_manufacturer_data = NULL,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = sizeof(service_uuid),
    .p_service_uuid = service_uuid,
    .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
};

static esp_ble_adv_params_t adv_params = {
    .adv_int_min = 0x20,
    .adv_int_max = 0x40,
    .adv_type = ADV_TYPE_IND,
    .own_addr_type = BLE_ADDR_TYPE_PUBLIC,
    .channel_map = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

struct gatts_profile_inst {
    esp_gatts_cb_t gatts_cb;
    uint16_t gatts_if;
    uint16_t app_id;
    uint16_t conn_id;
    uint16_t service_handle;
    esp_gatt_srvc_id_t service_id;
    uint16_t char_handle_color;
    uint16_t char_handle_text;
    esp_bt_uuid_t char_uuid_color;
    esp_bt_uuid_t char_uuid_text;
    esp_gatt_perm_t perm;
    esp_gatt_char_prop_t property;
    uint16_t descr_handle;
    esp_bt_uuid_t descr_uuid;
};

static void gatts_profile_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param);

#define PROFILE_NUM 1
#define PROFILE_APP_IDX 0

static struct gatts_profile_inst gl_profile_tab[PROFILE_NUM] = {
    [PROFILE_APP_IDX] = {
        .gatts_cb = gatts_profile_event_handler,
        .gatts_if = ESP_GATT_IF_NONE,
    },
};

// LVGL Display Flush Callback
static void lvgl_flush_cb(lv_disp_drv_t *drv, const lv_area_t *area, lv_color_t *color_map)
{
    esp_lcd_panel_handle_t panel = (esp_lcd_panel_handle_t) drv->user_data;
    int offsetx1 = area->x1;
    int offsetx2 = area->x2;
    int offsety1 = area->y1;
    int offsety2 = area->y2;
    // Pass the draw buffer to the driver
    esp_lcd_panel_draw_bitmap(panel, offsetx1, offsety1, offsetx2 + 1, offsety2 + 1, color_map);
    lv_disp_flush_ready(drv);
}

// LVGL Tick Callback
#if LV_TICK_CUSTOM
static uint32_t lvgl_tick_get_cb(void)
{
    return esp_timer_get_time() / 1000;
}
#endif

// LVGL Task
static void lvgl_task(void *pvParameter)
{
    ESP_LOGI(TAG, "LVGL task started");
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10));
        lv_timer_handler();
    }
}

// LCD Helper Functions
void lcd_fill_rect(esp_lcd_panel_handle_t panel_handle, int x, int y, int width, int height, uint16_t color)
{
    uint16_t *line_buf = malloc(width * sizeof(uint16_t));
    if (line_buf == NULL) {
        ESP_LOGE(TAG, "Failed to allocate line buffer");
        return;
    }

    for (int i = 0; i < width; i++) {
        line_buf[i] = color;
    }

    for (int i = 0; i < height; i++) {
        esp_lcd_panel_draw_bitmap(panel_handle, x, y + i, x + width, y + i + 1, line_buf);
    }

    free(line_buf);
}

void lcd_clear_screen(uint16_t color)
{
    if (screen_obj) {
        // Extract RGB565 components
        uint8_t r5 = (color >> 11) & 0x1F;
        uint8_t g6 = (color >> 5) & 0x3F;
        uint8_t b5 = color & 0x1F;

        // Convert RGB565 to RGB888 for LVGL
        uint8_t r8 = (r5 << 3) | (r5 >> 2);  // Replicate top bits
        uint8_t g8 = (g6 << 2) | (g6 >> 4);
        uint8_t b8 = (b5 << 3) | (b5 >> 2);

        // Create 24-bit RGB888 hex value for lv_color_hex()
        uint32_t rgb888 = (r8 << 16) | (g8 << 8) | b8;

        lv_color_t lv_color = lv_color_hex(rgb888);
        lv_obj_set_style_bg_color(screen_obj, lv_color, 0);
        current_color = color;

        // Force LVGL to refresh the display
        lv_refr_now(NULL);

        ESP_LOGI(TAG, "Screen cleared to color: RGB565=0x%04X, RGB888=0x%06X", color, (unsigned int)rgb888);
    }
}

void lcd_display_text(const char *text)
{
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "┌─────────────────────────────────┐");
    ESP_LOGI(TAG, "│ DISPLAYING TEXT WITH LVGL       │");
    ESP_LOGI(TAG, "├─────────────────────────────────┤");
    ESP_LOGI(TAG, "│ Text: '%s'", text);
    ESP_LOGI(TAG, "│ Length: %d chars", (int)strlen(text));
    ESP_LOGI(TAG, "└─────────────────────────────────┘");
    ESP_LOGI(TAG, "");

    if (text_label != NULL) {
        // Update the label text
        lv_label_set_text(text_label, text);

        // Make sure label is visible and centered
        lv_obj_clear_flag(text_label, LV_OBJ_FLAG_HIDDEN);
        lv_obj_center(text_label);

        // Force LVGL to refresh the display
        lv_refr_now(NULL);

        ESP_LOGI(TAG, "Text displayed successfully using LVGL!");
        ESP_LOGI(TAG, "Label text: '%s'", lv_label_get_text(text_label));
        ESP_LOGI(TAG, "");
    } else {
        ESP_LOGW(TAG, "Text label not initialized!");
    }
}

// BLE Event Handlers
static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
        adv_config_done &= (~ADV_CONFIG_FLAG);
        if (adv_config_done == 0) {
            esp_ble_gap_start_advertising(&adv_params);
        }
        break;
    case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
        if (param->adv_start_cmpl.status != ESP_BT_STATUS_SUCCESS) {
            ESP_LOGE(TAG, "Advertising start failed");
        } else {
            ESP_LOGI(TAG, "");
            ESP_LOGI(TAG, "╔════════════════════════════════════════════╗");
            ESP_LOGI(TAG, "║  BLE ADVERTISING STARTED                   ║");
            ESP_LOGI(TAG, "╚════════════════════════════════════════════╝");
            ESP_LOGI(TAG, "  Device is now visible to Flutter app!");
            ESP_LOGI(TAG, "  Look for: 'ESP32_IoT_Display'");
            ESP_LOGI(TAG, "  Service UUID: 0x00FF");
            ESP_LOGI(TAG, "");
        }
        break;
    case ESP_GAP_BLE_ADV_STOP_COMPLETE_EVT:
        if (param->adv_stop_cmpl.status != ESP_BT_STATUS_SUCCESS) {
            ESP_LOGE(TAG, "Advertising stop failed");
        } else {
            ESP_LOGI(TAG, "Stop adv successfully");
        }
        break;
    case ESP_GAP_BLE_UPDATE_CONN_PARAMS_EVT:
        ESP_LOGI(TAG, "=== CONNECTION PARAMS UPDATED ===");
        ESP_LOGI(TAG, "  Status: %d", param->update_conn_params.status);
        ESP_LOGI(TAG, "  Min interval: %d", param->update_conn_params.min_int);
        ESP_LOGI(TAG, "  Max interval: %d", param->update_conn_params.max_int);
        ESP_LOGI(TAG, "  Latency: %d", param->update_conn_params.latency);
        ESP_LOGI(TAG, "  Timeout: %d", param->update_conn_params.timeout);
        ESP_LOGI(TAG, "================================");
        break;
    default:
        break;
    }
}

static void gatts_profile_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param)
{
    switch (event) {
    case ESP_GATTS_REG_EVT:
        ESP_LOGI(TAG, "GATT server registered, app_id %04x", param->reg.app_id);
        gl_profile_tab[PROFILE_APP_IDX].service_id.is_primary = true;
        gl_profile_tab[PROFILE_APP_IDX].service_id.id.inst_id = 0x00;
        gl_profile_tab[PROFILE_APP_IDX].service_id.id.uuid.len = ESP_UUID_LEN_16;
        gl_profile_tab[PROFILE_APP_IDX].service_id.id.uuid.uuid.uuid16 = GATTS_SERVICE_UUID;

        esp_ble_gap_set_device_name(DEVICE_NAME);
        esp_ble_gap_config_adv_data(&adv_data);
        esp_ble_gatts_create_service(gatts_if, &gl_profile_tab[PROFILE_APP_IDX].service_id, GATTS_NUM_HANDLE);
        break;

    case ESP_GATTS_CREATE_EVT:
        ESP_LOGI(TAG, "Service created, handle %d", param->create.service_handle);
        gl_profile_tab[PROFILE_APP_IDX].service_handle = param->create.service_handle;
        gl_profile_tab[PROFILE_APP_IDX].char_uuid_color.len = ESP_UUID_LEN_16;
        gl_profile_tab[PROFILE_APP_IDX].char_uuid_color.uuid.uuid16 = GATTS_CHAR_UUID_COLOR;

        esp_ble_gatts_start_service(gl_profile_tab[PROFILE_APP_IDX].service_handle);

        // Add color characteristic
        esp_ble_gatts_add_char(gl_profile_tab[PROFILE_APP_IDX].service_handle,
                              &gl_profile_tab[PROFILE_APP_IDX].char_uuid_color,
                              ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
                              ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_WRITE,
                              NULL, NULL);
        break;

    case ESP_GATTS_ADD_CHAR_EVT:
        ESP_LOGI(TAG, "Characteristic added, handle %d", param->add_char.attr_handle);

        if (param->add_char.char_uuid.uuid.uuid16 == GATTS_CHAR_UUID_COLOR) {
            gl_profile_tab[PROFILE_APP_IDX].char_handle_color = param->add_char.attr_handle;

            // Now add text characteristic
            gl_profile_tab[PROFILE_APP_IDX].char_uuid_text.len = ESP_UUID_LEN_16;
            gl_profile_tab[PROFILE_APP_IDX].char_uuid_text.uuid.uuid16 = GATTS_CHAR_UUID_TEXT;

            esp_ble_gatts_add_char(gl_profile_tab[PROFILE_APP_IDX].service_handle,
                                  &gl_profile_tab[PROFILE_APP_IDX].char_uuid_text,
                                  ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
                                  ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_WRITE,
                                  NULL, NULL);
        } else if (param->add_char.char_uuid.uuid.uuid16 == GATTS_CHAR_UUID_TEXT) {
            gl_profile_tab[PROFILE_APP_IDX].char_handle_text = param->add_char.attr_handle;
        }
        break;

    case ESP_GATTS_WRITE_EVT:
        ESP_LOGI(TAG, "=== WRITE EVENT RECEIVED ===");
        ESP_LOGI(TAG, "  Handle: %d", param->write.handle);
        ESP_LOGI(TAG, "  Value length: %d bytes", param->write.len);
        ESP_LOGI(TAG, "  Need response: %s", param->write.need_rsp ? "YES" : "NO");

        // Print hex dump of received data
        ESP_LOGI(TAG, "  Data (hex): ");
        for (int i = 0; i < param->write.len; i++) {
            printf("%02X ", param->write.value[i]);
            if ((i + 1) % 16 == 0) printf("\n              ");
        }
        printf("\n");

        if (param->write.handle == gl_profile_tab[PROFILE_APP_IDX].char_handle_color) {
            ESP_LOGI(TAG, "  -> COLOR CHARACTERISTIC");

            if (param->write.len == 2) {
                // RGB565 format (2 bytes)
                uint16_t color = (param->write.value[0] << 8) | param->write.value[1];
                ESP_LOGI(TAG, "  -> RGB565 format: 0x%04X", color);
                lcd_clear_screen(color);
            } else if (param->write.len == 6 || param->write.len == 7) {
                // Hex string format: "RRGGBB" or "#RRGGBB"
                char hex_str[8] = {0};
                memcpy(hex_str, param->write.value, param->write.len);
                hex_str[param->write.len] = '\0';

                // Skip '#' if present
                char *hex_start = (hex_str[0] == '#') ? hex_str + 1 : hex_str;

                // Parse RGB888 hex string
                uint32_t rgb888 = strtol(hex_start, NULL, 16);
                uint8_t r8 = (rgb888 >> 16) & 0xFF;
                uint8_t g8 = (rgb888 >> 8) & 0xFF;
                uint8_t b8 = rgb888 & 0xFF;

                // Convert RGB888 to RGB565
                uint16_t r5 = (r8 >> 3) & 0x1F;
                uint16_t g6 = (g8 >> 2) & 0x3F;
                uint16_t b5 = (b8 >> 3) & 0x1F;
                uint16_t color = (r5 << 11) | (g6 << 5) | b5;

                ESP_LOGI(TAG, "  -> Hex format: %s -> RGB888(0x%06X) -> RGB565(0x%04X)",
                         hex_str, (unsigned int)rgb888, color);
                ESP_LOGI(TAG, "     RGB888: R=%d, G=%d, B=%d", r8, g8, b8);
                ESP_LOGI(TAG, "     RGB565: R=%d, G=%d, B=%d", r5, g6, b5);
                lcd_clear_screen(color);
            } else {
                ESP_LOGW(TAG, "  -> ERROR: Invalid color data length: %d (expected 2 for RGB565 or 6/7 for hex)", param->write.len);
            }
        } else if (param->write.handle == gl_profile_tab[PROFILE_APP_IDX].char_handle_text) {
            ESP_LOGI(TAG, "  -> TEXT CHARACTERISTIC");
            // Text command: expecting string
            char text_buf[GATTS_DEMO_CHAR_VAL_LEN_MAX + 1] = {0};
            memcpy(text_buf, param->write.value, param->write.len);
            text_buf[param->write.len] = '\0';
            ESP_LOGI(TAG, "  -> Received text: '%s'", text_buf);
            ESP_LOGI(TAG, "  -> Text length: %d characters", (int)strlen(text_buf));
            lcd_display_text(text_buf);
        } else {
            ESP_LOGW(TAG, "  -> UNKNOWN HANDLE");
        }

        // Send response if needed
        if (param->write.need_rsp) {
            ESP_LOGI(TAG, "  -> Sending response...");
            esp_ble_gatts_send_response(gatts_if, param->write.conn_id, param->write.trans_id, ESP_GATT_OK, NULL);
        }
        ESP_LOGI(TAG, "===========================");
        break;

    case ESP_GATTS_CONNECT_EVT:
        ESP_LOGI(TAG, "");
        ESP_LOGI(TAG, "╔════════════════════════════════════╗");
        ESP_LOGI(TAG, "║   FLUTTER APP CONNECTED!           ║");
        ESP_LOGI(TAG, "╚════════════════════════════════════╝");
        ESP_LOGI(TAG, "  Connection ID: %d", param->connect.conn_id);
        ESP_LOGI(TAG, "  Remote device address: %02x:%02x:%02x:%02x:%02x:%02x",
                 param->connect.remote_bda[0], param->connect.remote_bda[1],
                 param->connect.remote_bda[2], param->connect.remote_bda[3],
                 param->connect.remote_bda[4], param->connect.remote_bda[5]);
        ESP_LOGI(TAG, "  Connection interval: %d", param->connect.conn_params.interval);
        ESP_LOGI(TAG, "  Latency: %d", param->connect.conn_params.latency);
        ESP_LOGI(TAG, "  Timeout: %d", param->connect.conn_params.timeout);
        ESP_LOGI(TAG, "");
        ESP_LOGI(TAG, "Waiting for commands from Flutter app...");
        ESP_LOGI(TAG, "");

        gl_profile_tab[PROFILE_APP_IDX].conn_id = param->connect.conn_id;
        // Visual feedback: flash green
        lcd_fill_rect(panel_handle, 0, 0, LCD_H_RES, 30, COLOR_GREEN);
        vTaskDelay(300 / portTICK_PERIOD_MS);
        lcd_fill_rect(panel_handle, 0, 0, LCD_H_RES, 30, current_color);
        break;

    case ESP_GATTS_DISCONNECT_EVT:
        ESP_LOGI(TAG, "");
        ESP_LOGI(TAG, "╔════════════════════════════════════╗");
        ESP_LOGI(TAG, "║   FLUTTER APP DISCONNECTED         ║");
        ESP_LOGI(TAG, "╚════════════════════════════════════╝");
        ESP_LOGI(TAG, "  Connection ID: %d", param->disconnect.conn_id);
        ESP_LOGI(TAG, "  Reason: 0x%02x", param->disconnect.reason);
        ESP_LOGI(TAG, "  Remote device: %02x:%02x:%02x:%02x:%02x:%02x",
                 param->disconnect.remote_bda[0], param->disconnect.remote_bda[1],
                 param->disconnect.remote_bda[2], param->disconnect.remote_bda[3],
                 param->disconnect.remote_bda[4], param->disconnect.remote_bda[5]);
        ESP_LOGI(TAG, "");
        ESP_LOGI(TAG, "Restarting advertising...");
        ESP_LOGI(TAG, "");

        esp_ble_gap_start_advertising(&adv_params);
        // Visual feedback: flash red
        lcd_fill_rect(panel_handle, 0, 0, LCD_H_RES, 30, COLOR_RED);
        vTaskDelay(300 / portTICK_PERIOD_MS);
        lcd_fill_rect(panel_handle, 0, 0, LCD_H_RES, 30, current_color);
        break;

    default:
        break;
    }
}

static void gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param)
{
    if (event == ESP_GATTS_REG_EVT) {
        if (param->reg.status == ESP_GATT_OK) {
            gl_profile_tab[PROFILE_APP_IDX].gatts_if = gatts_if;
        } else {
            ESP_LOGE(TAG, "Reg app failed, app_id %04x, status %d", param->reg.app_id, param->reg.status);
            return;
        }
    }

    for (int idx = 0; idx < PROFILE_NUM; idx++) {
        if (gatts_if == ESP_GATT_IF_NONE || gatts_if == gl_profile_tab[idx].gatts_if) {
            if (gl_profile_tab[idx].gatts_cb) {
                gl_profile_tab[idx].gatts_cb(event, gatts_if, param);
            }
        }
    }
}

void init_lcd(void)
{
    ESP_LOGI(TAG, "Initializing ST7789 LCD display");

    // Initialize backlight GPIO
    gpio_config_t bk_gpio_config = {
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = 1ULL << PIN_NUM_BK_LIGHT
    };
    ESP_ERROR_CHECK(gpio_config(&bk_gpio_config));
    gpio_set_level(PIN_NUM_BK_LIGHT, LCD_BK_LIGHT_OFF_LEVEL);

    // Initialize SPI bus
    spi_bus_config_t buscfg = {
        .sclk_io_num = PIN_NUM_CLK,
        .mosi_io_num = PIN_NUM_MOSI,
        .miso_io_num = -1,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = LCD_H_RES * LCD_V_RES * sizeof(uint16_t),
    };
    ESP_ERROR_CHECK(spi_bus_initialize(LCD_HOST, &buscfg, SPI_DMA_CH_AUTO));

    ESP_LOGI(TAG, "Install panel IO");
    esp_lcd_panel_io_handle_t io_handle = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = PIN_NUM_DC,
        .cs_gpio_num = PIN_NUM_CS,
        .pclk_hz = LCD_PIXEL_CLOCK_HZ,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .spi_mode = 0,
        .trans_queue_depth = 10,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_config, &io_handle));

    ESP_LOGI(TAG, "Install ST7789 panel driver");
    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = PIN_NUM_RST,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_BGR,
        .bits_per_pixel = 16,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_st7789(io_handle, &panel_config, &panel_handle));

    ESP_LOGI(TAG, "Initialize LCD panel (90 degree rotation)");
    ESP_ERROR_CHECK(esp_lcd_panel_reset(panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_init(panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_swap_xy(panel_handle, true));  // Rotate 90 degrees
    ESP_ERROR_CHECK(esp_lcd_panel_mirror(panel_handle, false, true));  // Mirror Y for correct orientation
    ESP_ERROR_CHECK(esp_lcd_panel_invert_color(panel_handle, true));
    ESP_ERROR_CHECK(esp_lcd_panel_set_gap(panel_handle, 0, 34));  // Swap gap for rotation
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel_handle, true));

    // Turn on backlight
    gpio_set_level(PIN_NUM_BK_LIGHT, LCD_BK_LIGHT_ON_LEVEL);
    ESP_LOGI(TAG, "LCD initialized successfully!");

    // Clear to black (using direct draw, LVGL not ready yet)
    lcd_fill_rect(panel_handle, 0, 0, LCD_H_RES, LCD_V_RES, COLOR_BLACK);
    current_color = COLOR_BLACK;
}

void init_lvgl(void)
{
    ESP_LOGI(TAG, "Initializing LVGL");

    // Initialize LVGL
    lv_init();

    // Set custom tick function (use lv_tick_set_cb if available, otherwise lv_tick_custom_cb)
    #if LV_TICK_CUSTOM
    lv_tick_set_cb(lvgl_tick_get_cb);
    #endif

    // Allocate draw buffers
    const size_t buf_size = LCD_H_RES * 40; // 40 lines buffer
    buf1 = heap_caps_malloc(buf_size * sizeof(lv_color_t), MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    buf2 = heap_caps_malloc(buf_size * sizeof(lv_color_t), MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);

    if (buf1 == NULL || buf2 == NULL) {
        ESP_LOGE(TAG, "Failed to allocate LVGL draw buffers");
        return;
    }

    ESP_LOGI(TAG, "LVGL draw buffers allocated: %d bytes each", buf_size * sizeof(lv_color_t));

    // Initialize LVGL draw buffer
    lv_disp_draw_buf_init(&disp_buf, buf1, buf2, buf_size);

    // Initialize display driver
    lv_disp_drv_init(&disp_drv);
    disp_drv.hor_res = LCD_H_RES;
    disp_drv.ver_res = LCD_V_RES;
    disp_drv.flush_cb = lvgl_flush_cb;
    disp_drv.draw_buf = &disp_buf;
    disp_drv.user_data = panel_handle;

    lv_disp_t *disp = lv_disp_drv_register(&disp_drv);
    if (disp == NULL) {
        ESP_LOGE(TAG, "Failed to register LVGL display driver");
        return;
    }

    ESP_LOGI(TAG, "LVGL display driver registered");

    // Create screen and label
    screen_obj = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(screen_obj, lv_color_hex(COLOR_BLACK), 0);
    lv_scr_load(screen_obj);

    // Create text label
    text_label = lv_label_create(screen_obj);
    lv_label_set_text(text_label, "Ready");
    lv_obj_set_style_text_color(text_label, lv_color_hex(COLOR_WHITE), 0);
    lv_obj_set_style_text_font(text_label, &lv_font_montserrat_24, 0);  // 24pt font (enabled via sdkconfig)
    lv_obj_set_width(text_label, LCD_H_RES - 40);  // Wider margin for better readability
    lv_label_set_long_mode(text_label, LV_LABEL_LONG_WRAP);

    // Make label background transparent so screen color shows through
    lv_obj_set_style_bg_opa(text_label, LV_OPA_TRANSP, 0);

    lv_obj_center(text_label);

    ESP_LOGI(TAG, "LVGL UI created");

    // Start LVGL task
    xTaskCreate(lvgl_task, "LVGL_Task", 4096, NULL, 5, NULL);

    ESP_LOGI(TAG, "LVGL initialized successfully!");
}

void init_ble(void)
{
    esp_err_t ret;

    // Initialize NVS
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ret = esp_bt_controller_init(&bt_cfg);
    if (ret) {
        ESP_LOGE(TAG, "Initialize controller failed: %s", esp_err_to_name(ret));
        return;
    }

    ret = esp_bt_controller_enable(ESP_BT_MODE_BLE);
    if (ret) {
        ESP_LOGE(TAG, "Enable controller failed: %s", esp_err_to_name(ret));
        return;
    }

    ret = esp_bluedroid_init();
    if (ret) {
        ESP_LOGE(TAG, "Init bluedroid failed: %s", esp_err_to_name(ret));
        return;
    }

    ret = esp_bluedroid_enable();
    if (ret) {
        ESP_LOGE(TAG, "Enable bluedroid failed: %s", esp_err_to_name(ret));
        return;
    }

    ret = esp_ble_gatts_register_callback(gatts_event_handler);
    if (ret) {
        ESP_LOGE(TAG, "GATTS register callback failed: %s", esp_err_to_name(ret));
        return;
    }

    ret = esp_ble_gap_register_callback(gap_event_handler);
    if (ret) {
        ESP_LOGE(TAG, "GAP register callback failed: %s", esp_err_to_name(ret));
        return;
    }

    ret = esp_ble_gatts_app_register(PROFILE_APP_IDX);
    if (ret) {
        ESP_LOGE(TAG, "GATTS app register failed: %s", esp_err_to_name(ret));
        return;
    }

    esp_err_t local_mtu_ret = esp_ble_gatt_set_local_mtu(500);
    if (local_mtu_ret) {
        ESP_LOGE(TAG, "Set local MTU failed: %s", esp_err_to_name(local_mtu_ret));
    }

    ESP_LOGI(TAG, "BLE initialized successfully");
}

void app_main(void)
{
    ESP_LOGI(TAG, "Starting ESP32 IoT BLE Device with LVGL");

    // Initialize LCD first
    init_lcd();

    // Initialize LVGL
    init_lvgl();

    // Initialize BLE
    init_ble();

    ESP_LOGI(TAG, "System ready. Waiting for BLE connections...");
    ESP_LOGI(TAG, "Device name: %s", DEVICE_NAME);
    ESP_LOGI(TAG, "Color characteristic UUID: 0x%04X", GATTS_CHAR_UUID_COLOR);
    ESP_LOGI(TAG, "Text characteristic UUID: 0x%04X", GATTS_CHAR_UUID_TEXT);

    // Keep running
    while (1) {
        vTaskDelay(1000 / portTICK_PERIOD_MS);
    }
}
