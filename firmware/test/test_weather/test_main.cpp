#include <cassert>

#include "weather_logic.h"

int main() {
  assert(weatherIconForCode(0) == WEATHER_CLEAR);
  assert(weatherIconForCode(2) == WEATHER_PARTLY_CLOUDY);
  assert(weatherIconForCode(3) == WEATHER_OVERCAST);
  assert(weatherIconForCode(45) == WEATHER_FOG);
  assert(weatherIconForCode(61) == WEATHER_RAIN);
  assert(weatherIconForCode(80) == WEATHER_SHOWERS);
  assert(weatherIconForCode(71) == WEATHER_SNOW);
  assert(weatherIconForCode(95) == WEATHER_THUNDERSTORM);
  assert(weatherIconForCode(999) == WEATHER_UNKNOWN);

  AutoModeInputs idle{};
  idle.weatherValid = true;
  idle.weatherWindow = true;
  assert(chooseAutoMode(idle) == AUTO_MODE_WEATHER);

  AutoModeInputs invalid = idle;
  invalid.weatherValid = false;
  assert(chooseAutoMode(invalid) == AUTO_MODE_IDLE);

  AutoModeInputs music = idle;
  music.music = true;
  assert(chooseAutoMode(music) == AUTO_MODE_MUSIC);

  AutoModeInputs working = music;
  working.working = true;
  assert(chooseAutoMode(working) == AUTO_MODE_AGENT);

  AutoModeInputs approval = working;
  approval.approval = true;
  assert(chooseAutoMode(approval) == AUTO_MODE_APPROVAL);

  return 0;
}
