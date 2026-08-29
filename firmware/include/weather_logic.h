#pragma once

enum WeatherIconKind {
  WEATHER_CLEAR,
  WEATHER_PARTLY_CLOUDY,
  WEATHER_CLOUDY,
  WEATHER_OVERCAST,
  WEATHER_FOG,
  WEATHER_RAIN,
  WEATHER_SHOWERS,
  WEATHER_SNOW,
  WEATHER_THUNDERSTORM,
  WEATHER_UNKNOWN,
};

inline WeatherIconKind weatherIconForCode(int code) {
  if (code == 0) return WEATHER_CLEAR;
  if (code == 1 || code == 2) return WEATHER_PARTLY_CLOUDY;
  if (code == 3) return WEATHER_OVERCAST;
  if (code == 45 || code == 48) return WEATHER_FOG;
  if (code >= 51 && code <= 67) return WEATHER_RAIN;
  if (code >= 80 && code <= 82) return WEATHER_SHOWERS;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return WEATHER_SNOW;
  if (code >= 95 && code <= 99) return WEATHER_THUNDERSTORM;
  return WEATHER_UNKNOWN;
}

enum AutoModeChoice {
  AUTO_MODE_IDLE,
  AUTO_MODE_WEATHER,
  AUTO_MODE_MUSIC,
  AUTO_MODE_AGENT,
  AUTO_MODE_APPROVAL,
};

struct AutoModeInputs {
  bool approval = false;
  bool working = false;
  bool music = false;
  bool weatherValid = false;
  bool weatherWindow = false;
};

inline AutoModeChoice chooseAutoMode(const AutoModeInputs &input) {
  if (input.approval) return AUTO_MODE_APPROVAL;
  if (input.working) return AUTO_MODE_AGENT;
  if (input.music) return AUTO_MODE_MUSIC;
  if (input.weatherValid && input.weatherWindow) return AUTO_MODE_WEATHER;
  return AUTO_MODE_IDLE;
}
