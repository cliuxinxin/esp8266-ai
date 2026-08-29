#pragma once

// ---- Firmware version (shown on the first-time WiFi setup screen & /api/info) ----
#define FW_VERSION "0.4.13"

// ---- Bridge polling ----
#define BRIDGE_DEFAULT_PORT 8765
#define BRIDGE_DEFAULT_PATH "/status"
#define BRIDGE_POLL_INTERVAL_MS 5000
#define BRIDGE_HTTP_TIMEOUT_MS 3000

// ---- Weather ----
#define WEATHER_POLL_INTERVAL_MS 600000UL
#define WEATHER_STALE_MS 1800000UL
#define WEATHER_AUTO_INTERVAL_MS 900000UL
#define WEATHER_AUTO_DURATION_MS 10000UL
#define WEATHER_TEXT_W 232
#define WEATHER_TEXT_H 16
#define WEATHER_TEXT_COUNT 7

// ---- Quote ----
#define QUOTE_POLL_INTERVAL_MS 5000UL

// ---- WiFiManager ----
#define WIFI_PORTAL_AP_NAME "AI-Clock-Setup"
#define WIFI_CONFIG_FILE "/bridge_host.txt"

// ---- Backlight ----
#define BRIGHTNESS_FILE "/brightness.txt"
#define BRIGHTNESS_DEFAULT 100
#define BRIGHTNESS_PWM_FREQ 2000 // Hz; high enough to avoid visible flicker when dim

// ---- Display layout (240x240 ST7789) ----
#define SCREEN_W 240
#define SCREEN_H 240
